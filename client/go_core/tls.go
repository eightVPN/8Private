// Package go_core implements the client-side VPN engine and tunnel controllers.
package go_core

import (
	"net"
	"time"

	utls "github.com/refraction-networking/utls"
)

// DialChromeTLS connects to the target server address over TCP and completes a TLS handshake
// that mimics Google Chrome's client signature (JA3/JA4 fingerprinting).
func DialChromeTLS(addr string, sni string, timeout time.Duration) (net.Conn, error) {
	dialer := &net.Dialer{
		Timeout: timeout,
	}

	conn, err := dialer.Dial("tcp", addr)
	if err != nil {
		return nil, err
	}

		// We use InsecureSkipVerify since we are connecting to our private VPN server
	// that utilizes dynamically generated, self-signed certificates.
	tlsConfig := &utls.Config{
		ServerName:         sni,
		InsecureSkipVerify: true,
	}

	// Wrap TCP socket inside a uTLS client mimicking Google Chrome v120
	uConn := utls.UClient(conn, tlsConfig, utls.HelloChrome_Auto)

	err = uConn.SetDeadline(time.Now().Add(timeout))
	if err != nil {
		uConn.Close()
		return nil, err
	}

	err = uConn.Handshake()
	if err != nil {
		uConn.Close()
		return nil, err
	}

	// Clear deadline after handshake
	_ = uConn.SetDeadline(time.Time{})

	return uConn, nil
}
