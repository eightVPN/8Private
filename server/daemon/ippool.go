// Package daemon implements the core VPN server daemon with TUN + QUIC datagram tunneling.
package daemon

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
)

// Sentinel errors for the IP pool.
var (
	ErrPoolExhausted = errors.New("ip pool exhausted: no addresses available")
	ErrIPNotManaged  = errors.New("ip address is not managed by this pool")
)

// IPPool manages dynamic allocation of client IPs within a VPN subnet.
// Thread-safe via sync.Mutex.
type IPPool struct {
	mu        sync.Mutex
	subnetIP  net.IP   // network address (e.g. 10.8.0.0)
	subnetNet *net.IPNet
	serverIP  net.IP   // first usable (e.g. 10.8.0.1)
	baseIP    uint32   // numeric value of network address
	maxClient int      // maximum allocatable client IPs
	allocated map[uint32]bool
	nextHint  uint32   // offset from baseIP to start scanning (2..maxClient+1)
}

// NewIPPool creates an IP pool for the given CIDR (e.g. "10.8.0.0/16").
// maxClients controls the upper bound of allocatable addresses. Pass 0 for auto-detection.
func NewIPPool(cidr string, maxClients int) (*IPPool, error) {
	ip, ipNet, err := net.ParseCIDR(cidr)
	if err != nil {
		return nil, fmt.Errorf("invalid CIDR %q: %w", cidr, err)
	}

	// Only IPv4 subnets are supported.
	ip4 := ip.To4()
	if ip4 == nil {
		return nil, fmt.Errorf("only IPv4 subnets are supported, got %q", cidr)
	}

	ones, bits := ipNet.Mask.Size()
	if bits != 32 {
		return nil, fmt.Errorf("unexpected mask bits: %d", bits)
	}

	// Total usable host addresses = 2^(32-ones) - 2 (exclude network and broadcast).
	totalUsable := (1 << (bits - ones)) - 2
	if totalUsable < 1 {
		return nil, fmt.Errorf("subnet %q too small for any hosts", cidr)
	}

	if maxClients <= 0 {
		maxClients = detectMaxClients()
	}

	// Server takes offset 1, clients get offsets 2..totalUsable.
	// Maximum client slots = totalUsable - 1 (server occupies one slot).
	maxAvail := totalUsable - 1 // slots available for clients
	if maxClients > maxAvail {
		maxClients = maxAvail
	}

	baseIP := ipToUint32(ipNet.IP.To4())
	serverIP := uint32ToIP(baseIP + 1)

	return &IPPool{
		subnetIP:  ipNet.IP.To4(),
		subnetNet: ipNet,
		serverIP:  serverIP,
		baseIP:    baseIP,
		maxClient: maxClients,
		allocated: make(map[uint32]bool),
		nextHint:  2, // first client offset
	}, nil
}

// Allocate assigns the next available IP address from the pool.
// Returns ErrPoolExhausted if no addresses are available.
func (p *IPPool) Allocate() (net.IP, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if len(p.allocated) >= p.maxClient {
		return nil, ErrPoolExhausted
	}

	// Scan from nextHint, wrapping around the client range [2, maxClient+1].
	start := p.nextHint
	for i := 0; i < p.maxClient; i++ {
		offset := start + uint32(i)
		// Wrap within the client range: offsets 2 through maxClient+1.
		if offset > uint32(p.maxClient)+1 {
			offset = offset - uint32(p.maxClient) + 1
		}
		candidate := p.baseIP + offset
		if !p.allocated[candidate] {
			p.allocated[candidate] = true
			p.nextHint = offset + 1
			if p.nextHint > uint32(p.maxClient)+1 {
				p.nextHint = 2
			}
			return uint32ToIP(candidate), nil
		}
	}

	return nil, ErrPoolExhausted
}

// Release returns a previously allocated IP back to the pool.
// Returns ErrIPNotManaged if the IP is not within the managed range.
func (p *IPPool) Release(ip net.IP) error {
	ip4 := ip.To4()
	if ip4 == nil {
		return ErrIPNotManaged
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	num := ipToUint32(ip4)
	offset := num - p.baseIP

	// Valid client offsets are [2, maxClient+1].
	if offset < 2 || offset > uint32(p.maxClient)+1 {
		return ErrIPNotManaged
	}

	if !p.allocated[num] {
		return ErrIPNotManaged
	}

	delete(p.allocated, num)

	// Reset hint to freed offset for faster re-allocation.
	p.nextHint = offset
	return nil
}

// IsManaged reports whether the given IP falls within the pool's subnet.
func (p *IPPool) IsManaged(ip net.IP) bool {
	return p.subnetNet.Contains(ip)
}

// ServerIP returns the server's IP address (first usable address in the subnet).
func (p *IPPool) ServerIP() net.IP {
	return net.IP(append([]byte(nil), p.serverIP...))
}

// SubnetCIDR returns the CIDR notation of the managed subnet.
func (p *IPPool) SubnetCIDR() string {
	ones, _ := p.subnetNet.Mask.Size()
	return fmt.Sprintf("%s/%d", p.subnetIP.String(), ones)
}

// PoolSize returns the maximum number of client IPs that can be allocated.
func (p *IPPool) PoolSize() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.maxClient
}

// AllocatedCount returns the number of currently allocated client IPs.
func (p *IPPool) AllocatedCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.allocated)
}

// ipToUint32 converts a 4-byte IPv4 address to a uint32 using big-endian byte order.
func ipToUint32(ip net.IP) uint32 {
	return binary.BigEndian.Uint32(ip)
}

// uint32ToIP converts a uint32 back to a net.IP (IPv4).
func uint32ToIP(n uint32) net.IP {
	ip := make(net.IP, 4)
	binary.BigEndian.PutUint32(ip, n)
	return ip
}

// detectMaxClients computes a dynamic pool size based on available CPU cores and RAM.
// Formula: min(NumCPU*256, ramGB*128, 65533). Falls back to 1024 on detection failure.
func detectMaxClients() int {
	cpuBased := runtime.NumCPU() * 256

	ramGB := detectRAMGB()
	ramBased := ramGB * 128

	const maxSubnet = 65533 // maximum usable in /16 minus server

	best := cpuBased
	if ramBased > 0 && ramBased < best {
		best = ramBased
	}
	if best > maxSubnet {
		best = maxSubnet
	}
	if best <= 0 {
		best = 1024
	}

	return best
}

// detectRAMGB attempts to read total system RAM in GB.
// Linux: parses /proc/meminfo. Other platforms: returns 0 (triggers fallback).
func detectRAMGB() int {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0
	}

	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "MemTotal:") {
			fields := strings.Fields(line)
			if len(fields) < 2 {
				return 0
			}
			kb, err := strconv.ParseInt(fields[1], 10, 64)
			if err != nil {
				return 0
			}
			gb := int(kb / (1024 * 1024))
			if gb < 1 {
				gb = 1
			}
			return gb
		}
	}

	return 0
}
