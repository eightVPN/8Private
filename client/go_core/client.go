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
	hwid         string
	psk          []byte
	quicConn     *quic.Conn
	rawConn      net.PacketConn
	tcpConn      net.Conn
	tunDev       shared.TUNDevice
	activeMode   string
	onModeChange func(mode string)
	running      bool
	cancel       context.CancelFunc
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
	if c.rawConn != nil {
		_ = c.rawConn.Close()
		c.rawConn = nil
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
	obf, err := shared.NewObfuscator(c.psk)
	if err != nil {
		return err
	}

	rConn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	c.rawConn = rConn

	obfConn := shared.NewObfuscatedConn(rConn, obf)

	udpAddr, err := net.ResolveUDPAddr("udp", c.serverAddr)
	if err != nil {
		obfConn.Close()
		return err
	}

	tlsConfig := &tls.Config{
		ServerName:         c.selectRandomSNI(),
		InsecureSkipVerify: true,
		NextProtos:         []string{"h3"},
	}

	quicConfig := &quic.Config{
		EnableDatagrams:      true,
		HandshakeIdleTimeout: 5 * time.Second,
	}

	log.Printf("Attempting UDP connection to server %s (SNI: %s)...", c.serverAddr, tlsConfig.ServerName)
	conn, err := quic.Dial(ctx, obfConn, udpAddr, tlsConfig, quicConfig)
	if err != nil {
		obfConn.Close()
		return err
	}
	c.quicConn = conn

	resp, err := c.authenticateClient(ctx, conn)
	if err != nil {
		conn.CloseWithError(0, "auth failed")
		return err
	}

	log.Printf("Authenticated! Assigned IP: %s, Subnet: %s", resp.AssignedIP, resp.Subnet)

	// Setup TUN Device
	if err := c.setupTUN(resp); err != nil {
		conn.CloseWithError(0, "tun setup failed")
		return fmt.Errorf("failed to setup TUN: %w", err)
	}

	go c.tunReadLoop(ctx, conn)
	go c.quicReadLoop(ctx, conn)

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

	tunConfig := shared.TUNConfig{
		DevName: c.GenerateVirtualTUNName(),
		Address: net.ParseIP(resp.AssignedIP),
		CIDR:    cidr,
		MTU:     resp.MTU,
		ServerIP: net.ParseIP(resp.ServerIP),
	}

	dev, err := shared.CreateTUN(tunConfig)
	if err != nil {
		return err
	}
	c.tunDev = dev
	return nil
}

func (c *VPNClient) tunReadLoop(ctx context.Context, conn *quic.Conn) {
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

		// Forward raw IP packet via QUIC Datagram
		if err := conn.SendDatagram(buf[:n]); err != nil {
			log.Printf("QUIC SendDatagram error: %v", err)
			return
		}
	}
}

func (c *VPNClient) quicReadLoop(ctx context.Context, conn *quic.Conn) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		data, err := conn.ReceiveDatagram(ctx)
		if err != nil {
			log.Printf("QUIC ReceiveDatagram error: %v", err)
			return
		}

		if c.tunDev != nil {
			if _, err := c.tunDev.Write(data); err != nil {
				log.Printf("TUN Write error: %v", err)
			}
		}
	}
}
