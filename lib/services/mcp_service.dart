import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A configured MCP (Model Context Protocol) server reachable over
/// Streamable HTTP.
class McpServer {
  final String name;
  final String url;
  final String apiKey;

  const McpServer({required this.name, required this.url, this.apiKey = ''});

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'apiKey': apiKey};

  factory McpServer.fromJson(Map<String, dynamic> json) => McpServer(
        name: json['name'] as String? ?? 'server',
        url: json['url'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
      );
}

class McpTool {
  final McpServer server;
  final String name;
  final String description;

  const McpTool({
    required this.server,
    required this.name,
    required this.description,
  });
}

/// Minimal MCP client (JSON-RPC 2.0 over Streamable HTTP). Lets the agent
/// discover and call tools exposed by external MCP plugin servers.
class McpService {
  final List<McpServer> servers = [];
  int _requestId = 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    servers.clear();
    final raw = prefs.getString('mcp_servers') ?? '[]';
    try {
      final list = jsonDecode(raw) as List;
      servers.addAll(
        list.whereType<Map<String, dynamic>>().map(McpServer.fromJson),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'mcp_servers',
      jsonEncode(servers.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> addServer(McpServer server) async {
    servers.removeWhere((s) => s.name == server.name);
    servers.add(server);
    await _save();
  }

  Future<void> removeServer(String name) async {
    servers.removeWhere((s) => s.name == name);
    await _save();
  }

  /// Sends a JSON-RPC request, handling both plain JSON and SSE responses.
  Future<Map<String, dynamic>> _rpc(
    McpServer server,
    String method,
    Map<String, dynamic> params, {
    String? sessionId,
  }) async {
    final response = await http
        .post(
          Uri.parse(server.url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            if (server.apiKey.isNotEmpty)
              'Authorization': 'Bearer ${server.apiKey}',
            if (sessionId != null) 'Mcp-Session-Id': sessionId,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': ++_requestId,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
        'MCP server "${server.name}" error (${response.statusCode})',
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    String payload = response.body;
    if (contentType.contains('text/event-stream')) {
      // Extract the last data: line of the SSE stream.
      final dataLines = payload
          .split('\n')
          .where((l) => l.startsWith('data:'))
          .map((l) => l.substring(5).trim())
          .toList();
      if (dataLines.isEmpty) throw Exception('MCP: empty SSE response');
      payload = dataLines.last;
    }

    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('MCP: unexpected response');
    }
    if (decoded['error'] != null) {
      throw Exception('MCP error: ${decoded['error']['message']}');
    }
    final result = decoded['result'];
    final map = result is Map<String, dynamic> ? result : <String, dynamic>{};
    // Bubble the session id up for follow-up calls.
    final sid = response.headers['mcp-session-id'];
    if (sid != null) map['__sessionId'] = sid;
    return map;
  }

  Future<String?> _initialize(McpServer server) async {
    final result = await _rpc(server, 'initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'PrivateAgent', 'version': '1.0.0'},
    });
    final sessionId = result['__sessionId'] as String?;
    // Required notification after initialize.
    try {
      await http.post(
        Uri.parse(server.url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          if (server.apiKey.isNotEmpty)
            'Authorization': 'Bearer ${server.apiKey}',
          if (sessionId != null) 'Mcp-Session-Id': sessionId,
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }),
      );
    } catch (_) {}
    return sessionId;
  }

  /// Lists the tools a server exposes (for discovery / settings display).
  Future<List<McpTool>> listTools(McpServer server) async {
    final sessionId = await _initialize(server);
    final result = await _rpc(server, 'tools/list', {}, sessionId: sessionId);
    final tools = result['tools'] as List? ?? const [];
    return tools.whereType<Map<String, dynamic>>().map((t) {
      return McpTool(
        server: server,
        name: t['name'] as String? ?? '?',
        description: t['description'] as String? ?? '',
      );
    }).toList();
  }

  /// Calls a tool and returns its text content.
  Future<String> callTool(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final server = servers.firstWhere(
      (s) => s.name == serverName,
      orElse: () => throw Exception('MCP server "$serverName" not configured'),
    );
    final sessionId = await _initialize(server);
    final result = await _rpc(
      server,
      'tools/call',
      {'name': toolName, 'arguments': arguments},
      sessionId: sessionId,
    );
    final content = result['content'] as List? ?? const [];
    final texts = content
        .whereType<Map<String, dynamic>>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String? ?? '')
        .toList();
    final out = texts.join('\n').trim();
    return out.isEmpty ? jsonEncode(result) : out;
  }
}
