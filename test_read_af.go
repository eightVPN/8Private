package main

import (
	"fmt"
	"golang.org/x/sys/unix"
	"os/exec"
	"time"
)

func main() {
	fd, _ := unix.Socket(unix.AF_SYSTEM, unix.SOCK_DGRAM, 2)
	var info unix.CtlInfo
	copy(info.Name[:], "com.apple.net.utun_control")
	unix.IoctlGetCtlInfo(fd, &info)
	addr := &unix.SockaddrCtl{
		ID:   info.Id,
		Unit: 0,
	}
	unix.Connect(fd, addr)
	
	name, _ := unix.GetsockoptString(fd, unix.SYSPROTO_CONTROL, unix.UTUN_OPT_IFNAME)
	exec.Command("ifconfig", name, "inet", "10.8.0.5/16", "10.8.0.5", "up").Run()
	exec.Command("route", "add", "-host", "10.8.0.6", "-interface", name).Run()
	
	go func() {
		time.Sleep(1 * time.Second)
		exec.Command("ping", "-c", "1", "10.8.0.6").Run()
	}()
	
	buf := make([]byte, 1500)
	n, _ := unix.Read(fd, buf)
	fmt.Printf("Read %d bytes. First 4 bytes: %v\n", n, buf[:4])
}
