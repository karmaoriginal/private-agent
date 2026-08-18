import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client for the remote code-execution sandbox the agent can use to run
/// commands outside the phone.
///
/// Convention: POST {base}/execute with {"command": "...", "language": "bash"}
/// The service probes /health on demand and reports clearly when the
/// server doesn't implement the expected routes.
class SandboxService {
  static const String defaultUrl = 'http://vicky.hidencloud.com:24704';

  String _baseUrl = defaultUrl;
  String get baseUrl => _baseUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('sandbox_url') ?? defaultUrl;
  }

  Future<void> saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = url.trim().isEmpty ? defaultUrl : url.trim();
    await prefs.setString('sandbox_url', _baseUrl);
  }

  Uri _uri(String path) {
    var base = _baseUrl;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return Uri.parse('$base$path');
  }

  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      try {
        final data = jsonDecode(response.body);
        return data is Map && data['status'] == 'ok';
      } catch (_) {
        return true; // 200 with non-JSON body still counts as alive
      }
    } catch (_) {
      return false;
    }
  }

  /// Runs a command in the sandbox. Tries the common route names in order.
  Future<String> execute(String command, {String language = 'bash'}) async {
    Object? lastError;
    for (final path in ['/execute', '/run', '/exec']) {
      try {
        final response = await http
            .post(
              _uri(path),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'command': command, 'language': language}),
            )
            .timeout(const Duration(minutes: 2));
        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body);
            if (data is Map) {
              return (data['output'] ??
                      data['stdout'] ??
                      data['result'] ??
                      response.body)
                  .toString();
            }
          } catch (_) {}
          return response.body;
        }
        lastError = 'HTTP ${response.statusCode} on $path';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(
      'Sandbox did not accept the command ($lastError). The server at '
      '$_baseUrl is alive but none of /execute, /run or /exist responded — '
      'check which routes your sandbox server exposes.',
    );
  }
}
