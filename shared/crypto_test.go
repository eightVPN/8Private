package shared

import (
	"bytes"
	"crypto/rand"
	"testing"
)

func TestObfuscator(t *testing.T) {
	// Generate random 256-bit key
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("failed to generate random key: %v", err)
	}

	obf, err := NewObfuscator(key)
	if err != nil {
		t.Fatalf("failed to create obfuscator: %v", err)
	}

	message := []byte("hello, vpn 8 secure packet!")

	// 1. Test success case
	dst := make([]byte, 2048)
	n, err := obf.ObfuscateTo(message, dst)
	if err != nil {
		t.Fatalf("failed to obfuscate: %v", err)
	}
	ciphertext := dst[:n]

	if bytes.Equal(ciphertext, message) {
		t.Fatal("ciphertext should not be equal to plain message")
	}

	plaintext, err := obf.Deobfuscate(ciphertext)
	if err != nil {
		t.Fatalf("failed to deobfuscate (len %d): %v", len(ciphertext), err)
	}

	if !bytes.Equal(plaintext, message) {
		t.Errorf("expected %s, got %s", message, plaintext)
	}

	// 2. Test invalid key size
	_, err = NewObfuscator(key[:10])
	if err == nil {
		t.Error("expected error for invalid key size, got nil")
	}

	// 3. Test corrupted packet authentication failure
	ciphertext[len(ciphertext)-1] ^= 0xFF
	_, err = obf.Deobfuscate(ciphertext)
	if err == nil {
		t.Error("expected decryption failure for corrupted packet, got nil")
	}
}
