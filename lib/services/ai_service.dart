import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';

class AiResponse {
  final String content;
  final int totalTokens;
  AiResponse(this.content, this.totalTokens);
}

/// Thrown when the AI provider responds with HTTP 429 (rate limited).
/// Carries the provider's suggested wait time when it sends a Retry-After
/// header, so callers can back off intelligently instead of guessing.
class RateLimitException implements Exception {
  final String message;
  final Duration? retryAfter;
  RateLimitException(this.message, [this.retryAfter]);
  @override
  String toString() => message;
}

class AiService {
  static const String _defaultBaseUrl = 'https://api.deepseek.com';
  static const String _defaultModel = 'deepseek-chat';
  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';

  // Extra "quick select" providers for the Settings screen.
  static const String openaiBaseUrl = 'https://api.openai.com/v1';
  static const String openaiDefaultModel = 'gpt-5.6-terra';
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai/';
  static const String geminiDefaultModel = 'gemini-3.6-flash';
  static const String anthropicBaseUrl = 'https://api.anthropic.com/v1';
  static const String anthropicDefaultModel = 'claude-sonnet-5';
  static const String _anthropicVersion = '2023-06-01';

  /// Free, general-purpose chat endpoints verified in NVIDIA's NIM catalog.
  /// The live /models response is intersected with this list so unavailable or
  /// non-chat models never appear in PrivateAgent's NVIDIA model picker.
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

  /// True when the base URL points at Anthropic's native Messages API, which
  /// uses a different request/response shape (system as a top-level field,
  /// x-api-key auth, content blocks in the reply) than the OpenAI-style
  /// /chat/completions endpoint every other provider in this app speaks.
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
  final List<Map<String, String>> _conversationHistory = [];

  static const String _systemPrompt = '''
You are PrivateAgent, a helpful AI assistant that controls an Android phone. You can perform device actions and also have normal conversations.

When the user wants to perform a device action, you MUST respond with ONLY a JSON object (no markdown, no code fences, no extra text) in this exact format:
{"action": "action_name", "params": {"key": "value"}, "response": "What you say to the user"}

Available actions and their params:

SIMPLE ACTIONS (single step only):
- open_app: {"app_name": "YouTube"} - ONLY use this when the user JUST wants to open an app and nothing else
- make_call: {"contact_name": "Mom"} OR {"phone_number": "1234567890"} - Makes a phone call
- send_sms: {"contact_name": "John", "message": "Hello"} OR {"phone_number": "123", "message": "Hi"} - Sends SMS
- search_contact: {"query": "John"} - Searches contacts
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"} - Sets an alarm
- set_volume: {"level": 50} - Sets volume (0-100)
- set_brightness: {"level": 50} - Sets brightness (0-100)
- read_screen: {} - Read what's currently on the screen
- press_back: {} - Press the back button

MULTI-STEP TASK (for anything that requires more than one action):
- execute_task: {"goal": "description of the full task"} - Automatically reads screen, taps, scrolls, types step by step

CRITICAL RULES:
1. If the user request contains "and" or involves MULTIPLE steps (open + search, open + send, open + find, etc.), you MUST use execute_task. NEVER use open_app for these.
2. execute_task handles everything: opening apps, finding elements, clicking, typing, scrolling.
3. The "response" field is shown to the user IMMEDIATELY, before execute_task starts running. Keep it short and forward-looking (e.g. "On it, opening WhatsApp now...") — it is not a place to report a result you don't have yet.

Examples of when to use execute_task:
- "Create a new alarm for 7 AM" → execute_task with goal "Create a new alarm for 7 AM"
- "Go to YouTube and search for cats" → execute_task
- "Open WhatsApp and send hello to John" → execute_task
- "Open Settings and turn on WiFi" → execute_task
- "Search for restaurants on Google Maps" → execute_task

Examples of when to use open_app:
- "Open YouTube" → open_app (just opening, no further action)
- "Open Settings" → open_app (just opening)

For normal conversation (questions, chat, info requests), just respond with plain text naturally.
''';

