// Package daemon implements the core VPN server daemon with TUN + QUIC datagram tunneling.
package daemon

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/user/vpn8/server/auth"
	"github.com/user/vpn8/server/db"
	"github.com/user/vpn8/shared"
)

// AuthRequest represents the authentication JSON payload sent by the client.
type AuthRequest struct {
	Key  string `json:"key"`
	HWID string `json:"hwid"`
}

// AuthResponse represents the authentication response payload sent back by the server.
type AuthResponse struct {
	Status     string `json:"status"`
	Message    string `json:"message,omitempty"`
	AssignedIP string `json:"assigned_ip,omitempty"`
	ServerIP   string `json:"server_ip,omitempty"`
	Subnet     string `json:"subnet,omitempty"`
	MTU        int    `json:"mtu,omitempty"`
	DataPort   int    `json:"data_port,omitempty"`
	APIKey     string `json:"api_key,omitempty"`
}

// ClientSession tracks a connected VPN client and its allocated resources.
type ClientSession struct {
	conn        *quic.Conn
	user        *db.User
	assignedIP  net.IP
	clientAddr  net.Addr
	addrMu      sync.RWMutex
	cancel      context.CancelFunc
	upLimiter   *TokenBucket
	downLimiter *TokenBucket
}

// TokenBucket implements a thread-safe token bucket rate limiter.
type TokenBucket struct {
	rate       float64 // bytes per second
	capacity   float64
	tokens     float64
	lastUpdate time.Time
	mu         sync.Mutex
}

// NewTokenBucket creates a new TokenBucket given a rate in Mbps.
func NewTokenBucket(rateMbps int) *TokenBucket {
	// Mbps to bytes per second
	rate := float64(rateMbps) * 1000000 / 8
	return &TokenBucket{
		rate:       rate,
		capacity:   rate, // 1 second burst capacity
		tokens:     rate,
		lastUpdate: time.Now(),
	}
}

// Allow checks if n bytes can be processed, consuming tokens if so.
func (tb *TokenBucket) Allow(n int) bool {
	if tb == nil || tb.rate <= 0 {
		return true // unlimited
	}

	tb.mu.Lock()
	defer tb.mu.Unlock()

	now := time.Now()
	elapsed := now.Sub(tb.lastUpdate).Seconds()
	tb.tokens += elapsed * tb.rate
	if tb.tokens > tb.capacity {
		tb.tokens = tb.capacity
	}
	tb.lastUpdate = now

	needed := float64(n)
	if tb.tokens >= needed {
		tb.tokens -= needed
		return true
	}
	return false
}

// ServerConfig holds configuration parameters for creating a VPNServer.
type ServerConfig struct {
	Store      *db.Store
	PSK        []byte
	TLSCert    tls.Certificate
	TUNName    string // e.g. "vpn8-tun0"
	Subnet     string // e.g. "10.8.0.0/16"
	MaxClients int    // 0 = auto-detect
	EnableNAT  bool
	OutIface   string // e.g. "eth0", empty = auto-detect
	DataPort   int
}

// VPNServer is the obfuscated UDP-QUIC tunneling server with TUN datagram relay.
type VPNServer struct {
	store      *db.Store
	obfuscator *shared.Obfuscator
	tlsConfig  *tls.Config
	quicConfig *quic.Config
	listener   *quic.Listener
	rawConn    net.PacketConn
	dataConn   *shared.ObfuscatedConn
	dataPort   int
	tunDev     shared.TUNDevice
	ipPool     *IPPool
	sessions   map[uint32]*ClientSession // keyed by assigned IP as uint32
	sessionsMu sync.RWMutex
	ctx        context.Context
	cancel     context.CancelFunc
	natEnabled bool
	natIface   string
	bufPool    sync.Pool // reusable packet buffers to reduce GC pressure
}

