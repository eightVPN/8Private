import 'dart:async';
import 'package:flutter/material.dart';
import 'services/daemon_service.dart';

enum VPNState { disconnected, connecting, connected }

enum ConnectionMode { udp, tcp }

class ServerProfile {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String accessKey;
  final int latencyMs;

  ServerProfile({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.accessKey,
    required this.latencyMs,
  });
}

class VPNUser {
  final String id;
  final String username;
  final String accessKey;
  final String role; // "owner", "admin", "user"
  final int deviceLimit;
  final int activeDevices;

  VPNUser({
    required this.id,
    required this.username,
    required this.accessKey,
    required this.role,
    required this.deviceLimit,
    required this.activeDevices,
  });
}

class VPNProvider extends ChangeNotifier {
  VPNState _state = VPNState.disconnected;
  ConnectionMode _mode = ConnectionMode.udp;

  double _downloadSpeed = 0.0;
  double _uploadSpeed = 0.0;
  int _latency = 12;

  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;

  ServerProfile? _selectedServer;
  final List<ServerProfile> _servers = [];

  // Administration State
  final List<VPNUser> _users = [];

  // Split Tunneling Configuration
  final List<String> _tunneledApps = [
    'com.android.chrome',
    'org.mozilla.firefox',
    'com.instagram.android',
  ];
  final List<String> _bypassedApps = [
    'ru.sberbankmobile',
    'ru.tinkoff.activities',
    'ru.gosuslugi.app',
  ];

  final List<String> _tunneledDomains = [
    'google.com',
    'youtube.com',
    'facebook.com',
    'instagram.com',
  ];
  final List<String> _bypassedDomains = [
    'gosuslugi.ru',
    'sberbank.ru',
    'tbank.ru',
    'nalog.gov.ru',
  ];

  VPNProvider() {
    if (_servers.isNotEmpty) {
      _selectedServer = _servers.first;
    }
  }

  // Getters
  VPNState get state => _state;
  ConnectionMode get mode => _mode;
  double get downloadSpeed => _downloadSpeed;
  double get uploadSpeed => _uploadSpeed;
  int get latency => _latency;
  Duration get sessionDuration => _sessionDuration;
  ServerProfile? get selectedServer => _selectedServer;
  List<ServerProfile> get servers => _servers;
  List<VPNUser> get users => _users;

  List<String> get tunneledApps => _tunneledApps;
  List<String> get bypassedApps => _bypassedApps;
  List<String> get tunneledDomains => _tunneledDomains;
  List<String> get bypassedDomains => _bypassedDomains;

  String get sessionDurationString {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(_sessionDuration.inHours);
    final minutes = twoDigits(_sessionDuration.inMinutes.remainder(60));
    final seconds = twoDigits(_sessionDuration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  // Server administration actions
  void createUser(String username, String role, int deviceLimit) {
    final newId = (_users.length + 1).toString();
    final newKey = 'epn_${role}_${username.toLowerCase().replaceAll(' ', '_')}';
    _users.add(
      VPNUser(
        id: newId,
        username: username,
        accessKey: newKey,
        role: role,
        deviceLimit: role == 'admin' ? 1 : deviceLimit,
        activeDevices: 0,
      ),
    );
    notifyListeners();
  }

  void deleteUser(String id) {
    _users.removeWhere((u) => u.id == id);
    notifyListeners();
  }

  void resetUserDevices(String id) {
    final idx = _users.indexWhere((u) => u.id == id);
    if (idx != -1) {
      final oldUser = _users[idx];
      _users[idx] = VPNUser(
        id: oldUser.id,
        username: oldUser.username,
        accessKey: oldUser.accessKey,
        role: oldUser.role,
        deviceLimit: oldUser.deviceLimit,
        activeDevices: 0,
      );
      notifyListeners();
    }
  }

  // Split tunneling configurations
  void addBypassedApp(String packageName) {
    if (!_bypassedApps.contains(packageName)) {
      _bypassedApps.add(packageName);
      notifyListeners();
    }
  }

  void removeBypassedApp(String packageName) {
    _bypassedApps.remove(packageName);
    notifyListeners();
  }

  void addBypassedDomain(String domain) {
    if (!_bypassedDomains.contains(domain)) {
      _bypassedDomains.add(domain);
      notifyListeners();
    }
  }

  void removeBypassedDomain(String domain) {
    _bypassedDomains.remove(domain);
    notifyListeners();
  }

  // Add a new server
  void addServer(ServerProfile server) {
    _servers.add(server);
    if (_selectedServer == null) {
      _selectedServer = server;
    }
    notifyListeners();
  }

  // Remove a server
  void removeServer(String id) {
    _servers.removeWhere((s) => s.id == id);
    if (_selectedServer?.id == id) {
      _selectedServer = _servers.isNotEmpty ? _servers.first : null;
    }
    notifyListeners();
  }

  // Select server
  void selectServer(ServerProfile server) {
    _selectedServer = server;
    _latency = server.latencyMs;
    if (_state == VPNState.connected) {
      disconnect();
      connect();
    } else {
      notifyListeners();
    }
  }

  // VPN connection control
  void toggleConnection() {
    if (_state == VPNState.connected) {
      disconnect();
    } else if (_state == VPNState.disconnected) {
      connect();
    }
  }

  Future<void> connect() async {
    if (_state != VPNState.disconnected || _selectedServer == null) return;

    _state = VPNState.connecting;
    notifyListeners();

    try {
      final success = await DaemonService.connect(
        '${_selectedServer!.ip}:51820',
        'epn_owner_key_default', // In production, read from activeServer credentials
        'macos_client', // In production, generate unique HWID
        '43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38'
      );
      
      if (success) {
        _state = VPNState.connected;
        _sessionDuration = Duration.zero;
        _mode = ConnectionMode.udp;
        _startSessionMetrics();
      } else {
        _state = VPNState.disconnected;
      }
    } catch (e) {
      print('VPN Connection Error: $e');
      _state = VPNState.disconnected;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_state != VPNState.connected) return;

    try {
      await DaemonService.disconnect();
    } catch (e) {
      print('VPN Disconnect Error: $e');
    }

    _state = VPNState.disconnected;
    _stopSessionMetrics();
    notifyListeners();
  }

  // Simulates server statistics updates and real daemon polling
  void _startSessionMetrics() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _sessionDuration += const Duration(seconds: 1);

      // Poll real status from Daemon
      final status = await DaemonService.getStatus();
      if (status['running'] == true) {
         if (status['activeMode'] == 'TCP') {
             _mode = ConnectionMode.tcp;
         } else if (status['activeMode'] == 'UDP') {
             _mode = ConnectionMode.udp;
         }
      } else {
          // Daemon died or disconnected externally
          disconnect();
          return;
      }

      // Random speed fluctuations matching premium speeds
      final r = randDouble(0.8, 1.2);
      _downloadSpeed = 482.5 * r;
      _uploadSpeed = 124.8 * r;

      notifyListeners();
    });
  }

  void _stopSessionMetrics() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _downloadSpeed = 0.0;
    _uploadSpeed = 0.0;
  }

  void _triggerTCPFallback() {
    _mode = ConnectionMode.tcp;
    // Speed drops slightly in TCP fallback due to TCP window/head-of-line blocking
    _downloadSpeed = 112.4;
    _uploadSpeed = 45.2;
    _latency = 36;
    notifyListeners();
  }

  double randDouble(double min, double max) {
    return min + (max - min) * (DateTime.now().millisecond / 1000.0);
  }
}
