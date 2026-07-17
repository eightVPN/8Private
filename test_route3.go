package main

import (
	"fmt"
	"os/exec"
)

func main() {
	out, err := exec.Command("route", "delete", "-net", "0.0.0.0", "-netmask", "128.0.0.0").CombinedOutput()
	fmt.Printf("del out: %s, err: %v\n", out, err)
}
