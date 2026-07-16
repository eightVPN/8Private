package shared

import (
	"bytes"
	"crypto/rand"
	"net"
	"testing"
	"time"
)

func TestObfuscatedConn(t *testing.T) {
	// Generate key
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("failed to read rand key: %v", err)
	}

	obf, err := NewObfuscator(key)
	if err != nil {
		t.Fatalf("failed to create obfuscator: %v", err)
	}

	// Create local UDP listeners
	l1, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen l1: %v", err)
	}
	defer l1.Close()

	l2, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen l2: %v", err)
	}
	defer l2.Close()

	c1 := NewObfuscatedConn(l1, obf)
	c2 := NewObfuscatedConn(l2, obf)

	addr1 := c1.LocalAddr()
	addr2 := c2.LocalAddr()

	// Test 1: Send valid obfuscated packet
	testMsg := []byte("hello through secure packet connection")
	go func() {
		_, err := c1.WriteTo(testMsg, addr2)
		if err != nil {
			t.Errorf("failed to write: %v", err)
		}
	}()

	buf := make([]byte, 2048)
	_ = c2.SetReadDeadline(time.Now().Add(1 * time.Second))
	n, from, err := c2.ReadFrom(buf)
	if err != nil {
		t.Fatalf("failed to read: %v", err)
	}

	if !bytes.Equal(buf[:n], testMsg) {
		t.Errorf("expected %s, got %s", testMsg, buf[:n])
	}
	if from.String() != addr1.String() {
		t.Errorf("expected sender %s, got %s", addr1, from)
	}

	// Test 2: Send unauthenticated packet from a raw socket (censor probing)
	rawSender, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to create raw sender: %v", err)
	}
	defer rawSender.Close()

	probeMsg := []byte("are you a VPN server? connection handshake initial packet")
	_, err = rawSender.WriteTo(probeMsg, addr2)
	if err != nil {
		t.Fatalf("failed to send raw probe: %v", err)
	}

	// We expect ReadFrom to block or timeout because the unauthenticated probe must be silent-dropped!
	_ = c2.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	_, _, err = c2.ReadFrom(buf)
	if err == nil {
		t.Fatal("expected ReadFrom to timeout after unauthenticated probe, but it returned a packet")
	}

	// Test 3: Send valid packet again after the probe (should still go through)
	go func() {
		_, err := c1.WriteTo([]byte("valid message after probe"), addr2)
		if err != nil {
			t.Errorf("failed to write: %v", err)
		}
	}()

	_ = c2.SetReadDeadline(time.Now().Add(1 * time.Second))
	n, _, err = c2.ReadFrom(buf)
	if err != nil {
		t.Fatalf("failed to read valid packet after probe: %v", err)
	}
	if string(buf[:n]) != "valid message after probe" {
		t.Errorf("expected message, got: %s", string(buf[:n]))
	}
}
