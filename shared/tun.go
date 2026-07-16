package shared

import "net"

// DefaultMTU is the default MTU for the TUN device (smaller than 1500 to account for QUIC+encryption overhead).
const DefaultMTU = 1400

// TUNDevice represents a platform-independent virtual network (TUN) device.
type TUNDevice interface {
	// Read reads a packet from the TUN device into buf and returns the number of bytes read.
	Read(buf []byte) (int, error)

	// Write writes a packet to the TUN device and returns the number of bytes written.
	Write(buf []byte) (int, error)

	// Close tears down the TUN device and releases associated resources.
	Close() error

	// Name returns the OS-assigned name of the TUN interface (e.g. "tun0", "utun3").
	Name() string
}

// TUNConfig contains parameters for creating a TUN device.
type TUNConfig struct {
	// DevName is the requested device name (e.g. "tun0"). May be ignored on platforms
	// that auto-assign names (macOS utun).
	DevName string

	// Address is the IPv4 address to assign to the TUN interface.
	Address net.IP

	// CIDR is the prefix length for the TUN subnet (e.g. 24 for /24).
	CIDR int

	// MTU is the Maximum Transmission Unit. Use DefaultMTU if zero.
	MTU int
}