  static const String _chatSystemPrompt = '''
You are PrivateAgent, a helpful conversational AI assistant. 
Provide direct, natural, and friendly text responses. You cannot perform device actions or run tools. 
Answer questions, explain concepts, brainstorm, write emails/messages, and chat with the user in plain text or markdown format.
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

    // Clean up the API key in case the user pasted "Bearer sk-..."
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

  /// Saves an extra system prompt that is appended AFTER the app's built-in
  /// system prompt (task or chat), for both multi-step tasks and normal chat.
  /// It is not a replacement — it layers custom instructions on top.
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
  int get rawMaxSteps => _maxSteps; // For the slider UI
  bool get disableMaxSteps => _disableMaxSteps;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  bool get useScreenCompression => _useScreenCompression;
  bool get useSystemPrompt => _useSystemPrompt;
  String get customSystemPrompt => _customSystemPrompt;

  int get _effectiveMaxTokens {
    // GLM is a reasoning model. With the app's 1,024-token default it can
    // consume the whole budget reasoning and finish without visible content.
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

  /// Appends the user's optional custom instructions after a base system
  /// prompt (task or chat). Returns null when the "Send System Prompt"
  /// toggle is off, so no system message is sent at all.
  String? _composeSystemPrompt(String basePrompt) {
    if (!_useSystemPrompt) return null;
    final custom = _customSystemPrompt.trim();
    if (custom.isEmpty) return basePrompt;
    return '$basePrompt\n\n--- Additional instructions from the user ---\n$custom';
  }

  /// Parses a numeric Retry-After header (seconds). Non-numeric values
  /// (HTTP-date form) are ignored in favor of the caller's own backoff.
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
    } catch (_) {
      // Not JSON, fall through to the raw body.
    }
    return body;
  }

  /// Retries transient failures. Rate limits (HTTP 429) get longer,
  /// provider-aware backoff — honoring the Retry-After header when the
  /// provider sends one — and more attempts than other network errors,
  /// since a busy free-tier endpoint (e.g. NVIDIA NIM) usually recovers if
  /// you wait long enough instead of aborting the whole task.
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
        final wait =
            e.retryAfter ?? Duration(seconds: (12 * rateLimitAttempt).clamp(12, 60));
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

  /// Dispatches to the right wire format for the configured provider.
  Future<AiResponse> _sendChatCompletion({
    required String? systemPrompt,
    required List<Map<String, String>> messages,
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

  /// Any provider that speaks the OpenAI /chat/completions wire format
  /// (DeepSeek, OpenRouter, Groq, Ollama, NVIDIA NIM, OpenAI, Gemini's
  /// OpenAI-compatibility endpoint, local servers, etc).
  Future<AiResponse> _sendOpenAiCompatible({
    required String? systemPrompt,
    required List<Map<String, String>> messages,
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
            'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
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
    String content = data['choices'][0]['message']['content'] as String? ?? '';

    // Strip <think> blocks commonly produced by reasoning models
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
    return AiResponse(content, tokens);
  }

  /// Anthropic's native Messages API (api.anthropic.com). This is a
  /// pay-per-token API key from console.anthropic.com — it is billed
  /// separately from, and is NOT the same thing as, a Claude.ai Pro/Max
  /// subscription, which does not expose API access.
  Future<AiResponse> _sendAnthropicMessages({
    required String? systemPrompt,
    required List<Map<String, String>> messages,
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
      // Anthropic's temperature range is 0.0-1.0, unlike some OpenAI-style
      // providers that accept up to 2.0.
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
    return AiResponse(text, tokens);
  }

  /// Send a message to the AI and get a full (non-streaming) response.
  /// Used by the Telegram remote-control integration.
  Future<String> sendMessage(String message, {bool isAgentMode = true}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    // Add ONLY the text to the persistent conversation history to save tokens.
    _conversationHistory.add({'role': 'user', 'content': message});

    // Keep conversation history manageable (last 20 messages)
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
  Stream<String> sendMessageStream(
    String message, {
    bool isAgentMode = true,
  }) async* {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});

    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    final basePrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
    final composedSystem = _composeSystemPrompt(basePrompt);

    // Anthropic's Messages API uses a different SSE event schema than the
    // OpenAI-style delta stream below. Rather than duplicate a whole second
    // stream parser, fetch the full response (with the same retry/backoff
    // handling as everything else) and emit it as a single chunk.
    if (isAnthropicBaseUrl(_baseUrl)) {
      try {
        final aiResponse = await _sendWithRetry(
          () => _sendAnthropicMessages(
            systemPrompt: composedSystem,
            messages: _conversationHistory,
            maxTokens: _effectiveMaxTokens,
          ),
        );
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

      // Retry a rate-limited connection attempt (before any bytes have
      // streamed back) a few times with backoff, same spirit as the
      // non-streaming retry helper but kept lightweight since this is a
      // single request/response, not a multi-step task loop.
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
          'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
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
      bool inThinkBlock = false;

      // Listen to response stream
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
                final rawContent = delta['content'];
                if (rawContent is String && rawContent.isNotEmpty) {
                  final content = rawContent;
                  accumulatedContent.write(content);

                  // Handle <think> block stripping on the fly for better stream styling
                  if (content.contains('<think>')) {
                    inThinkBlock = true;
                    // If there is text before <think>, yield it
                    final parts = content.split('<think>');
                    if (parts[0].isNotEmpty) {
                      yield parts[0];
                    }
                  } else if (content.contains('</think>')) {
                    inThinkBlock = false;
                    // If there is text after </think>, yield it
                    final parts = content.split('</think>');
                    if (parts.length > 1 && parts[1].isNotEmpty) {
                      yield parts[1];
                    }
                  } else if (!inThinkBlock) {
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

      // Clean up final accumulated response and add to history
      String finalResponse = accumulatedContent.toString().trim();
      finalResponse = finalResponse
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      if (finalResponse.isEmpty) {
        throw Exception(
          'The model finished without a visible answer. Increase Max Tokens '
          'or try another NVIDIA model.',
        );
      }
      _conversationHistory.add({'role': 'assistant', 'content': finalResponse});
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a task execution message — no conversation history, low temperature, limited tokens.
  /// This is much faster and cheaper than sendMessage.
  ///
  /// [onRetry] is called (instead of throwing) whenever a transient failure
  /// (e.g. a 429 rate limit) is being retried, so the caller can surface a
  /// friendly progress message instead of a scary raw error mid-task.
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
    // Try to parse as JSON action
    try {
      final trimmed = response.trim();
      // Handle if the response is wrapped in code fences
      String jsonStr = trimmed;
      if (trimmed.startsWith('```')) {
        final lines = trimmed.split('\n');
        lines.removeAt(0); // Remove opening fence
        if (lines.isNotEmpty && lines.last.trim() == '```') {
          lines.removeLast(); // Remove closing fence
        }
        jsonStr = lines.join('\n').trim();
      }

      // If it looks like JSON but is missing a closing brace (common with some local models)
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
          // If it still fails, it might be deeply truncated, try adding another brace
          if (e.toString().contains('Unexpected end of input')) {
            jsonStr += '\n}';
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (json.containsKey('action')) {
              return AgentAction.fromJson(json);
            }
          }
        }
      }
    } catch (_) {
      // Not JSON, it's plain text conversation
    }
    return null;
  }

  /// Fetches available models from the provider's /models endpoint
  Future<List<String>> fetchAvailableModels(
    String baseUrl,
    String apiKey,
  ) async {
    try {
      String cleanBaseUrl = baseUrl;
      // Many providers host it at /models, but some require the base URL without /chat/completions logic
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
      print('Error fetching models: $e');
      return [];
    }
  }
}
