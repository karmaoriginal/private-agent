import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mcp_service.dart';
import '../services/sandbox_service.dart';
import '../services/search_service.dart';
import '../services/voice_service.dart';

/// Integrations hub: voice engines (device/API TTS, STT), web search
/// (Camofox / DuckDuckGo / Tavily / Brave), the remote sandbox, and MCP
/// plugin servers.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final _sandbox = SandboxService();
  final _mcp = McpService();
  final _search = SearchService();

  // Voice
  String _ttsEngine = 'device';
  final _ttsModelCtrl = TextEditingController();
  final _ttsVoiceCtrl = TextEditingController();
  String _language = 'es-ES';
  double _rate = 0.5;
  double _pitch = 1.0;
  bool _partial = true;

  // Search
  String _searchProvider = 'duckduckgo';
  final _tavilyCtrl = TextEditingController();
  final _braveCtrl = TextEditingController();
  final _camofoxUrlCtrl = TextEditingController();
  final _camofoxKeyCtrl = TextEditingController();
  bool? _camofoxHealthy;

  // Sandbox
  final _sandboxUrlCtrl = TextEditingController();
  bool? _sandboxHealthy;

  bool _loading = true;

  static const _languages = [
    'es-ES', 'es-MX', 'en-US', 'en-GB', 'fr-FR',
    'de-DE', 'it-IT', 'pt-BR', 'ca-ES',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _sandbox.init();
    await _mcp.init();
    await _search.init();

    _ttsEngine = prefs.getString('voice_tts_engine') ?? 'device';
    _ttsModelCtrl.text = prefs.getString('voice_tts_model') ?? 'tts-1';
    _ttsVoiceCtrl.text = prefs.getString('voice_tts_voice') ?? 'alloy';
    _language = prefs.getString('voice_language') ?? 'es-ES';
    _rate = prefs.getDouble('voice_rate') ?? 0.5;
    _pitch = prefs.getDouble('voice_pitch') ?? 1.0;
    _partial = prefs.getBool('voice_partial_results') ?? true;

    _searchProvider = _search.provider;
    _tavilyCtrl.text = _search.tavilyKey;
    _braveCtrl.text = _search.braveKey;
    _camofoxUrlCtrl.text = _search.camofox.baseUrl;
    _camofoxKeyCtrl.text = prefs.getString('camofox_key') ?? '';

    _sandboxUrlCtrl.text = _sandbox.baseUrl;

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveVoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_tts_engine', _ttsEngine);
    await prefs.setString('voice_tts_model', _ttsModelCtrl.text.trim());
    await prefs.setString('voice_tts_voice', _ttsVoiceCtrl.text.trim());
    await prefs.setString('voice_language', _language);
    await prefs.setDouble('voice_rate', _rate);
    await prefs.setDouble('voice_pitch', _pitch);
    await prefs.setBool('voice_partial_results', _partial);
  }

  Future<void> _saveSearch() async {
    await _search.saveSettings(
      provider: _searchProvider,
      tavilyKey: _tavilyCtrl.text,
      braveKey: _braveCtrl.text,
    );
    await _search.camofox.saveSettings(_camofoxUrlCtrl.text, _camofoxKeyCtrl.text);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _ttsModelCtrl.dispose();
    _ttsVoiceCtrl.dispose();
    _tavilyCtrl.dispose();
    _braveCtrl.dispose();
    _camofoxUrlCtrl.dispose();
    _camofoxKeyCtrl.dispose();
    _sandboxUrlCtrl.dispose();
    super.dispose();
  }

  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      color: Theme.of(context).primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (subtitle != null)
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Integrations',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _buildVoiceCard(),
                _buildSearchCard(),
                _buildSandboxCard(),
                _buildMcpCard(),
              ],
            ),
    );
  }

  // ─── Voice ────────────────────────────────────────────────────────

  Widget _buildVoiceCard() {
    return _card(
      icon: Icons.record_voice_over_outlined,
      title: 'Voice (TTS & STT)',
      subtitle: 'Speech engine, language and the provider TTS model',
      children: [
        const Text('Text-to-speech engine',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'device',
                label: Text('Device', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.phone_android_rounded, size: 16),
              ),
              ButtonSegment(
                value: 'api',
                label: Text('API model', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.cloud_outlined, size: 16),
              ),
            ],
            selected: {_ttsEngine},
            onSelectionChanged: (s) {
              setState(() => _ttsEngine = s.first);
              _saveVoice();
            },
          ),
        ),
        if (_ttsEngine == 'api') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _ttsModelCtrl,
            decoration: const InputDecoration(
              labelText: 'TTS model',
              hintText: 'tts-1, tts-1-hd, ...',
              isDense: true,
            ),
            onChanged: (_) => _saveVoice(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ttsVoiceCtrl,
            decoration: const InputDecoration(
              labelText: 'Voice',
              hintText: 'alloy, nova, shimmer, ...',
              isDense: true,
            ),
            onChanged: (_) => _saveVoice(),
          ),
          const SizedBox(height: 4),
          const Text(
            'Uses the same Base URL and API key as the chat endpoint (/audio/speech).',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: const InputDecoration(
            labelText: 'Language (TTS + speech recognition)',
            isDense: true,
          ),
          items: _languages
              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _language = v);
            _saveVoice();
          },
        ),
        const SizedBox(height: 8),
        Text('Speech rate: ${_rate.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: _rate,
          min: 0.25,
          max: 1.0,
          divisions: 15,
          onChanged: (v) => setState(() => _rate = v),
          onChangeEnd: (_) => _saveVoice(),
        ),
        Text('Pitch: ${_pitch.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: _pitch,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          onChanged: (v) => setState(() => _pitch = v),
          onChangeEnd: (_) => _saveVoice(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Live partial transcription', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Show words as you speak',
              style: TextStyle(fontSize: 11)),
          value: _partial,
          onChanged: (v) {
            setState(() => _partial = v);
            _saveVoice();
          },
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () async {
            await _saveVoice();
            final test = VoiceService();
            await test.init();
            await test.speak(
                'Esto es una **prueba** de voz 😄 con markdown y emojis.');
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Test voice'),
        ),
      ],
    );
  }

  // ─── Search ───────────────────────────────────────────────────────

  Widget _buildSearchCard() {
    return _card(
      icon: Icons.travel_explore_rounded,
      title: 'Web Search',
      subtitle: 'Provider used by the web_search tool',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _searchProvider,
          decoration: const InputDecoration(labelText: 'Provider', isDense: true),
          items: const [
            DropdownMenuItem(
              value: 'duckduckgo',
              child: Text('DuckDuckGo (free, no key)'),
            ),
            DropdownMenuItem(
              value: 'camofox',
              child: Text('CamoFox Browser Server (self-hosted)'),
            ),
            DropdownMenuItem(value: 'tavily', child: Text('Tavily')),
            DropdownMenuItem(value: 'brave', child: Text('Brave Search')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _searchProvider = v);
            _saveSearch();
          },
        ),
        if (_searchProvider == 'tavily') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _tavilyCtrl,
            decoration: const InputDecoration(
                labelText: 'Tavily API key', isDense: true),
            onChanged: (_) => _saveSearch(),
          ),
        ],
        if (_searchProvider == 'brave') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _braveCtrl,
            decoration: const InputDecoration(
                labelText: 'Brave API key', isDense: true),
            onChanged: (_) => _saveSearch(),
          ),
        ],
        if (_searchProvider == 'camofox') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _camofoxUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'CamoFox server URL',
              hintText: 'http://localhost:9377',
              isDense: true,
            ),
            onChanged: (_) => _saveSearch(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _camofoxKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'Access key (CAMOFOX_ACCESS_KEY, optional)',
              isDense: true,
            ),
            onChanged: (_) => _saveSearch(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await _saveSearch();
                  final ok = await _search.camofox.healthCheck();
                  setState(() => _camofoxHealthy = ok);
                  _toast(ok
                      ? 'CamoFox server is healthy'
                      : 'CamoFox server not reachable');
                },
                icon: const Icon(Icons.monitor_heart_outlined, size: 18),
                label: const Text('Test connection'),
              ),
              const SizedBox(width: 8),
              if (_camofoxHealthy != null)
                Icon(
                  _camofoxHealthy!
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color: _camofoxHealthy! ? Colors.green : Colors.red,
                  size: 18,
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Sandbox ──────────────────────────────────────────────────────

  Widget _buildSandboxCard() {
    return _card(
      icon: Icons.terminal_rounded,
      title: 'Remote Sandbox',
      subtitle: 'Server where the agent can run code (run_code tool)',
      children: [
        TextField(
          controller: _sandboxUrlCtrl,
          decoration: const InputDecoration(
            labelText: 'Sandbox URL',
            hintText: SandboxService.defaultUrl,
            isDense: true,
          ),
          onChanged: (_) => _sandbox.saveUrl(_sandboxUrlCtrl.text),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await _sandbox.saveUrl(_sandboxUrlCtrl.text);
                final ok = await _sandbox.healthCheck();
                setState(() => _sandboxHealthy = ok);
                _toast(ok
                    ? 'Sandbox is online'
                    : 'Sandbox /health did not respond OK');
              },
              icon: const Icon(Icons.monitor_heart_outlined, size: 18),
              label: const Text('Health check'),
            ),
            const SizedBox(width: 8),
            if (_sandboxHealthy != null)
              Icon(
                _sandboxHealthy!
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                color: _sandboxHealthy! ? Colors.green : Colors.red,
                size: 18,
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'The agent calls POST /execute with {"command": "...", "language": "bash"}. '
          'If your server exposes different routes, adjust SandboxService.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  // ─── MCP ──────────────────────────────────────────────────────────

  Widget _buildMcpCard() {
    return _card(
      icon: Icons.extension_rounded,
      title: 'MCP Plugins',
      subtitle: 'External tool servers (Model Context Protocol)',
      children: [
        if (_mcp.servers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No MCP servers configured yet.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          ..._mcp.servers.map(
            (server) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dns_rounded, size: 20),
              title: Text(server.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(server.url,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.handyman_outlined, size: 18),
                    tooltip: 'List tools',
                    onPressed: () => _showServerTools(server),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.redAccent),
                    onPressed: () async {
                      await _mcp.removeServer(server.name);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _showAddServerDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add MCP server'),
        ),
      ],
    );
  }

  void _showAddServerDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add MCP server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com/mcp',
              ),
            ),
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(
                labelText: 'API key (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty ||
                  urlCtrl.text.trim().isEmpty) {
                return;
              }
              await _mcp.addServer(
                McpServer(
                  name: nameCtrl.text.trim(),
                  url: urlCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                ),
              );
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showServerTools(McpServer server) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );
    try {
      final tools = await _mcp.listTools(server);
      if (!mounted) return;
      Navigator.pop(context); // close loading
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Tools on ${server.name}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: tools.isEmpty
                ? const Center(child: Text('No tools exposed'))
                : ListView.builder(
                    itemCount: tools.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(tools[i].name,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        tools[i].description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      _toast('Could not reach ${server.name}: $e');
    }
  }
}
