package main

import (
	"encoding/hex"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/user/vpn8/client/go_core"
)

var (
	apiAddr      = flag.String("api", "127.0.0.1:51821", "Local API listen address")
	parentPid    = flag.Int("pid", 0, "Parent process PID to monitor for auto-shutdown")
	globalClient *go_core.VPNClient
	clientMutex  sync.Mutex
)

type ConnectRequest struct {
	ServerAddr string `json:"serverAddr"`
	AccessKey  string `json:"accessKey"`
	Hwid       string `json:"hwid"`
	PskHex     string `json:"pskHex"`
}

type StatusResponse struct {
	Running    bool   `json:"running"`
	ActiveMode string `json:"activeMode"`
	RxBytes    uint64 `json:"rxBytes"`
	TxBytes    uint64 `json:"txBytes"`
}

func main() {
	flag.Parse()

	log.Println("Starting VPN 8 Local Daemon...")
	log.Printf("Listening on API: %s", *apiAddr)

	// If a parent PID is provided, start the watchdog
	if *parentPid > 0 {
		log.Printf("Watchdog enabled for Parent PID: %d", *parentPid)
		go pidWatchdog(*parentPid)
	}

	http.HandleFunc("/connect", handleConnect)
	http.HandleFunc("/disconnect", handleDisconnect)
	http.HandleFunc("/status", handleStatus)

	go func() {
		if err := http.ListenAndServe(*apiAddr, nil); err != nil {
			log.Fatalf("API Server crash: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	<-sigChan
	log.Println("Shutting down daemon...")
	stopVPN()
	os.Exit(0)
}

func pidWatchdog(pid int) {
	for {
		// On Unix systems, sending signal 0 checks if the process exists
		process, err := os.FindProcess(pid)
		if err != nil {
			log.Printf("Parent process %d not found. Exiting.", pid)
			os.Exit(0)
		}
		err = process.Signal(syscall.Signal(0))
		if err != nil {
			log.Printf("Parent process %d has exited. Daemon shutting down.", pid)
			os.Exit(0)
		}
		time.Sleep(2 * time.Second)
	}
}

func handleConnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ConnectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON payload", http.StatusBadRequest)
		return
	}

	psk, err := hex.DecodeString(req.PskHex)
	if err != nil || len(psk) != 32 {
		http.Error(w, "Invalid PSK hex or not 32 bytes", http.StatusBadRequest)
		return
	}

	clientMutex.Lock()
	defer clientMutex.Unlock()

	if globalClient != nil && globalClient.IsRunning() {
		http.Error(w, "VPN is already running", http.StatusConflict)
		return
	}

	globalClient = go_core.NewVPNClient(req.ServerAddr, req.AccessKey, req.Hwid, psk)

	err = globalClient.Start()
	if err != nil {
		http.Error(w, "Failed to start VPN: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"connected"}`))
}

func handleDisconnect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	stopVPN()

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"disconnected"}`))
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	clientMutex.Lock()
	defer clientMutex.Unlock()

	resp := StatusResponse{
		Running:    false,
		ActiveMode: "None",
	}

	if globalClient != nil && globalClient.IsRunning() {
		resp.Running = true
		resp.ActiveMode = globalClient.GetActiveMode()
		resp.RxBytes = globalClient.GetRxBytes()
		resp.TxBytes = globalClient.GetTxBytes()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func stopVPN() {
	clientMutex.Lock()
	defer clientMutex.Unlock()
	if globalClient != nil {
		globalClient.Stop()
		globalClient = nil
	}
}
