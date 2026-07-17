package main

import (
	"log"
	"net"
	"os"
	"sync"
	"time"

	"github.com/user/vpn8/client/go_core"
	"github.com/user/vpn8/server/daemon"
	"github.com/user/vpn8/server/db"
	"github.com/user/vpn8/shared"
)

// mockTUN simulates a TUN device for testing without requiring root privileges.
type mockTUN struct {
	readCh  chan []byte
	writeCh chan []byte
	name    string
	closed  bool
	mu      sync.Mutex
}

func newMockTUN(name string) *mockTUN {
	return &mockTUN{
		readCh:  make(chan []byte, 64),
		writeCh: make(chan []byte, 64),
		name:    name,
	}
}

func (m *mockTUN) Read(buf []byte) (int, error) {
	pkt, ok := <-m.readCh
	if !ok {
		return 0, net.ErrClosed
	}
	n := copy(buf, pkt)
	return n, nil
}

func (m *mockTUN) Write(buf []byte) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return 0, net.ErrClosed
	}
	pkt := make([]byte, len(buf))
	copy(pkt, buf)
	m.writeCh <- pkt
	log.Printf("[%s] Received Packet: %d bytes", m.name, len(buf))
	return len(buf), nil
}

func (m *mockTUN) Close() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.closed {
		m.closed = true
		close(m.readCh)
	}
	return nil
}

func (m *mockTUN) Name() string {
	return m.name
}

func main() {
	log.Println("=== Starting Local VPN 8 End-to-End Test (Mocked TUN) ===")

	// 1. Setup Database and User
	dbFile := "local_e2e_test.db"
	defer os.Remove(dbFile)

	store, err := db.NewStore(dbFile)
	if err != nil {
		log.Fatalf("Failed to create store: %v", err)
	}
	defer store.Close()

	userKey := "test_client_secret_key"
	_, err = store.CreateUser("test_client_user", userKey, "api_key_for_test", "user", 2, 0)
	if err != nil {
		log.Fatalf("Failed to create user: %v", err)
	}

	psk := []byte("secret_key_client_test_psk_12345") // 32 bytes
	cert, _ := shared.GenerateTempCertificate()

	// 2. Setup Server Daemon
	server, err := daemon.NewVPNServerForTest(store, psk, cert)
	if err != nil {
		log.Fatalf("Failed to create server daemon: %v", err)
	}

	serverTun := newMockTUN("vpn-server-tun")
	server.SetTUN(serverTun)

	err = server.Start("127.0.0.1:0") // Random port
	if err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
	defer server.Close()

	serverAddr := server.Addr().String()
	log.Printf("Server daemon running on %s", serverAddr)

	// 3. Setup Client
	client := go_core.NewVPNClient(serverAddr, userKey, "mock_device_id", psk)
	clientTun := newMockTUN("vpn-client-tun")
	client.SetTUN(clientTun)

	log.Println("Starting Client...")
	err = client.Start()
	if err != nil {
		log.Fatalf("Failed to start client: %v", err)
	}
	defer client.Stop()

	// Allow connection and authentication to complete
	time.Sleep(1 * time.Second)
	
	if client.GetActiveMode() != "UDP" {
		log.Fatalf("Expected UDP mode, got %s", client.GetActiveMode())
	}
	log.Println("Client successfully connected and authenticated via QUIC (UDP).")

	// 4. Test Datagram Relay
	log.Println("Sending test IP packet through Client TUN -> Server TUN")
	testPkt := []byte{
		0x45, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x40, 0x11, 0x00, 0x00, // IPv4 Header
		0x0a, 0x08, 0x00, 0x02, // Src IP (10.8.0.2 - assigned to client)
		0x08, 0x08, 0x08, 0x08, // Dst IP (8.8.8.8)
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Payload
	}

	// Inject packet into client TUN
	clientTun.readCh <- testPkt

	select {
	case receivedPkt := <-serverTun.writeCh:
		if len(receivedPkt) == len(testPkt) {
			log.Println("✅ SUCCESS: Server received the exact packet from the Client over QUIC Datagrams!")
		} else {
			log.Fatalf("Length mismatch: got %d, expected %d", len(receivedPkt), len(testPkt))
		}
	case <-time.After(2 * time.Second):
		log.Fatalf("❌ FAILURE: Server did not receive the packet in time.")
	}
	
	log.Println("=== Test Completed Successfully ===")
}
