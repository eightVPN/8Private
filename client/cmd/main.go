package main

import (
	"encoding/hex"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/user/vpn8/client/go_core"
)

func main() {
	serverAddr := getEnv("VPN_SERVER", "127.0.0.1:51820")
	accessKey := getEnv("VPN_KEY", "epn_owner_key_default")
	hwid := getEnv("VPN_HWID", "local_mac_test")
	pskHex := getEnv("VPN_PSK", "43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38")

	psk, err := hex.DecodeString(pskHex)
	if err != nil {
		log.Fatalf("Invalid PSK hex: %v", err)
	}

	log.Printf("Starting VPN 8 Local Client...")
	log.Printf("Target Server: %s", serverAddr)

	client := go_core.NewVPNClient(serverAddr, accessKey, hwid, psk)
	
	client.SetModeChangeListener(func(mode string) {
		log.Printf("Connection mode changed to: %s", mode)
	})

	err = client.Start()
	if err != nil {
		log.Fatalf("Failed to start VPN client: %v", err)
	}

	log.Println("VPN Client is running in background. Press Ctrl+C to exit.")

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	
	// Print active mode every 5 seconds
	go func() {
		for {
			time.Sleep(5 * time.Second)
			log.Printf("Status heartbeat - Active Mode: %s", client.GetActiveMode())
		}
	}()

	<-sigChan
	log.Println("Shutting down VPN client...")
	client.Stop()
	log.Println("Shutdown complete.")
}

func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return defaultVal
}
