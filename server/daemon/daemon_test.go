package daemon

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/quic-go/quic-go"
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

// newMockTUN creates a mock TUN with buffered channels.
func newMockTUN() *mockTUN {
	return &mockTUN{
		readCh:  make(chan []byte, 64),
		writeCh: make(chan []byte, 64),
		name:    "mock-tun0",
	}
}

// Read blocks until a packet is available on readCh or the channel is closed.
func (m *mockTUN) Read(buf []byte) (int, error) {
	pkt, ok := <-m.readCh
	if !ok {
		return 0, net.ErrClosed
	}
	n := copy(buf, pkt)
	return n, nil
}

// Write copies the packet and sends it to writeCh for test assertions.
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

// Close marks the device as closed and closes the readCh to unblock readers.
func (m *mockTUN) Close() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.closed {
		m.closed = true
		close(m.readCh)
	}
	return nil
}

// Name returns the mock device name.
func (m *mockTUN) Name() string {
	return m.name
}

// makeIPv4Packet constructs a minimal valid IPv4 packet with the given src/dst/protocol/payload.
// Header is 20 bytes (no options), total length = 20 + len(payload).
func makeIPv4Packet(src, dst net.IP, protocol byte, payload []byte) []byte {
	src4 := src.To4()
	dst4 := dst.To4()
	totalLen := 20 + len(payload)

	pkt := make([]byte, totalLen)
	pkt[0] = 0x45               // Version=4, IHL=5 (20 bytes)
	pkt[1] = 0                  // DSCP/ECN
	binary.BigEndian.PutUint16(pkt[2:4], uint16(totalLen)) // Total Length
	binary.BigEndian.PutUint16(pkt[4:6], 0)                // Identification
	binary.BigEndian.PutUint16(pkt[6:8], 0)                // Flags + Fragment Offset
	pkt[8] = 64                 // TTL
	pkt[9] = protocol           // Protocol
	// pkt[10:12] = checksum (left zero for testing)
	copy(pkt[12:16], src4)
	copy(pkt[16:20], dst4)
	copy(pkt[20:], payload)

	return pkt
}

// setupTestServer creates a test VPN server with a mock TUN, a temporary SQLite store,
// a test user, and starts the server on a free local port.
// Returns the server, mock TUN, server address, user access key, and a cleanup function.
func setupTestServer(t *testing.T) (*VPNServer, *mockTUN, string, string, func()) {
	t.Helper()

	dbFile := t.TempDir() + "/test_daemon.db"
	store, err := db.NewStore(dbFile)
	if err != nil {
		t.Fatalf("failed to create store: %v", err)
	}

	userKey := "test_key_daemon_32chars_pad_here"
	_, err = store.CreateUser("testuser", userKey, "", "user", 2, 0)
	if err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	psk := []byte("this_is_a_very_secure_secret_key") // 32 bytes
	cert, err := shared.GenerateTempCertificate()
	if err != nil {
		t.Fatalf("failed to generate certificate: %v", err)
	}

	server, err := NewVPNServerForTest(store, psk, cert)
	if err != nil {
		t.Fatalf("failed to create VPN server: %v", err)
	}

	tun := newMockTUN()
	server.SetTUN(tun)

	if err := server.Start("127.0.0.1:0"); err != nil {
		t.Fatalf("failed to start server: %v", err)
	}

	// Start TUN read loop since SetTUN was called after Start.
	go server.tunReadLoop()

	addr := server.Addr().String()

	cleanup := func() {
		server.Close()
		store.Close()
		os.Remove(dbFile)
	}

	return server, tun, addr, userKey, cleanup
}

// dialServer creates an obfuscated QUIC client connection to the test server.
func dialServer(t *testing.T, addr string, psk []byte) *quic.Conn {
	t.Helper()


	clientRaw, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen on client socket: %v", err)
	}
	t.Cleanup(func() { clientRaw.Close() })

	tlsConfig := &tls.Config{
		InsecureSkipVerify: true,
		NextProtos:         []string{"h3"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams:      true,
		HandshakeIdleTimeout: 5 * time.Second,
	}

	udpAddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		t.Fatalf("failed to resolve address: %v", err)
	}

	conn, err := quic.Dial(context.Background(), clientRaw, udpAddr, tlsConfig, quicConfig)
	if err != nil {
		t.Fatalf("failed to dial server: %v", err)
	}

	t.Cleanup(func() { conn.CloseWithError(0, "test done") })

	return conn
}

// authenticateClient opens a stream, sends auth, and returns the decoded response.
func authenticateClient(t *testing.T, conn *quic.Conn, key, hwid string) AuthResponse {
	t.Helper()

	stream, err := conn.OpenStreamSync(context.Background())
	if err != nil {
		t.Fatalf("failed to open control stream: %v", err)
	}
	defer stream.Close()

	req := AuthRequest{Key: key, HWID: hwid}
	if err := json.NewEncoder(stream).Encode(req); err != nil {
		t.Fatalf("failed to send auth request: %v", err)
	}

	var resp AuthResponse
	if err := json.NewDecoder(stream).Decode(&resp); err != nil {
		t.Fatalf("failed to decode auth response: %v", err)
	}

	return resp
}

