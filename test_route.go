package main

import (
	"fmt"
	"os/exec"
)

func main() {
	out, err := exec.Command("route", "add", "-inet6", "2001:db8::/32", "::1", "-blackhole").CombinedOutput()
	fmt.Printf("blackhole out: %s, err: %v\n", out, err)
}
