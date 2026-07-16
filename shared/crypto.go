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
	ErrInvalidKeySize   = errors.New("pre-shared key must be exactly 16 or 32 bytes long")
)

// Obfuscator handles packet-level encryption and decryption to hide VPN signatures.
type Obfuscator struct {
	block cipher.Block
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

	return &Obfuscator{block: block}, nil
}

// ObfuscateTo encrypts data directly into the provided dst buffer (Zero-Allocation).
// The resulting slice format: [IV/Nonce][Ciphertext]
func (o *Obfuscator) ObfuscateTo(plaintext, dst []byte) (int, error) {
	bs := o.block.BlockSize()
	iv := dst[:bs]
	if _, err := io.ReadFull(rand.Reader, iv); err != nil {
		return 0, err
	}

	stream := cipher.NewCTR(o.block, iv)
	stream.XORKeyStream(dst[bs:bs+len(plaintext)], plaintext)
	return bs + len(plaintext), nil
}

// Deobfuscate decrypts a packet in-place.
// Returns a slice of the original buffer (actual points to a subslice of ciphertext).
func (o *Obfuscator) Deobfuscate(ciphertext []byte) ([]byte, error) {
	bs := o.block.BlockSize()
	if len(ciphertext) < bs {
		return nil, ErrPacketTooShort
	}

	iv := ciphertext[:bs]
	actual := ciphertext[bs:]

	stream := cipher.NewCTR(o.block, iv)
	stream.XORKeyStream(actual, actual)

	return actual, nil
}
