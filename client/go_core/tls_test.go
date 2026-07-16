package go_core

import (
	"crypto/tls"
	"io"
	"net"
	"testing"
	"time"

	"github.com/user/vpn8/shared"
)

func TestDialChromeTLS(t *testing.T) {
	// 1. Generate in-memory self-signed certificate and launch local TLS listener
	cert, err := shared.GenerateTempCertificate()
	if err != nil {
		t.Fatalf("failed to generate test cert: %v", err)
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
	}

	listener, err := tls.Listen("tcp", "127.0.0.1:0", tlsConfig)
	if err != nil {
		t.Fatalf("failed to start local TLS listener: %v", err)
	}
	defer listener.Close()

	addr := listener.Addr().String()

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				buf := make([]byte, 1024)
				n, err := c.Read(buf)
				if err != nil {
					return
				}
				// Echo name back with standard greeting
				_, _ = c.Write(append([]byte("hello "), buf[:n]...))
			}(conn)
		}
	}()

	// 2. Connect to local server using Chrome TLS fingerprint spoofing
	c, err := DialChromeTLS(addr, "localhost", 2*time.Second)
	if err != nil {
		t.Fatalf("failed to dial Chrome TLS: %v", err)
	}
	defer c.Close()

	// 3. Verify data relay
	payload := []byte("chrome client")
	_, err = c.Write(payload)
	if err != nil {
		t.Fatalf("failed to write data: %v", err)
	}

	resp := make([]byte, 100)
	n, err := c.Read(resp)
	if err != nil && err != io.EOF {
		t.Fatalf("failed to read data: %v", err)
	}

	expected := "hello chrome client"
	if string(resp[:n]) != expected {
		t.Errorf("expected payload '%s', got '%s'", expected, string(resp[:n]))
	}
}
