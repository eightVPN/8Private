package go_core

import (
	"context"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/user/vpn8/server/daemon"
	"github.com/user/vpn8/server/db"
	"github.com/user/vpn8/shared"
)

// mockTUN simulates a TUN device for testing. Read blocks on readCh; Write sends to writeCh.
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

func TestVPNClientTUN(t *testing.T) {
	// 1. Setup Server
	dbFile := t.TempDir() + "/test_client_run.db"
	store, err := db.NewStore(dbFile)
	if err != nil {
		t.Fatalf("failed to create store: %v", err)
	}
	defer store.Close()

	userKey := "secret_key_client_test"
	_, err = store.CreateUser("test_client_user", userKey, "api_key_for_test", "user", 2, 0)
	if err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	psk := []byte("secret_key_client_test_psk_12345") // 32 bytes
	cert, err := shared.GenerateTempCertificate()
	if err != nil {
		t.Fatalf("failed to generate cert: %v", err)
	}

	server, err := daemon.NewVPNServerForTest(store, psk, cert)
	if err != nil {
		t.Fatalf("failed to create server daemon: %v", err)
	}
	
	serverTun := newMockTUN("server-tun0")
	server.SetTUN(serverTun)

	err = server.Start("127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to start server: %v", err)
	}
	defer server.Close()
	serverAddr := server.Addr().String()

	// 2. Initialize Client
	client := NewVPNClient(serverAddr, userKey, "device_hwid_test", psk)
	clientTun := newMockTUN("client-tun0")
	client.SetTUN(clientTun)

	modeChanged := make(chan string, 1)
	client.SetModeChangeListener(func(m string) {
		modeChanged <- m
	})

	// Test TUN adapter name generation
	tunName := client.GenerateVirtualTUNName()
	if tunName == "" {
		t.Error("expected non-empty random TUN name")
	}

	// Start Client
	err = client.Start()
	if err != nil {
		t.Fatalf("failed to start client: %v", err)
	}
	defer client.Stop()

	// 3. Verify Connection and Datagram Relay
	// Wait a moment for connection and authentication to complete
	time.Sleep(500 * time.Millisecond)

	if client.GetActiveMode() != "UDP" {
		t.Errorf("expected active mode UDP, got %s", client.GetActiveMode())
	}

	if client.quicConn == nil {
		t.Fatal("expected client to establish QUIC connection")
	}

	// Send a mock IP packet from the client's TUN interface
	testPkt := []byte{
		0x45, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x40, 0x11, 0x00, 0x00, // Header
		0x0a, 0x08, 0x00, 0x02, // Src IP (10.8.0.2)
		0x08, 0x08, 0x08, 0x08, // Dst IP (8.8.8.8)
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Payload
	}

	// Push packet into client's mock TUN read channel
	clientTun.readCh <- testPkt

	// The client's tunReadLoop should read this packet and send it via QUIC Datagram
	// The server's datagram loop receives it and writes it to the server's mock TUN
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	select {
	case receivedPkt := <-serverTun.writeCh:
		if len(receivedPkt) != len(testPkt) {
			t.Errorf("received packet length %d does not match sent length %d", len(receivedPkt), len(testPkt))
		}
	case <-ctx.Done():
		t.Fatal("timeout waiting for packet to arrive at server TUN")
	}
}
