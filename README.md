# 8Private (VPN 8)

8Private is a high-performance, DPI-evasive VPN solution featuring a Flutter-based client and a Golang backend. It is designed to provide maximum throughput while actively obfuscating traffic against Deep Packet Inspection (DPI) systems like TSPU.

## Architecture

The project is split into three main components:
- **`server/`**: The VPN Backend. Handles TUN interface routing, IP allocation, user management, and REST API administration.
- **`client/`**: The VPN Client. Built with Flutter for a cross-platform UI, and embeds a local Go daemon (`vpn8-core`) to handle the networking and TUN interface on the client device.
- **`shared/`**: The Core Networking Library. Contains the packet framing, cryptography, and TUN utilities shared between the client and server.

### Dual-Channel Networking
8Private utilizes a dual-channel architecture for optimal performance and security:
1. **Control Plane (QUIC)**: Used for secure, reliable client authentication and connection setup.
2. **Data Plane (Pure UDP + AEAD)**: Used for raw IP packet transit.

## DPI Evasion & Security
To bypass modern DPI systems (like TSPU) without sacrificing the speed of WireGuard or OpenVPN, the Data Plane implements several advanced obfuscation techniques:
- **Zero-Allocation Routing**: Parses IPv4 headers directly into `uint32` integers, allowing O(1) session lookups without triggering Garbage Collection (GC) pauses at high throughputs.
- **XChaCha20-Poly1305 AEAD**: Provides Authenticated Encryption with Associated Data. Uses a 192-bit (24-byte) random nonce to prevent replay attacks and cryptographic reuse. Packets that fail authentication are silently dropped (resilient against active probing).
- **Protocol Camouflage**: Prepends a Fake STUN Magic Header (`0x2112A442`) to disguise the traffic as standard WebRTC voice/video data.
- **Randomized Padding**: Injects random padding at the end of each packet to obscure the true MTU and packet length, thwarting machine-learning traffic analysis.

## Build Instructions

### Prerequisites
- Go 1.21+
- Flutter SDK (for client UI)
- `make` or standard shell tools

### Server
```bash
cd server/cmd
go build -o vpn8-server .
./vpn8-server
```

### Client (Local Daemon)
```bash
cd client/cmd
go build -o vpn8-core .
```

### Client (Flutter App)
```bash
cd client
flutter pub get
flutter run -d macos
```
