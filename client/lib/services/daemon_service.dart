import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class DaemonService {
  static const String _apiBaseUrl = 'http://127.0.0.1:51821';
  static bool _daemonStarted = false;

  /// Starts the VPN core daemon with elevated privileges if not already running.
  static Future<void> ensureDaemonRunning() async {
    if (_daemonStarted) return;
    
    // Check if it's already responding
    try {
      final res = await http.get(Uri.parse('$_apiBaseUrl/status')).timeout(const Duration(seconds: 1));
      if (res.statusCode == 200) {
        _daemonStarted = true;
        return;
      }
    } catch (_) {
      // Not running, proceed to start
    }

    // During local macOS development, the Flutter app runs in a Sandbox container, 
    // so Directory.current is not the project root. 
    // We hardcode the absolute path to the project directory for development purposes.
    final executablePath = '/Users/user/develop/8Private/client/vpn8-core';
    
    if (!File(executablePath).existsSync()) {
      throw Exception('Daemon binary not found at $executablePath. Did you run build_daemon.sh?');
    }

    if (Platform.isMacOS) {
      final currentPid = pid;
      final script = 'do shell script "$executablePath -pid $currentPid > /dev/null 2>&1 &" with administrator privileges';
      
      final result = await Process.run('osascript', ['-e', script]);
      
      if (result.exitCode != 0) {
        throw Exception('Failed to start daemon (auth rejected?): ${result.stderr}');
      }
    } else {
      // Future Linux/Windows support
      throw UnsupportedError('Daemon start not implemented for this platform yet.');
    }
    
    // Wait for the daemon to start listening
    bool isListening = false;
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final res = await http.get(Uri.parse('$_apiBaseUrl/status')).timeout(const Duration(seconds: 1));
        if (res.statusCode == 200) {
          isListening = true;
          break;
        }
      } catch (_) {}
    }
    
    if (!isListening) {
      throw Exception('Daemon process started but API is not reachable.');
    }
    
    _daemonStarted = true;
  }

  /// Connects the VPN by sending credentials to the daemon
  static Future<bool> connect(String serverAddr, String accessKey, String hwid, String pskHex) async {
    await ensureDaemonRunning();
    
    final res = await http.post(
      Uri.parse('$_apiBaseUrl/connect'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'serverAddr': serverAddr,
        'accessKey': accessKey,
        'hwid': hwid,
        'pskHex': pskHex,
      }),
    );
    
    if (res.statusCode == 200) {
      return true;
    } else {
      print('Daemon connect failed: ${res.statusCode} - ${res.body}');
      return false;
    }
  }

  /// Disconnects the VPN
  static Future<void> disconnect() async {
    try {
      await http.post(Uri.parse('$_apiBaseUrl/disconnect'));
    } catch (e) {
      print('Failed to send disconnect to daemon: $e');
    }
  }

  /// Fetches the status of the VPN daemon
  static Future<Map<String, dynamic>> getStatus() async {
    try {
      final res = await http.get(Uri.parse('$_apiBaseUrl/status')).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return {'running': false, 'activeMode': 'None'};
  }
}
