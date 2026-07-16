//go:build linux

package shared

import (
	"fmt"
	"os"
	"os/exec"
	"unsafe"

	"golang.org/x/sys/unix"
)

const (
	// iffTUN selects TUN (layer 3) mode.
	iffTUN uint16 = 0x0001
	// iffNoPi disables the 4-byte packet-info header.
	iffNoPi uint16 = 0x1000
	// tunSetIFF is the ioctl request code for TUNSETIFF.
	tunSetIFF = 0x400454ca
)

// ifReq is the ifreq structure passed to the TUNSETIFF ioctl.
type ifReq struct {
	Name  [16]byte
	Flags uint16
	_     [22]byte // padding to match kernel struct size
}

// linuxTUN implements TUNDevice for Linux.
type linuxTUN struct {
	file *os.File
	name string
}

// CreateTUN creates and configures a TUN device on Linux.
//
// It opens /dev/net/tun, issues a TUNSETIFF ioctl to allocate the interface,
// then shells out to `ip` to assign the address, set the MTU, and bring the
// link up.
func CreateTUN(cfg TUNConfig) (TUNDevice, error) {
	if cfg.MTU == 0 {
		cfg.MTU = DefaultMTU
	}

	// 1. Open the TUN clone device.
	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/net/tun: %w", err)
	}

	// 2. Prepare and issue the TUNSETIFF ioctl.
	var req ifReq
	copy(req.Name[:], cfg.DevName)
	req.Flags = iffTUN | iffNoPi

	if _, _, errno := unix.Syscall(
		unix.SYS_IOCTL,
		uintptr(fd),
		uintptr(tunSetIFF),
		uintptr(unsafe.Pointer(&req)),
	); errno != 0 {
		unix.Close(fd)
		return nil, fmt.Errorf("ioctl TUNSETIFF: %w", errno)
	}

	// Extract the kernel-assigned name (null-terminated inside the [16]byte).
	devName := string(req.Name[:])
	for i, b := range req.Name {
		if b == 0 {
			devName = string(req.Name[:i])
			break
		}
	}

	// Wrap the fd in an *os.File so Read/Write/Close work normally.
	file := os.NewFile(uintptr(fd), "/dev/net/tun")
	if file == nil {
		unix.Close(fd)
		return nil, fmt.Errorf("os.NewFile returned nil for fd %d", fd)
	}

	// 3. Configure the interface via `ip` commands.
	addr := fmt.Sprintf("%s/%d", cfg.Address.String(), cfg.CIDR)

	if err := exec.Command("ip", "addr", "add", addr, "dev", devName).Run(); err != nil {
		file.Close()
		return nil, fmt.Errorf("ip addr add %s dev %s: %w", addr, devName, err)
	}
	if err := exec.Command("ip", "link", "set", devName, "mtu", fmt.Sprintf("%d", cfg.MTU)).Run(); err != nil {
		file.Close()
		return nil, fmt.Errorf("ip link set mtu %d dev %s: %w", cfg.MTU, devName, err)
	}
	if err := exec.Command("ip", "link", "set", devName, "up").Run(); err != nil {
		file.Close()
		return nil, fmt.Errorf("ip link set up dev %s: %w", devName, err)
	}

	return &linuxTUN{file: file, name: devName}, nil
}

// Read reads a single packet from the TUN device.
func (t *linuxTUN) Read(buf []byte) (int, error) {
	return t.file.Read(buf)
}

// Write writes a single packet to the TUN device.
func (t *linuxTUN) Write(buf []byte) (int, error) {
	return t.file.Write(buf)
}

// Close closes the underlying file descriptor and tears down the TUN device.
func (t *linuxTUN) Close() error {
	return t.file.Close()
}

// Name returns the kernel-assigned interface name (e.g. "tun0").
func (t *linuxTUN) Name() string {
	return t.name
}

// Compile-time interface check.
var _ TUNDevice = (*linuxTUN)(nil)

