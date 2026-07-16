// Package shared provides common utilities and data structures for both client and server.
package shared

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"io"
)

// ErrInvalidPacket size or authentication failure errors.
var (
	ErrPacketTooShort   = errors.New("packet is too short to be deobfuscated")
	ErrDecryptionFailed = errors.New("failed to decrypt or authenticate packet")
	ErrInvalidKeySize   = errors.New("pre-shared key must be exactly 16 or 32 bytes long")
)

// Obfuscator handles packet-level encryption and decryption to hide VPN signatures.
type Obfuscator struct {
	aead cipher.AEAD
}

// NewObfuscator initializes an Obfuscator using a pre-shared key (PSK).
// The key size must be 16 bytes (AES-128) or 32 bytes (AES-256).
func NewObfuscator(psk []byte) (*Obfuscator, error) {
	if len(psk) != 16 && len(psk) != 32 {
		return nil, ErrInvalidKeySize
	}

	block, err := aes.NewCipher(psk)
	if err != nil {
		return nil, err
	}

	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}

	return &Obfuscator{aead: aead}, nil
}

// Obfuscate wraps a plaintext packet by encrypting it.
// The resulting slice format: [12-byte Nonce][Ciphertext + 16-byte Auth Tag]
func (o *Obfuscator) Obfuscate(plaintext []byte) ([]byte, error) {
	nonce := make([]byte, o.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}

	// Allocate buffer with exact size: nonce size + plaintext length + GCM overhead (16 bytes)
	out := make([]byte, len(nonce), len(nonce)+len(plaintext)+o.aead.Overhead())
	copy(out, nonce)

	return o.aead.Seal(out, nonce, plaintext, nil), nil
}

// Deobfuscate decrypts and authenticates a packet.
// Returns an error if the packet is too short or if authentication fails.
func (o *Obfuscator) Deobfuscate(ciphertext []byte) ([]byte, error) {
	nonceSize := o.aead.NonceSize()
	if len(ciphertext) < nonceSize+o.aead.Overhead() {
		return nil, ErrPacketTooShort
	}

	nonce := ciphertext[:nonceSize]
	actualCiphertext := ciphertext[nonceSize:]

	plaintext, err := o.aead.Open(nil, nonce, actualCiphertext, nil)
	if err != nil {
		return nil, ErrDecryptionFailed
	}

	return plaintext, nil
}