func TestVPNDaemonAuth(t *testing.T) {
	_, _, addr, userKey, cleanup := setupTestServer(t)
	defer cleanup()

	psk := []byte("this_is_a_very_secure_secret_key")
	conn := dialServer(t, addr, psk)

	resp := authenticateClient(t, conn, userKey, "test_hwid_001")

	if resp.Status != "success" {
		t.Fatalf("expected status 'success', got %q: %s", resp.Status, resp.Message)
	}
	if resp.AssignedIP == "" {
		t.Fatal("expected non-empty assigned IP")
	}
	if resp.ServerIP != "10.8.0.1" {
		t.Fatalf("expected server IP '10.8.0.1', got %q", resp.ServerIP)
	}
	if resp.Subnet == "" {
		t.Fatal("expected non-empty subnet")
	}
	if resp.MTU != shared.DefaultMTU {
		t.Fatalf("expected MTU %d, got %d", shared.DefaultMTU, resp.MTU)
	}

	// Verify the assigned IP is within the pool.
	assignedIP := net.ParseIP(resp.AssignedIP)
	if assignedIP == nil {
		t.Fatalf("failed to parse assigned IP: %s", resp.AssignedIP)
	}
	if !assignedIP.Equal(assignedIP.To4()) || assignedIP.Equal(net.ParseIP("10.8.0.1")) {
		t.Fatalf("assigned IP %s is invalid (server IP or not IPv4)", resp.AssignedIP)
	}
}

func TestVPNDaemonDatagramRelay(t *testing.T) {
	_, tun, addr, userKey, cleanup := setupTestServer(t)
	defer cleanup()

	psk := []byte("this_is_a_very_secure_secret_key")
	conn := dialServer(t, addr, psk)

	resp := authenticateClient(t, conn, userKey, "test_hwid_relay")
	if resp.Status != "success" {
		t.Fatalf("auth failed: %s", resp.Message)
	}

	clientIP := net.ParseIP(resp.AssignedIP).To4()
	externalIP := net.ParseIP("8.8.8.8").To4()
	payload := []byte("hello tunnel")
	pkt := makeIPv4Packet(clientIP, externalIP, 17, payload)

	pubIP, _, _ := net.SplitHostPort(addr)
	dataServerAddr, _ := net.ResolveUDPAddr("udp", fmt.Sprintf("%s:%d", pubIP, resp.DataPort))
	obf, _ := shared.NewObfuscator(psk)
	dataRawConn, _ := net.ListenPacket("udp", "127.0.0.1:0")
	dataConn := shared.NewObfuscatedConn(dataRawConn, obf)
	defer dataConn.Close()

	if _, err := dataConn.WriteTo(pkt, dataServerAddr); err != nil {
		t.Fatalf("failed to send packet: %v", err)
	}

	select {
	case received := <-tun.writeCh:
		if len(received) != len(pkt) {
			t.Fatalf("TUN received %d bytes, expected %d", len(received), len(pkt))
		}
		dstInPkt := net.IP(received[16:20])
		if !dstInPkt.Equal(externalIP) {
			t.Fatalf("packet dst IP mismatch: got %s, want %s", dstInPkt, externalIP)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("timeout waiting for packet on mock TUN")
	}
}

func TestVPNDaemonReverseRelay(t *testing.T) {
	_, tun, addr, userKey, cleanup := setupTestServer(t)
	defer cleanup()

	psk := []byte("this_is_a_very_secure_secret_key")
	conn := dialServer(t, addr, psk)

	resp := authenticateClient(t, conn, userKey, "test_hwid_reverse")
	if resp.Status != "success" {
		t.Fatalf("auth failed: %s", resp.Message)
	}

	clientIP := net.ParseIP(resp.AssignedIP).To4()
	externalIP := net.ParseIP("1.1.1.1").To4()
	
	pubIP, _, _ := net.SplitHostPort(addr)
	dataServerAddr, _ := net.ResolveUDPAddr("udp", fmt.Sprintf("%s:%d", pubIP, resp.DataPort))
	obf, _ := shared.NewObfuscator(psk)
	dataRawConn, _ := net.ListenPacket("udp", "127.0.0.1:0")
	dataConn := shared.NewObfuscatedConn(dataRawConn, obf)
	defer dataConn.Close()

	// Send a dummy packet to register our dataAddr with the server.
	dummyPkt := makeIPv4Packet(clientIP, externalIP, 17, []byte("ping"))
	_, _ = dataConn.WriteTo(dummyPkt, dataServerAddr)

	time.Sleep(100 * time.Millisecond) // wait for server to process

	// Simulate return packet from TUN
	payload := []byte("reverse packet")
	pkt := makeIPv4Packet(externalIP, clientIP, 17, payload)
	tun.readCh <- pkt

	_ = dataRawConn.SetReadDeadline(time.Now().Add(3 * time.Second))
	buf := make([]byte, 2048)
	n, _, err := dataConn.ReadFrom(buf)
	if err != nil {
		t.Fatalf("failed to receive packet from server: %v", err)
	}
	data := buf[:n]

	if len(data) != len(pkt) {
		t.Fatalf("received %d bytes, expected %d", len(data), len(pkt))
	}

	srcInPkt := net.IP(data[12:16])
	if !srcInPkt.Equal(externalIP) {
		t.Fatalf("relayed packet src IP mismatch: got %s, want %s", srcInPkt, externalIP)
	}
}

func TestActiveProbing(t *testing.T) {
	_, _, addr, _, cleanup := setupTestServer(t)
	defer cleanup()

	// Open a plain (non-obfuscated) UDP socket to simulate an active prober.
	probeSocket, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to open probing socket: %v", err)
	}
	defer probeSocket.Close()

	udpAddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		t.Fatalf("failed to resolve addr: %v", err)
	}

	// Send unauthenticated garbage.
	_, err = probeSocket.WriteTo([]byte("GET / HTTP/1.1\r\n\r\n"), udpAddr)
	if err != nil {
		t.Fatalf("failed to write probe: %v", err)
	}

	// The server should silently drop it. No response expected.
	_ = probeSocket.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	buf := make([]byte, 1024)
	_, _, err = probeSocket.ReadFrom(buf)
	if err == nil {
		t.Fatal("expected server to ignore unauthenticated probe, but received a response")
	}
}
