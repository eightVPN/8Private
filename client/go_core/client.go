package go_core

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/user/vpn8/shared"
)

// AuthResponse must match the daemon's definition.
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

var sniWhitelist = []string{
	"www.microsoft.com",
	"updates.microsoft.com",
	"www.apple.com",
	"gateway.apple.com",
	"www.google.com",
	"clients3.google.com",
	"www.cloudflare.com",
	"api.stripe.com",
	"www.paypal.com",
}

type VPNClient struct {
	mu           sync.Mutex
	serverAddr   string
	accessKey    string
	apiKey       string
	hwid         string
	psk          []byte
	quicConn     *quic.Conn
	dataConn     *shared.ObfuscatedConn
	dataPort     int
	tcpConn      net.Conn
	tunDev       shared.TUNDevice
	activeMode   string
	onModeChange func(mode string)
	running      bool
	cancel       context.CancelFunc
	rxBytes      uint64
	txBytes      uint64
}

func NewVPNClient(serverAddr string, accessKey string, hwid string, psk []byte) *VPNClient {
	return &VPNClient{
		serverAddr: serverAddr,
		accessKey:  accessKey,
		hwid:       hwid,
		psk:        psk,
		activeMode: "UDP",
	}
}

func (c *VPNClient) SetModeChangeListener(cb func(string)) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.onModeChange = cb
}

func (c *VPNClient) GetActiveMode() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.activeMode
}

func (c *VPNClient) GetAPIKey() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.apiKey
}

func (c *VPNClient) GetRxBytes() uint64 {
	return atomic.LoadUint64(&c.rxBytes)
}

func (c *VPNClient) GetTxBytes() uint64 {
	return atomic.LoadUint64(&c.txBytes)
}

func (c *VPNClient) SetCustomTUN(tun shared.TUNDevice) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.tunDev = tun
}

func (c *VPNClient) GetCustomTUN() shared.TUNDevice {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.tunDev
}

func (c *VPNClient) IsRunning() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.running
}

func (c *VPNClient) Start() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.running {
		return errors.New("client is already running")
	}

	ctx, cancel := context.WithCancel(context.Background())
	c.cancel = cancel
	c.running = true

	go c.connectionWatcher(ctx)

	return nil
}

func (c *VPNClient) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.cleanup()
}

func (c *VPNClient) cleanup() {
	if c.cancel != nil {
		c.cancel()
	}
	if c.quicConn != nil {
		_ = (*c.quicConn).CloseWithError(0, "client stop")
		c.quicConn = nil
	}
	if c.dataConn != nil {
		_ = c.dataConn.Close()
		c.dataConn = nil
	}
	if c.tcpConn != nil {
		_ = c.tcpConn.Close()
		c.tcpConn = nil
	}
	if c.tunDev != nil {
		_ = c.tunDev.Close()
		c.tunDev = nil
	}
	c.running = false
}

func (c *VPNClient) selectRandomSNI() string {
	rand.Seed(time.Now().UnixNano())
	return sniWhitelist[rand.Intn(len(sniWhitelist))]
}

func (c *VPNClient) GenerateVirtualTUNName() string {
	prefixes := []string{"utun", "tun"}
	rand.Seed(time.Now().UnixNano())
	pref := prefixes[rand.Intn(len(prefixes))]
	num := rand.Intn(10)
	subnum := rand.Intn(100)
	return fmt.Sprintf("%s%d_virtual_%d", pref, num, subnum)
}

func (c *VPNClient) connectionWatcher(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
			err := c.connectUDP(ctx)
			if err != nil {
				log.Printf("UDP connection failed: %v. Swapping to TCP Fallback...", err)
				c.mu.Lock()
				c.activeMode = "TCP"
				if c.onModeChange != nil {
					go c.onModeChange("TCP")
				}
				c.mu.Unlock()

				errTCP := c.connectTCP(ctx)
				if errTCP != nil {
					log.Printf("TCP connection failed: %v. Retrying connection loop...", errTCP)
					time.Sleep(5 * time.Second)
					continue
				}
			}

			// Block until connection is lost or context cancelled
			<-ctx.Done()
			return
		}
	}
}

