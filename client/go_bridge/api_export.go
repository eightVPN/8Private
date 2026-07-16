package main

/*
#include <stdint.h>
#include <stdlib.h>

// Typedef for the Swift callback function that receives packets from Go.
typedef void (*WritePacketCallback)(const void* packet, int length);

// Global callback variable (we only need one per VPN extension since it's a singleton)
WritePacketCallback swiftWritePacketCallback = NULL;

// Wrapper function to call the function pointer (Cgo requires wrappers to call C function pointers)
static inline void callSwiftWritePacketCallback(const void* packet, int length) {
    if (swiftWritePacketCallback != NULL) {
        swiftWritePacketCallback(packet, length);
    }
}
*/
import "C"
import (
	"encoding/hex"
	"log"
	"unsafe"
	"github.com/user/vpn8/client/go_core"
)

func main() {}


// swiftWritePacketCallback is implemented in C and called from Go.
// We must declare it in a separate C file or just pass it in during StartVPN.

var globalClient *go_core.VPNClient

//export SetSwiftWriteCallback
func SetSwiftWriteCallback(cb C.WritePacketCallback) {
	C.swiftWritePacketCallback = cb
}

//export StartVPN
func StartVPN(serverAddr *C.char, accessKey *C.char, hwid *C.char, pskHex *C.char) C.int {
	if globalClient != nil && globalClient.IsRunning() {
		return -1 // Already running
	}

	goServerAddr := C.GoString(serverAddr)
	goAccessKey := C.GoString(accessKey)
	goHwid := C.GoString(hwid)
	goPskHex := C.GoString(pskHex)

	psk, err := hex.DecodeString(goPskHex)
	if err != nil {
		log.Printf("Invalid PSK hex: %v", err)
		return -2
	}

	globalClient = go_core.NewVPNClient(goServerAddr, goAccessKey, goHwid, psk)

	// Inject the custom AppExtension TUNDevice into the client.
	tun := NewAppExtTUN()
	globalClient.SetCustomTUN(tun)

	err = globalClient.Start()
	if err != nil {
		log.Printf("Failed to start VPN client: %v", err)
		return -3
	}

	return 0 // Success
}

//export StopVPN
func StopVPN() {
	if globalClient != nil {
		globalClient.Stop()
		globalClient = nil
	}
}

//export PushPacketToGo
func PushPacketToGo(packet unsafe.Pointer, length C.int) {
	// Swift calls this when NEPacketTunnelFlow gives it a packet.
	if globalClient != nil && globalClient.IsRunning() {
		tun, ok := globalClient.GetCustomTUN().(*AppExtTUN)
		if ok {
			// Copy the packet data from C to Go
			data := C.GoBytes(packet, length)
			tun.PushPacketFromSwift(data)
		}
	}
}
