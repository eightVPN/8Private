//go:build darwin

package shared

import (
	"fmt"
	"os/exec"

	"golang.org/x/sys/unix"
)

const (
	// utunControl is the kernel control name for utun devices.
	utunControl = "com.apple.net.utun_control"

	// sysprotoControl is the PF_SYSTEM protocol number for kernel controls.
	sysprotoControl = 2

	// utunOptIfname is the socket option to retrieve the assigned interface name.
	utunOptIfname = 2

	// afHeaderSize is the size of the address-family header prepended by macOS utun.
	afHeaderSize = 4
)

// afIPv4Header is the 4-byte header that must be prepended to every IPv4
// packet written to a utun device: AF_INET = 2.
var afIPv4Header = [afHeaderSize]byte{0, 0, 0, 2}

// darwinTUN implements TUNDevice for macOS via utun.
type darwinTUN struct {
	fd   int
	name string
}

// CreateTUN creates and configures a utun device on macOS.
//
// It opens a PF_SYSTEM socket, resolves the utun kernel control ID, connects
// with Unit 0 (auto-assign), retrieves the assigned interface name, and
// configures the interface via ifconfig.
func CreateTUN(cfg TUNConfig) (TUNDevice, error) {
	if cfg.MTU == 0 {
		cfg.MTU = DefaultMTU
	}

	// 1. Create a PF_SYSTEM datagram socket for kernel control.
	fd, err := unix.Socket(unix.AF_SYSTEM, unix.SOCK_DGRAM, sysprotoControl)
	if err != nil {
		return nil, fmt.Errorf("socket(AF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL): %w", err)
	}

	// 2. Resolve the utun kernel control ID.
	ctlInfo := &unix.CtlInfo{}
	copy(ctlInfo.Name[:], utunControl)
	if err := unix.IoctlCtlInfo(fd, ctlInfo); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("ioctl CTLIOCGINFO: %w", err)
	}

	// 3. Connect with Unit=0 to let the kernel auto-assign the next utunN.
	sa := &unix.SockaddrCtl{
		ID:   ctlInfo.Id,
		Unit: 0,
	}
	if err := unix.Connect(fd, sa); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("connect utun: %w", err)
	}

	// 4. Retrieve the kernel-assigned interface name (e.g. "utun3").
	ifName, err := unix.GetsockoptString(fd, sysprotoControl, utunOptIfname)
	if err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("getsockopt UTUN_OPT_IFNAME: %w", err)
	}

	// 5. Configure the interface via ifconfig.
	addr := cfg.Address.String()
	cidrAddr := fmt.Sprintf("%s/%d", addr, cfg.CIDR)
	mtu := fmt.Sprintf("%d", cfg.MTU)

	if err := exec.Command("ifconfig", ifName, "inet", cidrAddr, addr, "mtu", mtu, "up").Run(); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("ifconfig %s inet %s %s mtu %s up: %w", ifName, cidrAddr, addr, mtu, err)
	}

	// 6. Set up default routing
	if len(cfg.ServerIP) > 0 {
		serverIPStr := cfg.ServerIP.String()
		// Find default gateway
		gwOut, _ := exec.Command("sh", "-c", "route -n get default | awk '/gateway/ {print $2}'").Output()
		gw := string(gwOut)
		if len(gw) > 0 && gw[len(gw)-1] == '\n' {
			gw = gw[:len(gw)-1]
		}

		if gw != "" {
			// Route server traffic to original gateway so the encrypted tunnel packets don't loop
			out, err := exec.Command("route", "add", "-host", serverIPStr, gw).CombinedOutput()
			fmt.Printf("Route host to GW: %v %s\n", err, string(out))
		}

		// Route all other traffic to utun interface (0.0.0.0/1 and 128.0.0.0/1)
		out1, err1 := exec.Command("route", "add", "-net", "0.0.0.0/1", "-interface", ifName).CombinedOutput()
		fmt.Printf("Route 0.0.0.0/1: %v %s\n", err1, string(out1))
		out2, err2 := exec.Command("route", "add", "-net", "128.0.0.0/1", "-interface", ifName).CombinedOutput()
		fmt.Printf("Route 128.0.0.0/1: %v %s\n", err2, string(out2))
	}

	return &darwinTUN{fd: fd, name: ifName}, nil
}

// Read reads a single packet from the utun device, stripping the 4-byte
// address-family header that macOS prepends to every packet.
func (t *darwinTUN) Read(buf []byte) (int, error) {
	// Use a slightly larger buffer to accommodate the AF header.
	raw := make([]byte, len(buf)+afHeaderSize)
	n, err := unix.Read(t.fd, raw)
	if err != nil {
		return 0, err
	}
	if n <= afHeaderSize {
		return 0, fmt.Errorf("utun read: packet too short (%d bytes)", n)
	}
	// Strip the 4-byte AF header and copy the IP packet into the caller's buffer.
	copied := copy(buf, raw[afHeaderSize:n])
	return copied, nil
}

// Write writes a single packet to the utun device, prepending the 4-byte
// AF_INET header that macOS requires.
func (t *darwinTUN) Write(buf []byte) (int, error) {
	raw := make([]byte, afHeaderSize+len(buf))
	copy(raw[:afHeaderSize], afIPv4Header[:])
	copy(raw[afHeaderSize:], buf)
	n, err := unix.Write(t.fd, raw)
	if err != nil {
		return 0, err
	}
	// Return the number of payload bytes written (exclude AF header).
	if n < afHeaderSize {
		return 0, fmt.Errorf("utun write: short write (%d bytes)", n)
	}
	return n - afHeaderSize, nil
}

// Close closes the utun socket and removes routes.
func (t *darwinTUN) Close() error {
	_ = exec.Command("route", "delete", "-net", "0.0.0.0/1", "-interface", t.name).Run()
	_ = exec.Command("route", "delete", "-net", "128.0.0.0/1", "-interface", t.name).Run()
	return unix.Close(t.fd)
}

// Name returns the kernel-assigned interface name (e.g. "utun3").
func (t *darwinTUN) Name() string {
	return t.name
}

// Compile-time interface check.
var _ TUNDevice = (*darwinTUN)(nil)
