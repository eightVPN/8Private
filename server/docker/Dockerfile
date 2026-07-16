# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy dependency files first to cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the entire workspace (required to compile shared and server modules together)
COPY . .

# Compile statically linked Go server binary for Linux
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o vpn8-server ./server/cmd/main.go

# Execution stage
FROM alpine:latest

# Install iptables, ca-certificates, iproute2 for TUN/NAT support
RUN apk --no-cache add ca-certificates iptables iproute2

WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /app/vpn8-server .

# Expose UDP VPN Tunnel Port and TCP REST API Port
EXPOSE 51820/udp
EXPOSE 8080/tcp

# The container MUST be started with:
#   --cap-add NET_ADMIN --device /dev/net/tun:/dev/net/tun
# These are required for TUN device creation and iptables NAT rules.

# Run server
ENTRYPOINT ["./vpn8-server"]
