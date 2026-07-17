import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:uuid/uuid.dart';
import 'services/daemon_service.dart';
import 'services/server_api_service.dart';

enum VPNState { disconnected, connecting, connected }

enum ConnectionMode { udp, tcp }

class ServerProfile {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String accessKey;
  final int latencyMs;
  String apiKey;

  ServerProfile({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.accessKey,
    required this.latencyMs,
    this.apiKey = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'accessKey': accessKey,
        'latencyMs': latencyMs,
        'apiKey': apiKey,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        ip: json['ip'] as String,
        port: json['port'] as int,
        accessKey: json['accessKey'] as String,
        latencyMs: json['latencyMs'] as int,
        apiKey: json['apiKey'] as String? ?? '',
      );
}

class VPNUser {
  final String id;
  final String username;
  final String accessKey;
  final String role; // "owner", "admin", "user"
  final int deviceLimit;
  final int rateLimit;
  final int activeDevices;

  VPNUser({
    required this.id,
    required this.username,
    required this.accessKey,
    required this.role,
    required this.deviceLimit,
    required this.rateLimit,
    required this.activeDevices,
  });
}

class VPNProvider extends ChangeNotifier {
  VPNState _state = VPNState.disconnected;
  ConnectionMode _mode = ConnectionMode.udp;

  double _downloadSpeed = 0.0;
  double _uploadSpeed = 0.0;
  int _latency = 12;

  int _lastRxBytes = 0;
  int _lastTxBytes = 0;

  final List<FlSpot> _downloadHistory = [];
  final List<FlSpot> _uploadHistory = [];
  double _historyTime = 0.0;

  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;

  ServerProfile? _selectedServer;
  List<ServerProfile> _servers = [];

  String _hwid = '';
  String _pskHex = '43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38';

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
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    _hwid = prefs.getString('hwid') ?? const Uuid().v4();
    _pskHex = prefs.getString('pskHex') ?? '43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38';
    
    // Ensure we save generated defaults
    await prefs.setString('hwid', _hwid);
    await prefs.setString('pskHex', _pskHex);

    final serversJson = prefs.getStringList('servers');
    if (serversJson != null) {
      _servers = serversJson
          .map((e) => ServerProfile.fromJson(jsonDecode(e)))
          .toList();
    }
    
    final selectedId = prefs.getString('selectedServerId');
    if (selectedId != null && _servers.isNotEmpty) {
      _selectedServer = _servers.cast<ServerProfile?>().firstWhere(
            (s) => s?.id == selectedId,
            orElse: () => _servers.first,
          );
    } else if (_servers.isNotEmpty) {
      _selectedServer = _servers.first;
    }
    
    // Initialize graph history
    for (int i = 0; i < 60; i++) {
      _downloadHistory.add(FlSpot(i.toDouble(), 0));
      _uploadHistory.add(FlSpot(i.toDouble(), 0));
    }
    _historyTime = 59.0;
    
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = _servers.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('servers', serversJson);
    if (_selectedServer != null) {
      await prefs.setString('selectedServerId', _selectedServer!.id);
    }
  }

