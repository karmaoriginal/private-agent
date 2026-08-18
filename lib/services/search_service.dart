import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'camofox_service.dart';

/// Unified web search. Supported providers:
/// - 'camofox'     -> self-hosted CamoFox Browser Server search macros
/// - 'duckduckgo'  -> DuckDuckGo instant answers (free, no key)
/// - 'tavily'      -> Tavily search API (needs key)
/// - 'brave'       -> Brave Search API (needs key)
class SearchService {
  String provider = 'duckduckgo';
  String tavilyKey = '';
  String braveKey = '';

  final CamofoxService camofox = CamofoxService();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    provider = prefs.getString('search_provider') ?? 'duckduckgo';
    tavilyKey = prefs.getString('search_tavily_key') ?? '';
    braveKey = prefs.getString('search_brave_key') ?? '';
    await camofox.init();
  }

  Future<void> saveSettings({
    required String provider,
    String? tavilyKey,
    String? braveKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    this.provider = provider;
    await prefs.setString('search_provider', provider);
    if (tavilyKey != null) {
      this.tavilyKey = tavilyKey.trim();
      await prefs.setString('search_tavily_key', this.tavilyKey);
    }
    if (braveKey != null) {
      this.braveKey = braveKey.trim();
      await prefs.setString('search_brave_key', this.braveKey);
    }
  }

  /// Searches the web and returns a compact, model-friendly text result.
  Future<String> search(String query) async {
    switch (provider) {
      case 'camofox':
        return await camofox.search(query);
      case 'tavily':
        return await _tavily(query);
      case 'brave':
        return await _brave(query);
      case 'duckduckgo':
      default:
        return await _duckDuckGo(query);
    }
  }

  Future<String> _duckDuckGo(String query) async {
    final uri = Uri.https('api.duckduckgo.com', '/', {
      'q': query,
      'format': 'json',
      'no_html': '1',
      'skip_disambig': '1',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('DuckDuckGo error (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    final buffer = StringBuffer();
    final abstract = (data['AbstractText'] as String?) ?? '';
    if (abstract.isNotEmpty) {
      buffer.writeln(abstract);
      final source = data['AbstractURL'] as String?;
      if (source != null && source.isNotEmpty) buffer.writeln('Source: $source');
    }
    final topics = data['RelatedTopics'] as List? ?? const [];
    var count = 0;
    for (final t in topics) {
      if (count >= 5) break;
      if (t is Map && t['Text'] is String) {
        buffer.writeln('- ${t['Text']} (${t['FirstURL'] ?? ''})');
        count++;
      }
    }
    final result = buffer.toString().trim();
    if (result.isEmpty) {
      return 'No instant answer found for "$query". Try browse_page with a '
          'specific URL or switch the search provider in Settings.';
    }
    return result;
  }

  Future<String> _tavily(String query) async {
    if (tavilyKey.isEmpty) {
      throw Exception('Tavily API key not configured (Settings > Search).');
    }
    final response = await http
        .post(
          Uri.parse('https://api.tavily.com/search'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'api_key': tavilyKey,
            'query': query,
            'max_results': 5,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Tavily error (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body);
    final buffer = StringBuffer();
    final answer = data['answer'] as String?;
    if (answer != null && answer.isNotEmpty) buffer.writeln(answer);
    for (final r in (data['results'] as List? ?? const [])) {
      if (r is Map) {
        buffer.writeln('- ${r['title']}: ${r['content']} (${r['url']})');
      }
    }
    return buffer.toString().trim();
  }

  Future<String> _brave(String query) async {
    if (braveKey.isEmpty) {
      throw Exception('Brave API key not configured (Settings > Search).');
    }
    final uri = Uri.https('api.search.brave.com', '/res/v1/web/search', {
      'q': query,
      'count': '5',
    });
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
      'X-Subscription-Token': braveKey,
    }).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Brave error (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body);
    final buffer = StringBuffer();
    final results = data['web']?['results'] as List? ?? const [];
    for (final r in results) {
      if (r is Map) {
        buffer.writeln('- ${r['title']}: ${r['description'] ?? ''} (${r['url']})');
      }
    }
    return buffer.toString().trim();
  }
}
