package shared

import (
	"encoding/binary"
	"errors"
	"net"
)

var (
	// ErrPacketTooSmall is returned when the packet is shorter than the minimum IPv4 header (20 bytes).
	ErrPacketTooSmall = errors.New("packet too small for IPv4 header")

	// ErrNotIPv4 is returned when the IP version nibble is not 4.
	ErrNotIPv4 = errors.New("not an IPv4 packet")
)

// Well-known IPv4 protocol numbers.
const (
	ProtoICMP = 1
	ProtoTCP  = 6
	ProtoUDP  = 17
)

// IPv4Header holds the most commonly inspected fields of an IPv4 header.
type IPv4Header struct {
	// Version is the IP version (always 4 for valid parses).
	Version uint8

	// IHL is the Internet Header Length in 32-bit words (minimum 5 = 20 bytes).
	IHL uint8

	// TotalLen is the total packet length in bytes, including header and payload.
	TotalLen uint16

	// Protocol is the upper-layer protocol number (e.g. ProtoTCP, ProtoUDP).
	Protocol uint8

	// SrcIP is the source IPv4 address.
	SrcIP net.IP

	// DstIP is the destination IPv4 address.
	DstIP net.IP
}

// ParseIPv4Header parses the IPv4 header from the beginning of pkt.
//
// It validates the minimum length (20 bytes) and that the version nibble is 4.
// Only the most commonly used fields are extracted; options are not parsed.
func ParseIPv4Header(pkt []byte) (*IPv4Header, error) {
	if len(pkt) < 20 {
		return nil, ErrPacketTooSmall
	}

	version := pkt[0] >> 4
	if version != 4 {
		return nil, ErrNotIPv4
	}

	ihl := pkt[0] & 0x0F
	totalLen := binary.BigEndian.Uint16(pkt[2:4])
	protocol := pkt[9]

	srcIP := make(net.IP, 4)
	copy(srcIP, pkt[12:16])

	dstIP := make(net.IP, 4)
	copy(dstIP, pkt[16:20])

	return &IPv4Header{
		Version:  version,
		IHL:      ihl,
		TotalLen: totalLen,
		Protocol: protocol,
		SrcIP:    srcIP,
		DstIP:    dstIP,
	}, nil
}

// DstIPFromPacket is a fast-path helper that extracts only the destination IP
// from an IPv4 packet without allocating a full IPv4Header.
func DstIPFromPacket(pkt []byte) (net.IP, error) {
	if len(pkt) < 20 {
		return nil, ErrPacketTooSmall
	}
	if pkt[0]>>4 != 4 {
		return nil, ErrNotIPv4
	}
	ip := make(net.IP, 4)
	copy(ip, pkt[16:20])
	return ip, nil
}

// SrcIPFromPacket is a fast-path helper that extracts only the source IP
// from an IPv4 packet without allocating a full IPv4Header.
func SrcIPFromPacket(pkt []byte) (net.IP, error) {
	if len(pkt) < 20 {
		return nil, ErrPacketTooSmall
	}
	if pkt[0]>>4 != 4 {
		return nil, ErrNotIPv4
	}
	ip := make(net.IP, 4)
	copy(ip, pkt[12:16])
	return ip, nil
}
