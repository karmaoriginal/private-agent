import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client for a CamoFox Browser Server (camofox-browser): an
/// anti-detection Firefox automation server with a REST API, search
/// macros (@google_search, @youtube_search, ...) and token-efficient
/// accessibility snapshots.
///
/// Default port for a self-hosted server is 9377.
class CamofoxService {
  static const String defaultUrl = 'http://localhost:9377';

  String _baseUrl = defaultUrl;
  String _apiKey = '';

  String get baseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('camofox_url') ?? defaultUrl;
    _apiKey = prefs.getString('camofox_key') ?? '';
  }

  Future<void> saveSettings(String url, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = url.trim().isEmpty ? defaultUrl : url.trim();
    _apiKey = apiKey.trim();
    await prefs.setString('camofox_url', _baseUrl);
    await prefs.setString('camofox_key', _apiKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
      };

  Uri _uri(String path) {
    var base = _baseUrl;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return Uri.parse('$base$path');
  }

  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(_uri('/health'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data is Map &&
          (data['status'] == 'ok' || data['status'] == 'healthy');
    } catch (_) {
      return false;
    }
  }

  /// Creates a tab and returns its id.
  Future<String> _createTab(String urlOrMacro) async {
    final response = await http
        .post(
          _uri('/tabs'),
          headers: _headers,
          body: jsonEncode({'url': urlOrMacro, 'userId': 'privateagent'}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'CamoFox error (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body);
    final id = data['tabId'] ?? data['id'] ?? data['tab']?['id'];
    if (id == null) {
      throw Exception('CamoFox did not return a tab id: ${response.body}');
    }
    return id.toString();
  }

  Future<String> _snapshot(String tabId) async {
    // Give the page a moment to settle, then grab the accessibility tree.
    await Future<void>.delayed(const Duration(seconds: 2));
    final response = await http
        .get(_uri('/tabs/$tabId/snapshot'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(
        'CamoFox snapshot error (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body);
    return (data['snapshot'] ?? data['content'] ?? response.body).toString();
  }

  Future<void> _closeTab(String tabId) async {
    try {
      await http
          .delete(_uri('/tabs/$tabId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Runs a search macro (default Google) and returns a trimmed snapshot.
  Future<String> search(String query, {String engine = 'google'}) async {
    final tabId = await _createTab('@${engine}_search $query');
    try {
      final snapshot = await _snapshot(tabId);
      return _trim(snapshot);
    } finally {
      await _closeTab(tabId);
    }
  }

  /// Opens a page and returns its accessibility snapshot.
  Future<String> openPage(String url) async {
    final tabId = await _createTab(url);
    try {
      final snapshot = await _snapshot(tabId);
      return _trim(snapshot);
    } finally {
      await _closeTab(tabId);
    }
  }

  String _trim(String content, {int maxChars = 8000}) {
    if (content.length <= maxChars) return content;
    return '${content.substring(0, maxChars)}\n...[truncated]';
  }
}
