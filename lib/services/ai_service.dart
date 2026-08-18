import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import '../models/chat_attachment.dart';

class AiResponse {
  final String content;
  final int totalTokens;

  /// Reasoning produced by thinking models, kept separate from the
  /// visible answer so the UI can show it collapsed.
  final String? thinking;

  AiResponse(this.content, this.totalTokens, {this.thinking});
}

/// Thrown when the AI provider responds with HTTP 429 (rate limited).
class RateLimitException implements Exception {
  final String message;
  final Duration? retryAfter;
  RateLimitException(this.message, [this.retryAfter]);
  @override
  String toString() => message;
}

/// A ready-made provider endpoint for the model picker / settings chips.
class AiProviderPreset {
  final String name;
  final String baseUrl;
  final String defaultModel;
  final String? note;
  const AiProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    this.note,
  });
}

class AiService {
  static const String _defaultBaseUrl = 'https://api.deepseek.com';
  static const String _defaultModel = 'deepseek-chat';
  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';

  static const String openaiBaseUrl = 'https://api.openai.com/v1';
  static const String openaiDefaultModel = 'gpt-5.6-terra';
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai/';
  static const String geminiDefaultModel = 'gemini-3.6-flash';
  static const String anthropicBaseUrl = 'https://api.anthropic.com/v1';
  static const String anthropicDefaultModel = 'claude-sonnet-5';
  static const String _anthropicVersion = '2023-06-01';

  /// All built-in provider presets shown in the model picker.
  static const List<AiProviderPreset> providerPresets = [
    AiProviderPreset(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
    ),
    AiProviderPreset(
      name: 'NVIDIA NIM',
      baseUrl: nvidiaBaseUrl,
      defaultModel: nvidiaDefaultModel,
      note: 'Free tier available',
    ),
    AiProviderPreset(
      name: 'OpenAI',
      baseUrl: openaiBaseUrl,
      defaultModel: openaiDefaultModel,
    ),
    AiProviderPreset(
      name: 'Gemini',
      baseUrl: geminiBaseUrl,
      defaultModel: geminiDefaultModel,
      note: 'OpenAI-compatible endpoint',
    ),
    AiProviderPreset(
      name: 'Claude (Anthropic)',
      baseUrl: anthropicBaseUrl,
      defaultModel: anthropicDefaultModel,
      note: 'Needs paid console.anthropic.com key',
    ),
    AiProviderPreset(
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.3-70b-versatile',
      note: 'Very fast, free tier',
    ),
    AiProviderPreset(
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      defaultModel: 'meta-llama/llama-3.3-70b-instruct:free',
      note: 'One key, many providers',
    ),
    AiProviderPreset(
      name: 'Mistral',
      baseUrl: 'https://api.mistral.ai/v1',
      defaultModel: 'mistral-small-latest',
    ),
    AiProviderPreset(
      name: 'xAI (Grok)',
      baseUrl: 'https://api.x.ai/v1',
      defaultModel: 'grok-3-mini',
    ),
    AiProviderPreset(
      name: 'Moonshot Kimi',
      baseUrl: 'https://api.moonshot.ai/v1',
      defaultModel: 'kimi-k2-0905-preview',
    ),
    AiProviderPreset(
      name: 'Zhipu GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      defaultModel: 'glm-4.5-flash',
      note: 'Free tier available',
    ),
    AiProviderPreset(
      name: 'Cerebras',
      baseUrl: 'https://api.cerebras.ai/v1',
      defaultModel: 'llama-3.3-70b',
      note: 'Extremely fast, free tier',
    ),
    AiProviderPreset(
      name: 'Together AI',
      baseUrl: 'https://api.together.xyz/v1',
      defaultModel: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    ),
    AiProviderPreset(
      name: 'Ollama Cloud',
      baseUrl: 'https://ollama.com/v1',
      defaultModel: 'gemma3:4b',
    ),
    AiProviderPreset(
      name: 'Local server',
      baseUrl: 'http://192.168.1.X:8080/v1',
      defaultModel: 'local-model',
      note: 'llama.cpp / LM Studio',
    ),
  ];

