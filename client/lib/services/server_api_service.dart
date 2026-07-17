import 'dart:convert';
import 'package:http/http.dart' as http;

class ServerApiService {
  static Map<String, String> _headers(String apiKey) {
    return {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    };
  }

  static String _baseUrl(String ip) {
    return 'https://$ip:8443/api';
  }

  static Future<List<dynamic>> getUsers(String ip, String apiKey) async {
    final res = await http.get(
      Uri.parse('${_baseUrl(ip)}/users'),
      headers: _headers(apiKey),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as List<dynamic>;
    } else {
      throw Exception('Failed to get users: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> createUser(
      String ip, String apiKey, String username, String role, int deviceLimit, int rateLimit) async {
    final res = await http.post(
      Uri.parse('${_baseUrl(ip)}/users'),
      headers: _headers(apiKey),
      body: jsonEncode({
        'username': username,
        'role': role,
        'deviceLimit': deviceLimit,
        'rateLimit': rateLimit,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to create user: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> deleteUser(String ip, String apiKey, int id) async {
    final res = await http.delete(
      Uri.parse('${_baseUrl(ip)}/users/$id'),
      headers: _headers(apiKey),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to delete user: ${res.statusCode} ${res.body}');
    }
  }

  static Future<Map<String, dynamic>> reissueAccessKey(String ip, String apiKey, int id) async {
    final res = await http.post(
      Uri.parse('${_baseUrl(ip)}/users/$id/reissue-access-key'),
      headers: _headers(apiKey),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to reissue access key: ${res.statusCode} ${res.body}');
    }
  }

  static Future<Map<String, dynamic>> reissueApiKey(String ip, String apiKey, int id) async {
    final res = await http.post(
      Uri.parse('${_baseUrl(ip)}/users/$id/reissue-api-key'),
      headers: _headers(apiKey),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to reissue api key: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> resetDevices(String ip, String apiKey, int id) async {
    final res = await http.post(
      Uri.parse('${_baseUrl(ip)}/users/$id/reset'),
      headers: _headers(apiKey),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to reset devices: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> serverReboot(String ip, String apiKey) async {
    final res = await http.post(
      Uri.parse('${_baseUrl(ip)}/server/reboot'),
      headers: _headers(apiKey),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to reboot server: ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> serverWipe(String ip, String apiKey) async {
    final res = await http.post(
      Uri.parse('${_baseUrl(ip)}/server/wipe'),
      headers: _headers(apiKey),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to wipe server: ${res.statusCode} ${res.body}');
    }
  }
}
