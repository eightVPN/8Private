package shared

import (
	"net"
)

// ObfuscatedConn wraps a net.PacketConn and obfuscates/deobfuscates all network packets in transit.
type ObfuscatedConn struct {
	net.PacketConn
	obf *Obfuscator
}

// NewObfuscatedConn returns a wrapped packet connection using the provided Obfuscator.
func NewObfuscatedConn(conn net.PacketConn, obf *Obfuscator) *ObfuscatedConn {
	return &ObfuscatedConn{
		PacketConn: conn,
		obf:        obf,
	}
}

// ReadFrom reads an obfuscated packet from the wire, deobfuscates it, and copies the plaintext
// into the provided slice. If authentication fails, the packet is silently discarded (blackholed),
// and the loop continues to read the next packet.
func (c *ObfuscatedConn) ReadFrom(p []byte) (int, net.Addr, error) {
	// Allocate a buffer large enough for a maximum UDP payload
	tempBuf := make([]byte, 65535)

	for {
		rawN, rawAddr, err := c.PacketConn.ReadFrom(tempBuf)
		if err != nil {
			return 0, nil, err
		}

		plaintext, errDeobf := c.obf.Deobfuscate(tempBuf[:rawN])
		if errDeobf != nil {
			// Audit log omitted to prevent active-probing logging side channels.
			// Silently drop and continue listening.
			continue
		}

		n := copy(p, plaintext)
		return n, rawAddr, nil
	}
}

// WriteTo encrypts the plaintext payload and writes the obfuscated packet to the target address.
// It returns the logical number of bytes written (matching len(p)) on success.
func (c *ObfuscatedConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	ciphertext, err := c.obf.Obfuscate(p)
	if err != nil {
		return 0, err
	}

	_, err = c.PacketConn.WriteTo(ciphertext, addr)
	if err != nil {
		return 0, err
	}

	// Conform to PacketConn.WriteTo contract by returning the length of the written plaintext slice
	return len(p), nil
}