  // Getters
  VPNState get state => _state;
  ConnectionMode get mode => _mode;
  double get downloadSpeed => _downloadSpeed;
  double get uploadSpeed => _uploadSpeed;
  List<FlSpot> get downloadHistory => _downloadHistory;
  List<FlSpot> get uploadHistory => _uploadHistory;
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
  Future<void> fetchUsers() async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return;
    try {
      final data = await ServerApiService.getUsers(_selectedServer!.ip, _selectedServer!.apiKey);
      _users.clear();
      for (var u in data) {
        _users.add(VPNUser(
          id: u['id'].toString(),
          username: u['username'] ?? '',
          accessKey: u['access_key'] ?? '',
          role: u['role'] ?? 'user',
          deviceLimit: u['device_limit'] ?? 1,
          rateLimit: u['rate_limit'] ?? 0,
          activeDevices: u['active_devices'] ?? 0,
        ));
      }
      notifyListeners();
    } catch (e) {
      print('Failed to fetch users: $e');
    }
  }

  Future<void> createUser(String username, String role, int deviceLimit, int rateLimit) async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return;
    try {
      await ServerApiService.createUser(_selectedServer!.ip, _selectedServer!.apiKey, username, role, deviceLimit, rateLimit);
      await fetchUsers();
    } catch (e) {
      print('Failed to create user: $e');
    }
  }

  Future<void> deleteUser(String id) async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return;
    try {
      await ServerApiService.deleteUser(_selectedServer!.ip, _selectedServer!.apiKey, int.parse(id));
      await fetchUsers();
    } catch (e) {
      print('Failed to delete user: $e');
    }
  }

  Future<Map<String, dynamic>?> reissueAccessKey(String id) async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return null;
    try {
      final res = await ServerApiService.reissueAccessKey(_selectedServer!.ip, _selectedServer!.apiKey, int.parse(id));
      await fetchUsers();
      return res;
    } catch (e) {
      print('Failed to reissue access key: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> reissueApiKey(String id) async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return null;
    try {
      final res = await ServerApiService.reissueApiKey(_selectedServer!.ip, _selectedServer!.apiKey, int.parse(id));
      await fetchUsers();
      return res;
    } catch (e) {
      print('Failed to reissue api key: $e');
      return null;
    }
  }

  Future<void> resetUserDevices(String id) async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return;
    try {
      await ServerApiService.resetDevices(_selectedServer!.ip, _selectedServer!.apiKey, int.parse(id));
      await fetchUsers();
    } catch (e) {
      print('Failed to reset devices: $e');
    }
  }

  Future<void> rebootServer() async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return;
    try {
      await ServerApiService.serverReboot(_selectedServer!.ip, _selectedServer!.apiKey);
    } catch (e) {
      print('Failed to reboot server: $e');
    }
  }

  Future<void> wipeServer() async {
    if (_selectedServer == null || _selectedServer!.apiKey.isEmpty) return;
    try {
      await ServerApiService.serverWipe(_selectedServer!.ip, _selectedServer!.apiKey);
    } catch (e) {
      print('Failed to wipe server: $e');
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
    _saveToPrefs();
    notifyListeners();
  }

  // Remove a server
  void removeServer(String id) {
    _servers.removeWhere((s) => s.id == id);
    if (_selectedServer?.id == id) {
      _selectedServer = _servers.isNotEmpty ? _servers.first : null;
    }
    _saveToPrefs();
    notifyListeners();
  }

  // Select server
  void selectServer(ServerProfile server) {
    _selectedServer = server;
    _latency = server.latencyMs;
    _saveToPrefs();
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
        '${_selectedServer!.ip}:${_selectedServer!.port}',
        _selectedServer!.accessKey,
        _hwid,
        _pskHex
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

      final currentApiKey = status['apiKey'] as String?;
      if (currentApiKey != null && currentApiKey.isNotEmpty && _selectedServer != null && _selectedServer!.apiKey != currentApiKey) {
        _selectedServer!.apiKey = currentApiKey;
        _saveToPrefs();
        fetchUsers();
      }

      // Read real traffic bytes
      final rxBytes = (status['rxBytes'] as int?) ?? 0;
      final txBytes = (status['txBytes'] as int?) ?? 0;

      // Calculate speed (bytes per second -> megabits per second)
      final rxDelta = rxBytes - _lastRxBytes;
      final txDelta = txBytes - _lastTxBytes;
      
      _lastRxBytes = rxBytes;
      _lastTxBytes = txBytes;

      // Only calculate if not first tick
      if (_sessionDuration.inSeconds > 1) {
          _downloadSpeed = (rxDelta * 8) / 1000000;
          _uploadSpeed = (txDelta * 8) / 1000000;
      }

      _historyTime += 1;
      _downloadHistory.add(FlSpot(_historyTime, _downloadSpeed));
      if (_downloadHistory.length > 60) _downloadHistory.removeAt(0);

      _uploadHistory.add(FlSpot(_historyTime, _uploadSpeed));
      if (_uploadHistory.length > 60) _uploadHistory.removeAt(0);

      notifyListeners();
    });
  }

  void _stopSessionMetrics() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _downloadSpeed = 0.0;
    _uploadSpeed = 0.0;
    _lastRxBytes = 0;
    _lastTxBytes = 0;
    for (int i = 0; i < 60; i++) {
        _downloadHistory[i] = FlSpot(_downloadHistory[i].x, 0);
        _uploadHistory[i] = FlSpot(_uploadHistory[i].x, 0);
    }
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
