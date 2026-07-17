package main

import (
	"encoding/hex"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"

	"github.com/user/vpn8/server/api"
	"github.com/user/vpn8/server/daemon"
	"github.com/user/vpn8/server/db"
	"github.com/user/vpn8/shared"
)

func main() {
	log.Println("Starting VPN 8 Server Backend...")

	// 1. Read configurations from Environment Variables
	vpnAddr := getEnv("VPN_ADDR", "0.0.0.0:51820")
	dataPortStr := getEnv("VPN_DATA_PORT", "51821")
	apiAddr := getEnv("API_ADDR", "0.0.0.0:8080")
	apiKey := getEnv("API_KEY", "vpn8_admin_default_token_9988")
	pskHex := getEnv("VPN_PSK", "43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38") // default hex key
	dbPath := getEnv("DB_PATH", "vpn8.db")
	tunName := getEnv("TUN_NAME", "vpn8-tun0")
	subnet := getEnv("VPN_SUBNET", "10.8.0.0/16")
	outIface := getEnv("OUT_IFACE", "") // empty = auto-detect
	enableNAT := getEnvBool("ENABLE_NAT", true)
	maxClientsStr := getEnv("MAX_CLIENTS", "0")

	maxClients, err := strconv.Atoi(maxClientsStr)
	if err != nil {
		maxClients = 0 // auto-detect
	}
	
	dataPort, err := strconv.Atoi(dataPortStr)
	if err != nil {
		dataPort = 51821
	}

	psk, err := hex.DecodeString(pskHex)
	if err != nil || len(psk) != 32 {
		log.Fatalf("Invalid VPN_PSK hex key (must decode to 32 bytes): %v", err)
	}

	// 2. Initialize Database Store
	store, err := db.NewStore(dbPath)
	if err != nil {
		log.Fatalf("Failed to initialize SQLite store: %v", err)
	}
	defer store.Close()

	// 3. Auto-provision default Owner key if no users exist
	users, err := store.ListUsers()
	if err == nil && len(users) == 0 {
		log.Println("Database is empty. Auto-provisioning default Owner account...")
		ownerKey := "epn_owner_key_default"
		u, err := store.CreateUser("default_owner", ownerKey, apiKey, "owner", 5, 0)
		if err != nil {
			log.Printf("Failed to provision default owner: %v", err)
		} else {
			log.Printf("-----------------------------------------------------------------")
			log.Printf("Provisioned Owner User: %s", u.Username)
			log.Printf("Connection and Admin Key: %s (Write this down!)", u.AccessKey)
			log.Printf("-----------------------------------------------------------------")
		}
	}

	// 4. Generate dynamic transient TLS Certificate for QUIC
	cert, err := shared.GenerateTempCertificate()
	if err != nil {
		log.Fatalf("Failed to generate ephemeral TLS certificate: %v", err)
	}

	// 5. Initialize and Start TUN-based VPN Daemon
	vpnServer, err := daemon.NewVPNServer(daemon.ServerConfig{
		Store:      store,
		PSK:        psk,
		TLSCert:    cert,
		TUNName:    tunName,
		Subnet:     subnet,
		MaxClients: maxClients,
		EnableNAT:  enableNAT,
		OutIface:   outIface,
		DataPort:   dataPort,
	})
	if err != nil {
		log.Fatalf("Failed to initialize VPN daemon: %v", err)
	}
	defer vpnServer.Close()

	err = vpnServer.Start(vpnAddr)
	if err != nil {
		log.Fatalf("Failed to start VPN daemon on %s: %v", vpnAddr, err)
	}
	log.Printf("VPN Daemon listening on UDP %s (TUN: %s, Subnet: %s, NAT: %v)",
		vpnAddr, tunName, subnet, enableNAT)

	// 6. Initialize and Start REST API Server
	apiServer := api.NewServer(store, apiKey)
	httpServer := &http.Server{
		Addr:    apiAddr,
		Handler: apiServer.Handler(),
	}

	go func() {
		log.Printf("REST API listening on TCP %s", apiAddr)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("API Server crash: %v", err)
		}
	}()

	// 7. Wait for system termination signals for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Received shutdown signal. Exiting gracefully...")
	_ = httpServer.Close()
	_ = vpnServer.Close()
	log.Println("VPN 8 Server terminated successfully.")
}

// getEnv returns the value of an environment variable or a default value.
func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return defaultVal
}

// getEnvBool returns a boolean from an environment variable ("true"/"1" = true).
func getEnvBool(key string, defaultVal bool) bool {
	val, ok := os.LookupEnv(key)
	if !ok {
		return defaultVal
	}
	return val == "true" || val == "1" || val == "yes"
}
