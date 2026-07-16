#!/bin/bash

# Exit on any error
set -e

echo "Building Local Daemon VPN Bridge (vpn8-core)..."

# Ensure we are in the correct directory (8Private root)
cd "$(dirname "$0")"

# Build the Go core as an executable
cd client
go build -o vpn8-core ./cmd

echo "Build successful! vpn8-core is ready at client/vpn8-core"
