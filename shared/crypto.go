// Package shared provides common utilities and data structures for both client and server.
package shared

import (
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"io"
	mrand "math/rand/v2"

	"golang.org/x/crypto/chacha20poly1305"
)

// ErrInvalidPacket size or authentication failure errors.
var (
	ErrPacketTooShort = errors.New("packet is too short to be deobfuscated")
	ErrInvalidKeySize = errors.New("pre-shared key must be exactly 32 bytes long")
	ErrInvalidMagic   = errors.New("invalid protocol magic bytes")
	ErrAuthFailed     = errors.New("AEAD authentication failed")
)

// STUNMagic is a fake STUN-like magic cookie to camouflage the traffic.
const STUNMagic uint32 = 0x2112A442

// Obfuscator handles packet-level encryption and decryption to hide VPN signatures.
type Obfuscator struct {
	aead cipher.AEAD
}

// NewObfuscator initializes an Obfuscator using a pre-shared key (PSK).
// The key size must be exactly 32 bytes.
func NewObfuscator(psk []byte) (*Obfuscator, error) {
	if len(psk) != 32 {
		return nil, ErrInvalidKeySize
	}

	key := sha256.Sum256(psk)
	aead, err := chacha20poly1305.NewX(key[:])
	if err != nil {
		return nil, err
	}

	return &Obfuscator{aead: aead}, nil
}

// ObfuscateTo encrypts data directly into the provided dst buffer.
// It adds a Fake STUN Header, 24-byte Nonce, Length-prefixed payload, and random padding.
// The resulting slice format: [STUN Header (4)][Nonce (24)][Ciphertext (Len (2) + Payload + Pad)]
func (o *Obfuscator) ObfuscateTo(plaintext, dst []byte) (int, error) {
	const headerSize = 4 + chacha20poly1305.NonceSizeX
	if len(dst) < headerSize+len(plaintext)+2+o.aead.Overhead() {
		return 0, errors.New("destination buffer too small")
	}

	// 1. Write Fake STUN Magic
	binary.BigEndian.PutUint32(dst[0:4], STUNMagic)

	// 2. Generate Random 24-byte Nonce
	nonce := dst[4:headerSize]
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return 0, err
	}

	// 3. Prepare Plaintext with Length Prefix and Padding
	// Max random padding of up to 64 bytes (or less if MTU limited)
	padLen := mrand.IntN(64)
	innerLen := 2 + len(plaintext) + padLen
	
	// We'll construct the inner plaintext in a temporary slice at the end of dst
	// to avoid extra heap allocations, then encrypt it in-place.
	offset := headerSize
	innerPlaintext := dst[offset : offset+innerLen]
	
	binary.BigEndian.PutUint16(innerPlaintext[0:2], uint16(len(plaintext)))
	copy(innerPlaintext[2:2+len(plaintext)], plaintext)
	
	// Write random bytes for padding
	if padLen > 0 {
		_, _ = io.ReadFull(rand.Reader, innerPlaintext[2+len(plaintext):])
	}

	// 4. Encrypt and Authenticate (AEAD)
	// Seal appends the ciphertext and MAC to dst[:offset]
	sealed := o.aead.Seal(dst[:offset], nonce, innerPlaintext, dst[:4]) // use STUN header as Associated Data
	
	return len(sealed), nil
}

// Deobfuscate decrypts a packet in-place.
// Returns a slice of the original buffer (actual points to a subslice of ciphertext).
func (o *Obfuscator) Deobfuscate(ciphertext []byte) ([]byte, error) {
	const headerSize = 4 + chacha20poly1305.NonceSizeX
	if len(ciphertext) < headerSize+o.aead.Overhead()+2 {
		return nil, ErrPacketTooShort
	}

	// 1. Verify Fake STUN Magic
	magic := binary.BigEndian.Uint32(ciphertext[0:4])
	if magic != STUNMagic {
		return nil, ErrInvalidMagic
	}

	nonce := ciphertext[4:headerSize]
	sealed := ciphertext[headerSize:]

	// 2. Decrypt and Authenticate
	// We use sealed[:0] to decrypt in-place exactly where the ciphertext is.
	plaintext, err := o.aead.Open(sealed[:0], nonce, sealed, ciphertext[:4])
	if err != nil {
		return nil, ErrAuthFailed
	}

	if len(plaintext) < 2 {
		return nil, ErrPacketTooShort
	}

	// 3. Extract Payload Length and remove padding
	payloadLen := int(binary.BigEndian.Uint16(plaintext[0:2]))
	if payloadLen > len(plaintext)-2 {
		return nil, ErrPacketTooShort
	}

	return plaintext[2 : 2+payloadLen], nil
}
