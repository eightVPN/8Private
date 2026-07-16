package main

/*
#include <stdint.h>

// Declare the C wrapper function from api_export.go
extern void callSwiftWritePacketCallback(const void* packet, int length);
*/
import "C"
import (
	"errors"
	"unsafe"
)

// AppExtTUN implements shared.TUNDevice by passing packets between Go and Swift (Apple NetworkExtension).
type AppExtTUN struct {
	readChan chan []byte
	closed   bool
}

// NewAppExtTUN creates a new TUN interface for App Extensions.
func NewAppExtTUN() *AppExtTUN {
	return &AppExtTUN{
		// Buffer enough packets to prevent blocking during bursts
		readChan: make(chan []byte, 1024),
	}
}

// Read blocks until Swift pushes a packet into readChan.
func (t *AppExtTUN) Read(buf []byte) (int, error) {
	if t.closed {
		return 0, errors.New("tun is closed")
	}

	packet, ok := <-t.readChan
	if !ok {
		return 0, errors.New("tun read channel closed")
	}

	copied := copy(buf, packet)
	return copied, nil
}

// Write pushes a packet from Go (from the VPN) back to Swift (to the OS IP stack).
func (t *AppExtTUN) Write(buf []byte) (int, error) {
	if t.closed {
		return 0, errors.New("tun is closed")
	}

	// We must pass a C pointer to Swift. Cgo requires C bytes to be allocated or passed directly
	// if we don't hold onto it. Since we are calling a synchronous callback, we can pass a pointer
	// to the Go slice data directly.
	ptr := unsafe.Pointer(&buf[0])
	length := C.int(len(buf))

	// Call the C wrapper which invokes the Swift function pointer
	C.callSwiftWritePacketCallback(ptr, length)

	return len(buf), nil
}

func (t *AppExtTUN) Close() error {
	t.closed = true
	close(t.readChan)
	return nil
}

func (t *AppExtTUN) Name() string {
	return "app_ext_tun0"
}

// PushPacketFromSwift is called by the C-exported API when Swift provides a new outbound packet.
func (t *AppExtTUN) PushPacketFromSwift(data []byte) {
	if t.closed {
		return
	}
	// Non-blocking write to avoid locking up Swift if Go is busy
	select {
	case t.readChan <- data:
	default:
		// Drop packet if the channel is full to prevent deadlocks
	}
}
