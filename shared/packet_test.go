package shared

import (
	"encoding/binary"
	"net"
	"testing"
)

// buildIPv4Packet constructs a minimal valid 20-byte IPv4 header with the
// given parameters. No options or payload are included.
func buildIPv4Packet(srcIP, dstIP net.IP, protocol uint8, totalLen uint16) []byte {
	pkt := make([]byte, 20)

	// Version (4) + IHL (5 = 20 bytes, no options).
	pkt[0] = (4 << 4) | 5

	// Total length.
	binary.BigEndian.PutUint16(pkt[2:4], totalLen)

	// Protocol.
	pkt[9] = protocol

	// Source and destination IPs.
	copy(pkt[12:16], srcIP.To4())
	copy(pkt[16:20], dstIP.To4())

	return pkt
}

func TestParseIPv4Header(t *testing.T) {
	srcIP := net.IPv4(10, 0, 0, 1).To4()
	dstIP := net.IPv4(10, 0, 0, 2).To4()
	pkt := buildIPv4Packet(srcIP, dstIP, ProtoTCP, 40)

	hdr, err := ParseIPv4Header(pkt)
	if err != nil {
		t.Fatalf("ParseIPv4Header returned unexpected error: %v", err)
	}
	if hdr.Version != 4 {
		t.Errorf("Version = %d, want 4", hdr.Version)
	}
	if hdr.IHL != 5 {
		t.Errorf("IHL = %d, want 5", hdr.IHL)
	}
	if hdr.TotalLen != 40 {
		t.Errorf("TotalLen = %d, want 40", hdr.TotalLen)
	}
	if hdr.Protocol != ProtoTCP {
		t.Errorf("Protocol = %d, want %d (TCP)", hdr.Protocol, ProtoTCP)
	}
	if !hdr.SrcIP.Equal(srcIP) {
		t.Errorf("SrcIP = %s, want %s", hdr.SrcIP, srcIP)
	}
	if !hdr.DstIP.Equal(dstIP) {
		t.Errorf("DstIP = %s, want %s", hdr.DstIP, dstIP)
	}
}

func TestParseIPv4Header_TooSmall(t *testing.T) {
	pkt := make([]byte, 19) // One byte short of minimum.
	_, err := ParseIPv4Header(pkt)
	if err != ErrPacketTooSmall {
		t.Errorf("got error %v, want ErrPacketTooSmall", err)
	}
}

func TestParseIPv4Header_NotIPv4(t *testing.T) {
	pkt := make([]byte, 20)
	pkt[0] = (6 << 4) | 5 // Version 6, IHL 5.
	_, err := ParseIPv4Header(pkt)
	if err != ErrNotIPv4 {
		t.Errorf("got error %v, want ErrNotIPv4", err)
	}
}

func TestDstIPFromPacket(t *testing.T) {
	srcIP := net.IPv4(192, 168, 1, 10).To4()
	dstIP := net.IPv4(192, 168, 1, 20).To4()
	pkt := buildIPv4Packet(srcIP, dstIP, ProtoUDP, 28)

	got, err := DstIPFromPacket(pkt)
	if err != nil {
		t.Fatalf("DstIPFromPacket returned unexpected error: %v", err)
	}

	// Also verify against the full parse to ensure consistency.
	hdr, _ := ParseIPv4Header(pkt)
	if !got.Equal(dstIP) {
		t.Errorf("DstIPFromPacket = %s, want %s", got, dstIP)
	}
	if !got.Equal(hdr.DstIP) {
		t.Errorf("DstIPFromPacket (%s) != ParseIPv4Header.DstIP (%s)", got, hdr.DstIP)
	}
}

func TestSrcIPFromPacket(t *testing.T) {
	srcIP := net.IPv4(172, 16, 0, 1).To4()
	dstIP := net.IPv4(172, 16, 0, 2).To4()
	pkt := buildIPv4Packet(srcIP, dstIP, ProtoICMP, 28)

	got, err := SrcIPFromPacket(pkt)
	if err != nil {
		t.Fatalf("SrcIPFromPacket returned unexpected error: %v", err)
	}

	// Also verify against the full parse to ensure consistency.
	hdr, _ := ParseIPv4Header(pkt)
	if !got.Equal(srcIP) {
		t.Errorf("SrcIPFromPacket = %s, want %s", got, srcIP)
	}
	if !got.Equal(hdr.SrcIP) {
		t.Errorf("SrcIPFromPacket (%s) != ParseIPv4Header.SrcIP (%s)", got, hdr.SrcIP)
	}
}

func TestProtocolParsing(t *testing.T) {
	tests := []struct {
		name     string
		protocol uint8
		want     uint8
	}{
		{"ICMP", ProtoICMP, 1},
		{"TCP", ProtoTCP, 6},
		{"UDP", ProtoUDP, 17},
	}

	srcIP := net.IPv4(10, 0, 0, 1).To4()
	dstIP := net.IPv4(10, 0, 0, 2).To4()

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pkt := buildIPv4Packet(srcIP, dstIP, tt.protocol, 20)
			hdr, err := ParseIPv4Header(pkt)
			if err != nil {
				t.Fatalf("ParseIPv4Header returned unexpected error: %v", err)
			}
			if hdr.Protocol != tt.want {
				t.Errorf("Protocol = %d, want %d", hdr.Protocol, tt.want)
			}
		})
	}
}
