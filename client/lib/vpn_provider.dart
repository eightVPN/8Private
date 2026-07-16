import 'dart:async';
import 'package:flutter/material.dart';

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

  void connect() {
    if (_state != VPNState.disconnected) return;

    _state = VPNState.connecting;
    notifyListeners();

    // Simulate connection delay and potential UDP throttling fallback
    Timer(const Duration(milliseconds: 1500), () {
      _state = VPNState.connected;
      _sessionDuration = Duration.zero;
      _mode = ConnectionMode.udp;

      // Start metrics generator and timer
      _startSessionMetrics();
      notifyListeners();
    });
  }

  void disconnect() {
    if (_state != VPNState.connected) return;

    _state = VPNState.disconnected;
    _downloadSpeed = 0.0;
    _uploadSpeed = 0.0;

    _sessionTimer?.cancel();
    _sessionTimer = null;

    notifyListeners();
  }

  // Simulates server statistics updates
  void _startSessionMetrics() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sessionDuration += const Duration(seconds: 1);

      // Random speed fluctuations matching premium speeds
      final r = randDouble(0.8, 1.2);
      _downloadSpeed = 482.5 * r;
      _uploadSpeed = 124.8 * r;

      // Simulate a random UDP Block after 20 seconds, triggering TCP Fallback
      if (_sessionDuration.inSeconds == 15 && _mode == ConnectionMode.udp) {
        _triggerTCPFallback();
      }

      notifyListeners();
    });
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
