package main

import (
	"fmt"
	"os/exec"
)

func main() {
	out1, err1 := exec.Command("ifconfig", "utun0", "inet6", "fd00::1/64", "up").CombinedOutput()
	fmt.Printf("ifconfig out: %s, err: %v\n", out1, err1)

	out2, err2 := exec.Command("route", "add", "-inet6", "::/1", "-interface", "utun0").CombinedOutput()
	fmt.Printf("route out: %s, err: %v\n", out2, err2)

	// Clean up
	exec.Command("route", "delete", "-inet6", "::/1").Run()
	exec.Command("ifconfig", "utun0", "inet6", "fd00::1", "delete").Run()
}
