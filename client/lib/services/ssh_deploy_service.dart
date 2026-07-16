import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

class SSHDeployConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final bool enableAutoUpdate;

  SSHDeployConfig({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.enableAutoUpdate = false,
  });
}

class SSHDeployService {
  static const String _bootstrapScript = '''
#!/bin/bash
set -e

echo "[1/6] Preparing environment..."
export DEBIAN_FRONTEND=noninteractive
if [ -x "\$(command -v apt-get)" ]; then
    apt-get update -y
elif [ -x "\$(command -v yum)" ]; then
    yum update -y
fi

echo "[2/6] Checking Docker Engine..."
if ! [ -x "\$(command -v docker)" ]; then
    echo "      Installing Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "      Docker is already installed."
fi

echo "[3/6] Setting up Virtual TUN Adapter..."
if [ ! -c /dev/net/tun ]; then
    echo "      Provisioning /dev/net/tun node..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

echo "      Enabling Kernel IPv4 Forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo "[4/6] Detecting Outbound Interface..."
OUT_IFACE=\$(ip route show default | awk '/default/ {print \$5}' | head -1)
if [ -z "\$OUT_IFACE" ]; then OUT_IFACE="eth0"; fi
echo "      Interface: \$OUT_IFACE"

echo "[5/6] Creating Deployment Configuration..."
if ! [ -x "\$(command -v git)" ]; then
    if [ -x "\$(command -v apt-get)" ]; then apt-get install git -y;
    elif [ -x "\$(command -v yum)" ]; then yum install git -y; fi
fi

mkdir -p /opt/vpn8/data
cd /opt/vpn8
if [ ! -d "8Private" ]; then
    git clone https://github.com/eightVPN/8Private.git
else
    cd 8Private && git pull && cd ..
fi

cat <<EOF > /opt/vpn8/docker-compose.yml
version: '3.8'
services:
  vpn8-server:
    build:
      context: ./8Private
      dockerfile: server/docker/Dockerfile
    image: vpn8-server:local
    container_name: vpn8-server
    restart: always
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    network_mode: host
    environment:
      - VPN_ADDR=:51820
      - API_ADDR=:8080
      - API_KEY=epn_owner_key_default
      - VPN_PSK=43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38
      - VPN_SUBNET=10.8.0.0/16
      - TUN_NAME=vpn8-tun0
      - ENABLE_NAT=true
      - OUT_IFACE=\$OUT_IFACE
      - MAX_CLIENTS=0
      - DB_PATH=/app/data/vpn8.db
    volumes:
      - ./data:/app/data
    sysctls:
      - net.ipv4.ip_forward=1
EOF

echo "[6/6] Launching VPN 8 Server..."
cd /opt/vpn8
docker compose up -d --build

if [ -x "\$(command -v ufw)" ]; then
    echo "      Configuring UFW Firewall..."
    ufw allow 22/tcp || true
    ufw allow 51820/udp || true
    ufw allow 8080/tcp || true
fi

echo "========================================="
echo "   VPN 8 Installation Completed!         "
echo "========================================="
''';

  /// Connects to the server, executes the deployment script, and yields output lines.
  Stream<String> deployServer(SSHDeployConfig config) async* {
    SSHClient? client;
    try {
      yield '> Initializing SSH connection to ${config.host}...';

      client = SSHClient(
        await SSHSocket.connect(
          config.host,
          config.port,
          timeout: const Duration(seconds: 10),
        ),
        username: config.username,
        onPasswordRequest: config.password != null
            ? () => config.password!
            : null,
        identities: config.privateKey != null
            ? SSHKeyPair.fromPem(config.privateKey!)
            : null,
      );

      yield '> Authentication successful. Opening shell...';

      final session = await client.execute('bash -s');

      // Write the script to stdin
      session.stdin.add(utf8.encode(_bootstrapScript));
      session.stdin.close();

      // Read output
      final Stream<String> stdoutStream = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final Stream<String> stderrStream = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => 'ERR: $line');

      await for (final line in StreamGroup.merge([
        stdoutStream,
        stderrStream,
      ])) {
        yield line;
      }

      await session.done;
      if (session.exitCode == 0) {
        yield '> Server deployment completed successfully.';
      } else {
        yield '> Deployment failed with exit code ${session.exitCode}.';
        throw Exception('Deployment failed with exit code ${session.exitCode}');
      }
    } catch (e) {
      yield '> ERROR: $e';
      rethrow;
    } finally {
      client?.close();
    }
  }
}

// Simple stream merger utility since we don't have async package in dependencies
class StreamGroup {
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) {
    StreamController<T>? controller;
    int activeStreams = 0;

    void onData(T data) {
      controller?.add(data);
    }

    void onError(Object error, StackTrace stackTrace) {
      controller?.addError(error, stackTrace);
    }

    void onDone() {
      activeStreams--;
      if (activeStreams == 0) {
        controller?.close();
      }
    }

    controller = StreamController<T>(
      onListen: () {
        for (final stream in streams) {
          activeStreams++;
          stream.listen(onData, onError: onError, onDone: onDone);
        }
      },
    );

    return controller.stream;
  }
}