// NewVPNServer creates a fully initialized VPN server with TUN device and optional NAT.
func NewVPNServer(config ServerConfig) (*VPNServer, error) {
	obf, err := shared.NewObfuscator(config.PSK)
	if err != nil {
		return nil, fmt.Errorf("failed to create obfuscator: %w", err)
	}

	subnet := config.Subnet
	if subnet == "" {
		subnet = "10.8.0.0/16"
	}

	pool, err := NewIPPool(subnet, config.MaxClients)
	if err != nil {
		return nil, fmt.Errorf("failed to create IP pool: %w", err)
	}

	tunName := config.TUNName
	if tunName == "" {
		tunName = "vpn8-tun0"
	}

	ones, _ := pool.subnetNet.Mask.Size()
	tunDev, err := shared.CreateTUN(shared.TUNConfig{
		DevName: tunName,
		Address: pool.ServerIP(),
		CIDR:    ones,
		MTU:     shared.DefaultMTU,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create TUN device: %w", err)
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{config.TLSCert},
		NextProtos:   []string{"h3"}, // mimic HTTP/3 for stealth
	}

	quicConfig := &quic.Config{
		EnableDatagrams: true,
		KeepAlivePeriod: 15 * time.Second,
	}

	ctx, cancel := context.WithCancel(context.Background())

	srv := &VPNServer{
		store:      config.Store,
		obfuscator: obf,
		tlsConfig:  tlsConfig,
		quicConfig: quicConfig,
		tunDev:     tunDev,
		ipPool:     pool,
		sessions:   make(map[uint32]*ClientSession),
		ctx:        ctx,
		cancel:     cancel,
		natEnabled: config.EnableNAT,
		natIface:   config.OutIface,
		dataPort:   config.DataPort,
		bufPool: sync.Pool{
			New: func() any {
				buf := make([]byte, shared.DefaultMTU+100)
				return &buf
			},
		},
	}

	if config.EnableNAT {
		if err := srv.setupNAT(); err != nil {
			tunDev.Close()
			cancel()
			return nil, fmt.Errorf("failed to setup NAT: %w", err)
		}
	}

	return srv, nil
}

// NewVPNServerForTest creates a VPNServer without TUN device or NAT setup.
// Suitable for unit testing with mock TUN injection via SetTUN.
func NewVPNServerForTest(store *db.Store, psk []byte, cert tls.Certificate) (*VPNServer, error) {
	obf, err := shared.NewObfuscator(psk)
	if err != nil {
		return nil, fmt.Errorf("failed to create obfuscator: %w", err)
	}

	pool, err := NewIPPool("10.8.0.0/16", 0)
	if err != nil {
		return nil, fmt.Errorf("failed to create IP pool: %w", err)
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		NextProtos:   []string{"h3"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams: true,
		KeepAlivePeriod: 15 * time.Second,
	}

	ctx, cancel := context.WithCancel(context.Background())

	return &VPNServer{
		store:      store,
		obfuscator: obf,
		tlsConfig:  tlsConfig,
		quicConfig: quicConfig,
		ipPool:     pool,
		sessions:   make(map[uint32]*ClientSession),
		ctx:        ctx,
		cancel:     cancel,
		bufPool: sync.Pool{
			New: func() any {
				buf := make([]byte, shared.DefaultMTU+100)
				return &buf
			},
		},
	}, nil
}

// SetTUN injects a TUN device into the server. Used for testing with mock devices.
func (s *VPNServer) SetTUN(dev shared.TUNDevice) {
	s.tunDev = dev
}

// Start binds the server to the specified UDP address and begins accepting connections.
func (s *VPNServer) Start(addr string) error {
	laddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return fmt.Errorf("failed to resolve address: %w", err)
	}

	rawConn, err := net.ListenUDP("udp", laddr)
	if err != nil {
		return fmt.Errorf("failed to listen UDP: %w", err)
	}
	s.rawConn = rawConn

	// 1. Start standard QUIC Listener (Auth/Control Plane)
	listener, err := quic.Listen(rawConn, s.tlsConfig, s.quicConfig)
	if err != nil {
		rawConn.Close()
		return fmt.Errorf("failed to start QUIC listener: %w", err)
	}
	s.listener = listener

	// 2. Start Obfuscated Data Listener (Pure UDP Data Plane)
	dataAddr, err := net.ResolveUDPAddr("udp", fmt.Sprintf(":%d", s.dataPort))
	if err != nil {
		return fmt.Errorf("failed to resolve data address: %w", err)
	}
	dataRawConn, err := net.ListenUDP("udp", dataAddr)
	if err != nil {
		return fmt.Errorf("failed to listen UDP data port: %w", err)
	}
	s.dataConn = shared.NewObfuscatedConn(dataRawConn, s.obfuscator)
	s.dataPort = dataRawConn.LocalAddr().(*net.UDPAddr).Port

	go s.acceptLoop()
	go s.dataReadLoop()

	if s.tunDev != nil {
		go s.tunReadLoop()
	}

	return nil
}

// Addr returns the server's local network address, or nil if not started.
func (s *VPNServer) Addr() net.Addr {
	if s.rawConn != nil {
		return s.rawConn.LocalAddr()
	}
	return nil
}

// Close gracefully shuts down the server and releases all resources.
func (s *VPNServer) Close() error {
	s.cancel()

	if s.natEnabled {
		s.cleanupNAT()
	}

	// Terminate all client sessions.
	s.sessionsMu.Lock()
	for ip, sess := range s.sessions {
		sess.cancel()
		sess.conn.CloseWithError(0, "server shutting down")
		_ = s.ipPool.Release(sess.assignedIP)
		delete(s.sessions, ip)
	}
	s.sessionsMu.Unlock()

	var firstErr error
	if s.tunDev != nil {
		if err := s.tunDev.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if s.listener != nil {
		if err := s.listener.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if s.dataConn != nil {
		if err := s.dataConn.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if s.rawConn != nil {
		if err := s.rawConn.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}

	return firstErr
}

// acceptLoop continuously accepts incoming QUIC connections until the server context is cancelled.
func (s *VPNServer) acceptLoop() {
	for {
		conn, err := s.listener.Accept(s.ctx)
		if err != nil {
			select {
			case <-s.ctx.Done():
				return
			default:
				log.Printf("vpn8: accept error: %v", err)
				return
			}
		}
		go s.handleConnection(conn)
	}
}

// handleConnection performs authentication, IP allocation, and starts the datagram relay
// for a single client connection.
func (s *VPNServer) handleConnection(conn *quic.Conn) {
	sessCtx, sessCancel := context.WithCancel(s.ctx)
	defer sessCancel()

	defer func() {
		_ = conn.CloseWithError(0, "session terminated")
	}()

	// 1. Accept the control stream for authentication.
	stream, err := conn.AcceptStream(sessCtx)
	if err != nil {
		return
	}
	defer stream.Close()

	// 2. Read and process authentication request.
	var req AuthRequest
	if err := json.NewDecoder(stream).Decode(&req); err != nil {
		resp := AuthResponse{Status: "error", Message: "invalid auth payload"}
		_ = json.NewEncoder(stream).Encode(resp)
		return
	}

	res, err := auth.Authenticate(s.store, req.Key, req.HWID)
	if err != nil {
		resp := AuthResponse{Status: "error", Message: err.Error()}
		_ = json.NewEncoder(stream).Encode(resp)
		return
	}

	// 3. Allocate a client IP from the pool.
	assignedIP, err := s.ipPool.Allocate()
	if err != nil {
		resp := AuthResponse{Status: "error", Message: "no IPs available"}
		_ = json.NewEncoder(stream).Encode(resp)
		return
	}

	// 4. Send success response with network configuration.
	resp := AuthResponse{
		Status:     "success",
		AssignedIP: assignedIP.String(),
		ServerIP:   s.ipPool.ServerIP().String(),
		Subnet:     s.ipPool.SubnetCIDR(),
		MTU:        shared.DefaultMTU,
		DataPort:   s.dataPort,
		APIKey:     res.User.APIKey,
	}
	if err := json.NewEncoder(stream).Encode(resp); err != nil {
		_ = s.ipPool.Release(assignedIP)
		return
	}

	// 5. Register the client session.
	sess := &ClientSession{
		conn:       conn,
		user:       res.User,
		assignedIP: assignedIP,
		cancel:     sessCancel,
	}

	if res.User.RateLimit > 0 {
		sess.upLimiter = NewTokenBucket(res.User.RateLimit)
		sess.downLimiter = NewTokenBucket(res.User.RateLimit)
	}

	ipKey := binary.BigEndian.Uint32(assignedIP.To4())
	s.sessionsMu.Lock()
	s.sessions[ipKey] = sess
	s.sessionsMu.Unlock()

	// 6. Ensure cleanup on exit.
	defer func() {
		s.sessionsMu.Lock()
		delete(s.sessions, ipKey)
		s.sessionsMu.Unlock()
		_ = s.ipPool.Release(assignedIP)
	}()

	// The client's QUIC connection remains open for control messages and keep-alives.
	// We wait until the context is cancelled (server shutdown) or the connection is closed (client disconnects).
	select {
	case <-sessCtx.Done():
	case <-conn.Context().Done():
	}
}

// dataReadLoop reads raw UDP packets from dataConn (decrypted via Obfuscator),
// performs NAT traversal by updating the client's source address, and writes to TUN.
func (s *VPNServer) dataReadLoop() {
	for {
		select {
		case <-s.ctx.Done():
			return
		default:
		}

		bufPtr := s.bufPool.Get().(*[]byte)
		buf := *bufPtr

		n, addr, err := s.dataConn.ReadFrom(buf)
		if err != nil {
			s.bufPool.Put(bufPtr)
			select {
			case <-s.ctx.Done():
				return
			default:
				log.Printf("vpn8: data read error: %v", err)
				return
			}
		}

		pkt := buf[:n]

		// Parse source IP from the IPv4 header as uint32.
		srcKey, err := shared.SrcIPUint32(pkt)
		if err != nil {
			s.bufPool.Put(bufPtr)
			continue
		}

		s.sessionsMu.RLock()
		sess, ok := s.sessions[srcKey]
		s.sessionsMu.RUnlock()

		if ok {
			if sess.upLimiter != nil && !sess.upLimiter.Allow(len(pkt)) {
				// Drop packet due to rate limit
				s.bufPool.Put(bufPtr)
				continue
			}

			// Update client's NAT address for returning packets
			sess.addrMu.Lock()
			sess.clientAddr = addr
			sess.addrMu.Unlock()

			if s.tunDev != nil {
				_, err = s.tunDev.Write(pkt)
				if err != nil {
					log.Printf("vpn8: TUN write error: %v", err)
				}
			}
		}

		s.bufPool.Put(bufPtr)
	}
}

// tunReadLoop reads packets from the TUN device and routes them to the appropriate client
// via QUIC datagrams. Uses sync.Pool for buffer reuse to minimize GC pressure.
func (s *VPNServer) tunReadLoop() {
	for {
		select {
		case <-s.ctx.Done():
			return
		default:
		}

		bufPtr := s.bufPool.Get().(*[]byte)
		buf := *bufPtr

		n, err := s.tunDev.Read(buf)
		if err != nil {
			s.bufPool.Put(bufPtr)
			select {
			case <-s.ctx.Done():
				return
			default:
				log.Printf("vpn8: TUN read error: %v", err)
				return
			}
		}

		pkt := buf[:n]

		// Parse destination IP from the IPv4 header as uint32.
		dstKey, err := shared.DstIPUint32(pkt)
		if err != nil {
			s.bufPool.Put(bufPtr)
			continue
		}

		s.sessionsMu.RLock()
		sess, ok := s.sessions[dstKey]
		s.sessionsMu.RUnlock()

		if ok {
			if sess.downLimiter != nil && !sess.downLimiter.Allow(len(pkt)) {
				// Drop packet due to rate limit
				s.bufPool.Put(bufPtr)
				continue
			}

			sess.addrMu.RLock()
			clientAddr := sess.clientAddr
			sess.addrMu.RUnlock()

			if clientAddr != nil {
				_, _ = s.dataConn.WriteTo(pkt, clientAddr)
			}
		}

		s.bufPool.Put(bufPtr)
	}
}

// setupNAT configures iptables MASQUERADE and FORWARD rules for the VPN subnet.
func (s *VPNServer) setupNAT() error {
	iface := s.natIface
	if iface == "" {
		detected, err := detectOutboundInterface()
		if err != nil {
			return fmt.Errorf("failed to detect outbound interface: %w", err)
		}
		iface = detected
		s.natIface = iface
	}

	subnet := s.ipPool.SubnetCIDR()
	tunName := ""
	if s.tunDev != nil {
		tunName = s.tunDev.Name()
	}

	// Enable IP forwarding.
	cmds := [][]string{
		{"sysctl", "-w", "net.ipv4.ip_forward=1"},
		{"iptables", "-t", "nat", "-A", "POSTROUTING", "-s", subnet, "-o", iface, "-j", "MASQUERADE"},
		{"iptables", "-A", "FORWARD", "-i", tunName, "-o", iface, "-j", "ACCEPT"},
		{"iptables", "-A", "FORWARD", "-i", iface, "-o", tunName, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"},
	}

	for _, args := range cmds {
		if err := exec.Command(args[0], args[1:]...).Run(); err != nil {
			return fmt.Errorf("command %q failed: %w", strings.Join(args, " "), err)
		}
	}

	return nil
}

// cleanupNAT removes the iptables rules that were set up by setupNAT.
func (s *VPNServer) cleanupNAT() {
	subnet := s.ipPool.SubnetCIDR()
	tunName := ""
	if s.tunDev != nil {
		tunName = s.tunDev.Name()
	}
	iface := s.natIface

	cmds := [][]string{
		{"iptables", "-t", "nat", "-D", "POSTROUTING", "-s", subnet, "-o", iface, "-j", "MASQUERADE"},
		{"iptables", "-D", "FORWARD", "-i", tunName, "-o", iface, "-j", "ACCEPT"},
		{"iptables", "-D", "FORWARD", "-i", iface, "-o", tunName, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"},
	}

	for _, args := range cmds {
		_ = exec.Command(args[0], args[1:]...).Run()
	}
}

// detectOutboundInterface parses `ip route show default` to find the primary outbound interface.
func detectOutboundInterface() (string, error) {
	out, err := exec.Command("ip", "route", "show", "default").Output()
	if err != nil {
		return "", fmt.Errorf("ip route failed: %w", err)
	}

	fields := strings.Fields(string(out))
	for i, f := range fields {
		if f == "dev" && i+1 < len(fields) {
			return fields[i+1], nil
		}
	}

	return "", fmt.Errorf("could not parse default route: %s", string(out))
}