  /// Free chat models verified in NVIDIA's NIM catalog.
  static const List<String> nvidiaFreeChatModels = [
    'z-ai/glm-5.2',
    'nvidia/nemotron-3-nano-30b-a3b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nvidia-nemotron-nano-9b-v2',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'meta/llama-3.3-70b-instruct',
    'meta/llama-3.2-3b-instruct',
    'meta/llama-3.1-8b-instruct',
    'meta/llama-3.1-70b-instruct',
    'mistralai/mistral-nemotron',
    'deepseek-ai/deepseek-v4-flash',
    'deepseek-ai/deepseek-v4-pro',
  ];

  static bool isNvidiaBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.toLowerCase() == 'integrate.api.nvidia.com';
  }

  static bool isAnthropicBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.toLowerCase() == 'api.anthropic.com';
  }

  static List<String> filterNvidiaFreeModels(Iterable<String> models) {
    final availableModels = models.toSet();
    return nvidiaFreeChatModels
        .where(availableModels.contains)
        .toList(growable: false);
  }

  String? _apiKey;
  String _baseUrl = _defaultBaseUrl;
  String _model = _defaultModel;
  int _maxSteps = 15;
  bool _disableMaxSteps = false;
  double _temperature = 1.0;
  int _maxTokens = 1024;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  String _customSystemPrompt = '';
  final List<Map<String, dynamic>> _conversationHistory = [];

  static const String _systemPrompt = '''
You are PrivateAgent, a capable AI assistant that controls an Android phone. You can perform device actions, use external tools, and also have normal conversations.

HOW TO RESPOND:
- Normal conversation (questions, chat, writing, explanations): respond in plain text or markdown. Be direct, helpful and natural.
- Device actions or tools: respond with ONLY a JSON object (no markdown, no code fences, no extra text):
{"action": "action_name", "params": {"key": "value"}, "response": "What you say to the user"}

SIMPLE DEVICE ACTIONS (single step only):
- open_app: {"app_name": "YouTube"} - ONLY when the user JUST wants to open an app
- launch_package: {"package_name": "com.example.app"} - open an app by its package id
- make_call: {"contact_name": "Mom"} OR {"phone_number": "1234567890"}
- send_sms: {"contact_name": "John", "message": "Hello"} OR {"phone_number": "123", "message": "Hi"}
- send_email: {"to": "a@b.com", "subject": "Hi", "body": "..."}
- search_contact: {"query": "John"}
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"}
- set_timer: {"seconds": 300, "label": "Tea"}
- set_volume: {"level": 50} - 0 to 100
- set_brightness: {"level": 50} - 0 to 100
- open_url: {"url": "https://example.com"} - opens in the phone browser
- read_screen: {} - read what is currently on the phone screen
- click_element: {"text": "Accept"} - tap an element by its text
- type_on_screen: {"text": "hello", "field_hint": "Search"}
- scroll_screen: {"direction": "down"} - up, down, left, right
- press_back: {}
- run_adb_command: {"command": "settings put global ..."} - via Shizuku, when available

WEB & KNOWLEDGE TOOLS:
- web_search: {"query": "latest news about X"} - Search the web. ALWAYS use this for current events, prices, weather, "latest", "today", facts you are not sure about, or anything that may have changed. Never invent current data.
- browse_page: {"url": "https://example.com/article"} - Open a web page and read its content (uses the configured CamoFox browser when available).

CODE EXECUTION:
- run_code: {"command": "python3 script.py", "language": "bash"} - Run a command in the remote sandbox server. Use it for calculations, file processing, scraping, or anything easier done with code. If it fails with a routing error, tell the user the sandbox server needs its API routes checked.

MCP PLUGINS:
- mcp_call: {"server": "server_name", "tool": "tool_name", "arguments": {...}} - Call a tool from a configured MCP plugin server. Only use servers/tools the user has configured; if unsure which exist, ask.

MULTI-STEP TASK (anything requiring more than one device action):
- execute_task: {"goal": "description of the full task"} - Automatically reads the screen, taps, scrolls and types step by step.

CRITICAL RULES:
1. If the request contains "and" or involves MULTIPLE steps (open + search, open + send, open + find), you MUST use execute_task. NEVER use open_app for these.
2. execute_task handles everything: opening apps, finding elements, clicking, typing, scrolling.
3. The "response" field is shown to the user IMMEDIATELY, before the action runs. Keep it short and forward-looking ("On it, opening WhatsApp now...") — do not report results you do not have yet.
4. When the user attaches images or files, analyze them directly and refer to them in your answer.
5. Prefer tools over guessing: if you can verify something with web_search, do it.
6. If a tool fails, explain the failure briefly and propose an alternative instead of retrying the same thing blindly.

Examples:
- "Create a new alarm for 7 AM" -> execute_task with goal "Create a new alarm for 7 AM"
- "Open YouTube" -> open_app (just opening, nothing else)
- "What's the weather in Madrid today?" -> web_search
- "Summarize this article: https://..." -> browse_page
''';

  static const String _chatSystemPrompt = '''
You are PrivateAgent, a helpful conversational AI assistant.
Provide direct, natural, and friendly text responses. You cannot perform device actions or run tools.
Answer questions, explain concepts, brainstorm, write emails/messages, and chat with the user in plain text or markdown format.
When the user attaches images or files, analyze them directly.
''';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key');
    _baseUrl = prefs.getString('api_base_url') ?? _defaultBaseUrl;
    _model = prefs.getString('api_model') ?? _defaultModel;
    _maxSteps = prefs.getInt('api_max_steps') ?? 15;
    _disableMaxSteps = prefs.getBool('api_disable_max_steps') ?? false;
    _temperature = prefs.getDouble('api_temperature') ?? 1.0;
    _maxTokens = prefs.getInt('api_max_tokens') ?? 1024;
    _useScreenCompression = prefs.getBool('api_use_screen_compression') ?? true;
    _useSystemPrompt = prefs.getBool('api_use_system_prompt') ?? true;
    _customSystemPrompt = prefs.getString('api_custom_system_prompt') ?? '';
  }

  Future<void> saveSettings({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    String cleanApiKey = apiKey.trim();
    if (cleanApiKey.toLowerCase().startsWith('bearer ')) {
      cleanApiKey = cleanApiKey.substring(7).trim();
    }

    _apiKey = cleanApiKey;
    await prefs.setString('api_key', cleanApiKey);

    if (baseUrl != null && baseUrl.isNotEmpty) {
      _baseUrl = baseUrl;
      await prefs.setString('api_base_url', baseUrl);
    }
    if (model != null && model.isNotEmpty) {
      _model = model;
      await prefs.setString('api_model', model);
    }
  }

  /// Switches endpoint + model in one call (used by the model picker).
  Future<void> selectModel({
    required String baseUrl,
    required String model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = baseUrl;
    _model = model;
    await prefs.setString('api_base_url', baseUrl);
    await prefs.setString('api_model', model);
  }

  Future<void> saveMaxSteps(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    _maxSteps = steps;
    await prefs.setInt('api_max_steps', steps);
  }

  Future<void> saveDisableMaxSteps(bool disable) async {
    final prefs = await SharedPreferences.getInstance();
    _disableMaxSteps = disable;
    await prefs.setBool('api_disable_max_steps', disable);
  }

  Future<void> saveAdvancedSettings({
    required double temperature,
    required int maxTokens,
    required bool useScreenCompression,
    required bool useSystemPrompt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _temperature = temperature;
    _maxTokens = maxTokens;
    _useScreenCompression = useScreenCompression;
    _useSystemPrompt = useSystemPrompt;
    await prefs.setDouble('api_temperature', temperature);
    await prefs.setInt('api_max_tokens', maxTokens);
    await prefs.setBool('api_use_screen_compression', useScreenCompression);
    await prefs.setBool('api_use_system_prompt', useSystemPrompt);
  }

  Future<void> saveCustomSystemPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    _customSystemPrompt = prompt.trim();
    await prefs.setString('api_custom_system_prompt', _customSystemPrompt);
  }

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;
  String get baseUrl => _baseUrl;
  String get model => _model;
  String get apiKey => _apiKey ?? '';
  int get maxSteps => _disableMaxSteps ? 999 : _maxSteps;
  int get rawMaxSteps => _maxSteps;
  bool get disableMaxSteps => _disableMaxSteps;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  bool get useScreenCompression => _useScreenCompression;
  bool get useSystemPrompt => _useSystemPrompt;
  String get customSystemPrompt => _customSystemPrompt;

  /// Display name of the provider matching the current base URL, if any.
  String get providerName {
    for (final p in providerPresets) {
      final presetHost = Uri.tryParse(p.baseUrl)?.host;
      final currentHost = Uri.tryParse(_baseUrl)?.host;
      if (presetHost != null && presetHost == currentHost) return p.name;
    }
    return Uri.tryParse(_baseUrl)?.host ?? 'Custom';
  }

  int get _effectiveMaxTokens {
    if (isNvidiaBaseUrl(_baseUrl) &&
        _model == nvidiaDefaultModel &&
        _maxTokens < 4096) {
      return 4096;
    }
    return _maxTokens;
  }

  void clearHistory() {
    _conversationHistory.clear();
  }

  void addHistoryMessage(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }
  }

  String? _composeSystemPrompt(String basePrompt) {
    if (!_useSystemPrompt) return null;
    final custom = _customSystemPrompt.trim();
    if (custom.isEmpty) return basePrompt;
    return '$basePrompt\n\n--- Additional instructions from the user ---\n$custom';
  }

  Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds == null) return null;
    return Duration(seconds: seconds.clamp(1, 300));
  }

  String _extractErrorMessage(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] is Map<String, dynamic>) {
          return decoded['error']['message']?.toString() ?? body;
        } else if (decoded['error'] is String) {
          return decoded['error'] as String;
        }
      }
    } catch (_) {}
    return body;
  }

  Future<AiResponse> _sendWithRetry(
    Future<AiResponse> Function() call, {
    void Function(String)? onRetry,
  }) async {
    const int maxRateLimitRetries = 6;
    const int maxOtherRetries = 4;
    int rateLimitAttempt = 0;
    int otherAttempt = 0;

    while (true) {
      try {
        return await call();
      } on RateLimitException catch (e) {
        rateLimitAttempt++;
        if (rateLimitAttempt > maxRateLimitRetries) {
          throw Exception(
            'API error (429): ${e.message}. Gave up after $maxRateLimitRetries retries.',
          );
        }
        final wait = e.retryAfter ??
            Duration(seconds: (12 * rateLimitAttempt).clamp(12, 60));
        developer.log(
          'Rate limited (429), retrying in ${wait.inSeconds}s ($rateLimitAttempt/$maxRateLimitRetries)',
          name: 'PrivateAgent',
        );
        onRetry?.call(
          'Rate limited by the API (429). Waiting ${wait.inSeconds}s before retrying '
          '($rateLimitAttempt/$maxRateLimitRetries)...',
        );
        await Future.delayed(wait);
      } catch (e) {
        otherAttempt++;
        if (otherAttempt > maxOtherRetries) {
          if (e is Exception) rethrow;
          throw Exception('Network error after $maxOtherRetries retries: $e');
        }
        final wait = Duration(seconds: 3 * otherAttempt);
        developer.log(
          'API call failed ($e), retrying $otherAttempt/$maxOtherRetries in ${wait.inSeconds}s...',
          name: 'PrivateAgent',
        );
        onRetry?.call(
          'Request failed ($e). Retrying in ${wait.inSeconds}s ($otherAttempt/$maxOtherRetries)...',
        );
        await Future.delayed(wait);
      }
    }
  }

  // ─── Message building (with attachments) ──────────────────────────

  /// Builds the user message payload for the current request.
  /// With no attachments this is a plain string map; with attachments it
  /// uses the provider's multimodal content format.
  Map<String, dynamic> _buildUserMessage(
    String text,
    List<ChatAttachment> attachments, {
    required bool anthropic,
  }) {
    if (attachments.isEmpty) {
      return {'role': 'user', 'content': text};
    }

    // Text-like attachments are inlined as extra context.
    final buffer = StringBuffer(text);
    final images = <ChatAttachment>[];
    final noted = <String>[];
    for (final a in attachments) {
      if (a.isImage && a.base64Data != null) {
        images.add(a);
      } else if (a.isTextLike && a.textContent != null) {
        buffer.writeln('\n\n--- Attached file: ${a.name} ---\n${a.textContent}');
      } else {
        noted.add('${a.name} (${a.mimeType}, ${a.humanSize})');
      }
    }
    if (noted.isNotEmpty) {
      buffer.writeln(
        '\n\n[User attached files that cannot be read inline: ${noted.join(', ')}]',
      );
    }

    if (images.isEmpty) {
      return {'role': 'user', 'content': buffer.toString()};
    }

    if (anthropic) {
      return {
        'role': 'user',
        'content': [
          for (final img in images)
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': img.mimeType,
                'data': img.base64Data,
              },
            },
          {'type': 'text', 'text': buffer.toString()},
        ],
      };
    }

    return {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': buffer.toString()},
        for (final img in images)
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:${img.mimeType};base64,${img.base64Data}',
            },
          },
      ],
    };
  }

  String _historyLabel(String text, List<ChatAttachment> attachments) {
    if (attachments.isEmpty) return text;
    final names = attachments.map((a) => a.name).join(', ');
    return '$text\n[attached: $names]';
  }

  // ─── Wire formats ─────────────────────────────────────────────────

  Future<AiResponse> _sendChatCompletion({
    required String? systemPrompt,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
  }) {
    if (isAnthropicBaseUrl(_baseUrl)) {
      return _sendAnthropicMessages(
        systemPrompt: systemPrompt,
        messages: messages,
        maxTokens: maxTokens,
      );
    }
    return _sendOpenAiCompatible(
      systemPrompt: systemPrompt,
      messages: messages,
      maxTokens: maxTokens,
    );
  }

  Future<AiResponse> _sendOpenAiCompatible({
    required String? systemPrompt,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
  }) async {
    final fullMessages = [
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    String requestUrl = _baseUrl;
    if (!requestUrl.endsWith('/chat/completions')) {
      requestUrl = requestUrl.endsWith('/')
          ? '${requestUrl}chat/completions'
          : '$requestUrl/chat/completions';
    }

    final response = await http
        .post(
          Uri.parse(requestUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            'HTTP-Referer': 'https://github.com/karmaoriginal/private-agent',
            'X-Title': 'PrivateAgent',
          },
          body: jsonEncode({
            'model': _model,
            'messages': fullMessages,
            'temperature': _temperature,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode == 429) {
      throw RateLimitException(
        _extractErrorMessage(response.body, response.statusCode),
        _parseRetryAfter(response.headers['retry-after']),
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'API error (${response.statusCode}): '
        '${_extractErrorMessage(response.body, response.statusCode)}',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
      throw Exception('Unexpected API response format: $data');
    }
    final message = data['choices'][0]['message'] as Map<String, dynamic>? ?? {};
    String content = message['content'] as String? ?? '';

    // Reasoning can arrive as a separate field and/or <think> blocks.
    final buffer = StringBuffer();
    final reasoning = message['reasoning_content'] ?? message['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) buffer.write(reasoning);

    final thinkMatch = RegExp(r'<think>([\s\S]*?)</think>').firstMatch(content);
    if (thinkMatch != null) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(thinkMatch.group(1));
    }
    content = content
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .trim();

    if (content.isEmpty) {
      throw Exception(
        'API returned an empty response. This may be due to strict rate limits or safety filters.',
      );
    }

    int tokens = 0;
    if (data.containsKey('usage') &&
        data['usage'] is Map &&
        data['usage']['total_tokens'] != null) {
      tokens = data['usage']['total_tokens'] as int;
    }
    final thinking = buffer.toString().trim();
    return AiResponse(content, tokens, thinking: thinking.isEmpty ? null : thinking);
  }

  Future<AiResponse> _sendAnthropicMessages({
    required String? systemPrompt,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
  }) async {
    String cleanBase = _baseUrl.trim();
    if (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }
    if (cleanBase.endsWith('/messages')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - '/messages'.length);
    }
    if (!cleanBase.endsWith('/v1')) {
      cleanBase = '$cleanBase/v1';
    }
    final requestUrl = '$cleanBase/messages';

    final body = <String, dynamic>{
      'model': _model,
      'max_tokens': maxTokens,
      'messages': messages,
      'temperature': _temperature > 1.0 ? 1.0 : _temperature,
    };
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }

    final response = await http
        .post(
          Uri.parse(requestUrl),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': _apiKey ?? '',
            'anthropic-version': _anthropicVersion,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode == 429) {
      throw RateLimitException(
        _extractErrorMessage(response.body, response.statusCode),
        _parseRetryAfter(response.headers['retry-after']),
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'API error (${response.statusCode}): '
        '${_extractErrorMessage(response.body, response.statusCode)}',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['content'] is! List) {
      throw Exception('Unexpected API response format: $data');
    }
    final blocks = data['content'] as List;
    final text = blocks
        .where((b) => b is Map && b['type'] == 'text')
        .map((b) => (b as Map)['text'] as String? ?? '')
        .join()
        .trim();
    final thinking = blocks
        .where((b) => b is Map && (b['type'] == 'thinking' || b['type'] == 'redacted_thinking'))
        .map((b) => (b as Map)['thinking'] as String? ?? '')
        .join()
        .trim();

    if (text.isEmpty) {
      throw Exception(
        'API returned an empty response. This may be due to strict rate limits or safety filters.',
      );
    }

    int tokens = 0;
    if (data['usage'] is Map) {
      final usage = data['usage'] as Map;
      final inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
      final outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;
      tokens = inputTokens + outputTokens;
    }
    return AiResponse(text, tokens, thinking: thinking.isEmpty ? null : thinking);
  }

  /// Send a message and get a full (non-streaming) response.
  Future<String> sendMessage(
    String message, {
    bool isAgentMode = true,
    List<ChatAttachment> attachments = const [],
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    final anthropic = isAnthropicBaseUrl(_baseUrl);
    _conversationHistory.add(
      _buildUserMessage(
        _historyLabel(message, attachments),
        attachments,
        anthropic: anthropic,
      ),
    );

    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    try {
      final basePrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final composedSystem = _composeSystemPrompt(basePrompt);

      final aiResponse = await _sendWithRetry(
        () => _sendChatCompletion(
          systemPrompt: composedSystem,
          messages: _conversationHistory,
          maxTokens: _effectiveMaxTokens,
        ),
      );

      _conversationHistory.add({
        'role': 'assistant',
        'content': aiResponse.content,
      });

      return aiResponse.content;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a message and stream the response chunk-by-chunk.
  /// [onThinking] receives the accumulated reasoning text as it grows
  /// (null-capable; may never fire for non-reasoning models).
  Stream<String> sendMessageStream(
    String message, {
    bool isAgentMode = true,
    List<ChatAttachment> attachments = const [],
    void Function(String thinking)? onThinking,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    final anthropic = isAnthropicBaseUrl(_baseUrl);
    _conversationHistory.add(
      _buildUserMessage(
        _historyLabel(message, attachments),
        attachments,
        anthropic: anthropic,
      ),
    );

    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    final basePrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
    final composedSystem = _composeSystemPrompt(basePrompt);

    // Anthropic: fetch full response, emit as a single chunk.
    if (anthropic) {
      try {
        final aiResponse = await _sendWithRetry(
          () => _sendAnthropicMessages(
            systemPrompt: composedSystem,
            messages: _conversationHistory,
            maxTokens: _effectiveMaxTokens,
          ),
        );
        if (aiResponse.thinking != null) {
          onThinking?.call(aiResponse.thinking!);
        }
        _conversationHistory.add({
          'role': 'assistant',
          'content': aiResponse.content,
        });
        yield aiResponse.content;
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Network error: $e');
      }
      return;
    }

    try {
      final fullMessages = [
        if (composedSystem != null && composedSystem.isNotEmpty)
          {'role': 'system', 'content': composedSystem},
        ..._conversationHistory,
      ];

      String requestUrl = _baseUrl;
      if (!requestUrl.endsWith('/chat/completions')) {
        requestUrl = requestUrl.endsWith('/')
            ? '${requestUrl}chat/completions'
            : '$requestUrl/chat/completions';
      }

      const int maxConnectAttempts = 3;
      int connectAttempt = 0;
      late http.Client client;
      late http.StreamedResponse response;

      while (true) {
        connectAttempt++;
        client = http.Client();
        final request = http.Request('POST', Uri.parse(requestUrl));
        request.headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://github.com/karmaoriginal/private-agent',
          'X-Title': 'PrivateAgent',
        });
        request.body = jsonEncode({
          'model': _model,
          'messages': fullMessages,
          'temperature': _temperature,
          'max_tokens': _effectiveMaxTokens,
          'stream': true,
        });

        response = await client.send(request).timeout(const Duration(minutes: 3));

        if (response.statusCode == 429 && connectAttempt < maxConnectAttempts) {
          final body = await response.stream.bytesToString();
          final wait = _parseRetryAfter(response.headers['retry-after']) ??
              Duration(seconds: 10 * connectAttempt);
          developer.log(
            'Stream request rate limited (429), retrying in ${wait.inSeconds}s '
            '($connectAttempt/$maxConnectAttempts): $body',
            name: 'PrivateAgent',
          );
          client.close();
          await Future.delayed(wait);
          continue;
        }
        break;
      }

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final errorMessage = _extractErrorMessage(body, response.statusCode);
        client.close();
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final accumulatedContent = StringBuffer();
      final accumulatedThinking = StringBuffer();
      bool inThinkBlock = false;

      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        if (trimmedLine.startsWith('data:')) {
          final dataStr = trimmedLine.substring(5).trim();
          if (dataStr == '[DONE]') break;
          try {
            final json = jsonDecode(dataStr);
            if (json is Map && json['choices'] is List) {
              final choices = json['choices'] as List;
              if (choices.isNotEmpty) {
                final choice = choices[0];
                if (choice is! Map) continue;
                final rawDelta = choice['delta'];
                final delta = rawDelta is Map ? rawDelta : const {};

                // Reasoning models (DeepSeek-R1, GLM, etc.) stream reasoning
                // in a dedicated field — capture it as "thinking".
                final reasoningDelta =
                    delta['reasoning_content'] ?? delta['reasoning'];
                if (reasoningDelta is String && reasoningDelta.isNotEmpty) {
                  accumulatedThinking.write(reasoningDelta);
                  onThinking?.call(accumulatedThinking.toString());
                }

                final rawContent = delta['content'];
                if (rawContent is String && rawContent.isNotEmpty) {
                  final content = rawContent;
                  accumulatedContent.write(content);

                  // Inline <think> blocks also count as thinking.
                  if (content.contains('<think>')) {
                    inThinkBlock = true;
                    final parts = content.split('<think>');
                    if (parts[0].isNotEmpty) yield parts[0];
                    if (parts.length > 1) {
                      accumulatedThinking.write(parts.sublist(1).join('<think>'));
                      onThinking?.call(accumulatedThinking.toString());
                    }
                  } else if (content.contains('</think>')) {
                    inThinkBlock = false;
                    final parts = content.split('</think>');
                    accumulatedThinking.write(parts[0]);
                    onThinking?.call(accumulatedThinking.toString());
                    if (parts.length > 1 && parts[1].isNotEmpty) {
                      yield parts[1];
                    }
                  } else if (inThinkBlock) {
                    accumulatedThinking.write(content);
                    onThinking?.call(accumulatedThinking.toString());
                  } else {
                    yield content;
                  }
                }
                if (choice['finish_reason'] != null) break;
              }
            }
          } catch (_) {
            // Ignore incomplete chunks
          }
        }
      }

      client.close();

      String finalResponse = accumulatedContent.toString().trim();
      finalResponse = finalResponse
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      if (finalResponse.isEmpty) {
        throw Exception(
          'The model finished without a visible answer. Increase Max Tokens '
          'or try another model.',
        );
      }
      _conversationHistory.add({'role': 'assistant', 'content': finalResponse});
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a task execution message — no conversation history, limited tokens.
  Future<AiResponse> sendTaskMessage(
    String systemPrompt,
    String prompt, {
    void Function(String)? onRetry,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    final composedSystem = _composeSystemPrompt(systemPrompt);

    return _sendWithRetry(
      () => _sendChatCompletion(
        systemPrompt: composedSystem,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: _effectiveMaxTokens,
      ),
      onRetry: onRetry,
    );
  }

  /// Parse the AI response to check if it's an action or plain text
  AgentAction? parseAction(String response) {
    try {
      final trimmed = response.trim();
      String jsonStr = trimmed;
      if (trimmed.startsWith('```')) {
        final lines = trimmed.split('\n');
        lines.removeAt(0);
        if (lines.isNotEmpty && lines.last.trim() == '```') {
          lines.removeLast();
        }
        jsonStr = lines.join('\n').trim();
      }

      if (jsonStr.startsWith('{') && !jsonStr.endsWith('}')) {
        jsonStr += '\n}';
      }

      if (jsonStr.startsWith('{') && jsonStr.contains('"action"')) {
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (json.containsKey('action')) {
            return AgentAction.fromJson(json);
          }
        } catch (e) {
          if (e.toString().contains('Unexpected end of input')) {
            jsonStr += '\n}';
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (json.containsKey('action')) {
              return AgentAction.fromJson(json);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetches available models from the provider's /models endpoint
  Future<List<String>> fetchAvailableModels(
    String baseUrl,
    String apiKey,
  ) async {
    try {
      String cleanBaseUrl = baseUrl;
      if (cleanBaseUrl.endsWith('/chat/completions')) {
        cleanBaseUrl = cleanBaseUrl.replaceAll('/chat/completions', '');
      }

      final bool anthropic = isAnthropicBaseUrl(cleanBaseUrl);
      String modelsUrl = cleanBaseUrl;
      if (modelsUrl.endsWith('/')) {
        modelsUrl = modelsUrl.substring(0, modelsUrl.length - 1);
      }
      if (anthropic && modelsUrl.endsWith('/messages')) {
        modelsUrl = modelsUrl.substring(0, modelsUrl.length - '/messages'.length);
      }
      if (anthropic && !modelsUrl.endsWith('/v1')) {
        modelsUrl = '$modelsUrl/v1';
      }

      final response = await http.get(
        Uri.parse('$modelsUrl/models'),
        headers: anthropic
            ? {
                'x-api-key': apiKey,
                'anthropic-version': _anthropicVersion,
              }
            : {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models;
        if (data is Map && data.containsKey('data')) {
          final modelsList = data['data'] as List;
          models = modelsList.map((m) => m['id'].toString()).toList();
        } else if (data is List) {
          models = data.map((m) => m['id'].toString()).toList();
        } else {
          return [];
        }

        if (isNvidiaBaseUrl(cleanBaseUrl)) {
          return filterNvidiaFreeModels(models);
        }
        models.sort();
        return models;
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