func (c *VPNClient) connectUDP(ctx context.Context) error {
	tlsConfig := &tls.Config{
		ServerName:         c.selectRandomSNI(),
		InsecureSkipVerify: true,
		NextProtos:         []string{"h3"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams:      true,
		HandshakeIdleTimeout: 5 * time.Second,
	}

	log.Printf("Attempting QUIC auth to server %s (SNI: %s)...", c.serverAddr, tlsConfig.ServerName)
	conn, err := quic.DialAddr(ctx, c.serverAddr, tlsConfig, quicConfig)
	if err != nil {
		return err
	}
	c.quicConn = conn

	resp, err := c.authenticateClient(ctx, conn)
	if err != nil {
		conn.CloseWithError(0, "auth failed")
		return err
	}

	log.Printf("Authenticated! Assigned IP: %s, Subnet: %s, DataPort: %d", resp.AssignedIP, resp.Subnet, resp.DataPort)
	c.mu.Lock()
	c.dataPort = resp.DataPort
	c.apiKey = resp.APIKey
	c.mu.Unlock()

	// Setup TUN Device
	if err := c.setupTUN(resp); err != nil {
		conn.CloseWithError(0, "tun setup failed")
		return fmt.Errorf("failed to setup TUN: %w", err)
	}

	// Setup Pure UDP Data Plane
	pubIP, _, err := net.SplitHostPort(c.serverAddr)
	if err != nil {
		pubIP = c.serverAddr
	}
	dataServerAddr, err := net.ResolveUDPAddr("udp", fmt.Sprintf("%s:%d", pubIP, c.dataPort))
	if err != nil {
		conn.CloseWithError(0, "data addr failed")
		return err
	}

	obf, err := shared.NewObfuscator(c.psk)
	if err != nil {
		conn.CloseWithError(0, "obfuscator failed")
		return err
	}

	dataRawConn, err := net.ListenPacket("udp", "0.0.0.0:0")
	if err != nil {
		conn.CloseWithError(0, "data listen failed")
		return err
	}
	c.dataConn = shared.NewObfuscatedConn(dataRawConn, obf)

	go c.tunToUdpLoop(ctx, dataServerAddr)
	go c.udpToTunLoop(ctx)

	// Keep connection alive
	go func() {
		<-ctx.Done()
		conn.CloseWithError(0, "context cancelled")
	}()

	return nil
}

// connectTCP provides uTLS-based fallback if UDP is blocked.
// For now, TCP tunneling of raw IP packets is a stub as per Phase 3, wait until TCP fallback is formally requested in a future phase.
func (c *VPNClient) connectTCP(ctx context.Context) error {
	return errors.New("TCP TUN fallback not yet fully implemented")
}

func (c *VPNClient) authenticateClient(ctx context.Context, conn *quic.Conn) (*AuthResponse, error) {
	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		return nil, err
	}
	defer stream.Close()

	req := struct {
		Key  string `json:"key"`
		HWID string `json:"hwid"`
	}{
		Key:  c.accessKey,
		HWID: c.hwid,
	}

	if err := json.NewEncoder(stream).Encode(req); err != nil {
		return nil, err
	}

	var resp AuthResponse
	if err := json.NewDecoder(stream).Decode(&resp); err != nil {
		return nil, err
	}

	if resp.Status != "success" {
		return nil, fmt.Errorf("auth failure: %s", resp.Message)
	}

	return &resp, nil
}

func (c *VPNClient) SetTUN(dev shared.TUNDevice) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.tunDev = dev
}

func (c *VPNClient) setupTUN(resp *AuthResponse) error {
	c.mu.Lock()
	if c.tunDev != nil {
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	// Parse CIDR prefix length (e.g. "10.8.0.0/16" -> 16)
	parts := strings.Split(resp.Subnet, "/")
	cidr := 16
	if len(parts) == 2 {
		if c, err := strconv.Atoi(parts[1]); err == nil {
			cidr = c
		}
	}

	pubIP, _, err := net.SplitHostPort(c.serverAddr)
	if err != nil {
		pubIP = c.serverAddr
	}

	var parsedPubIP net.IP
	if ip := net.ParseIP(pubIP); ip != nil {
		parsedPubIP = ip
	} else if ips, err := net.LookupIP(pubIP); err == nil && len(ips) > 0 {
		parsedPubIP = ips[0]
	}

	tunConfig := shared.TUNConfig{
		DevName: c.GenerateVirtualTUNName(),
		Address: net.ParseIP(resp.AssignedIP),
		CIDR:    cidr,
		MTU:     resp.MTU,
		ServerIP: parsedPubIP,
	}

	dev, err := shared.CreateTUN(tunConfig)
	if err != nil {
		return err
	}
	c.tunDev = dev
	return nil
}

func (c *VPNClient) tunToUdpLoop(ctx context.Context, serverAddr *net.UDPAddr) {
	buf := make([]byte, shared.DefaultMTU+100)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		if c.tunDev == nil {
			time.Sleep(100 * time.Millisecond)
			continue
		}

		n, err := c.tunDev.Read(buf)
		if err != nil {
			log.Printf("TUN Read error: %v", err)
			return
		}

		// Forward raw IP packet via pure UDP
		if _, err := c.dataConn.WriteTo(buf[:n], serverAddr); err != nil {
			log.Printf("UDP WriteTo error: %v", err)
			return
		}
		atomic.AddUint64(&c.txBytes, uint64(n))
	}
}

func (c *VPNClient) udpToTunLoop(ctx context.Context) {
	buf := make([]byte, shared.DefaultMTU+100)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		n, _, err := c.dataConn.ReadFrom(buf)
		if err != nil {
			log.Printf("UDP ReadFrom error: %v", err)
			return
		}
		atomic.AddUint64(&c.rxBytes, uint64(n))

		if c.tunDev != nil {
			if _, err := c.tunDev.Write(buf[:n]); err != nil {
				log.Printf("TUN Write error: %v", err)
			}
		}
	}
}
