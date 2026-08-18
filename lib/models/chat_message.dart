import 'chat_attachment.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final AgentActionResult? actionResult;

  /// Reasoning / chain-of-thought captured from thinking models
  /// (<think> blocks, reasoning_content deltas). Shown collapsed in the UI.
  final String? thinking;

  /// Files / photos attached to this message (usually user messages).
  final List<ChatAttachment> attachments;

  /// True when this message represents an error, so the UI can style it.
  final bool isError;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.actionResult,
    this.thinking,
    this.attachments = const [],
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'actionResult': actionResult?.toJson(),
        'thinking': thinking,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'isError': isError,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        actionResult: json['actionResult'] != null
            ? AgentActionResult.fromJson(json['actionResult'] as Map<String, dynamic>)
            : null,
        thinking: json['thinking'] as String?,
        attachments: (json['attachments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatAttachment.fromJson)
            .toList(),
        isError: json['isError'] as bool? ?? false,
      );
}

class AgentActionResult {
  final String actionType;
  final bool success;
  final String? details;

  AgentActionResult({
    required this.actionType,
    required this.success,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'success': success,
        'details': details,
      };

  factory AgentActionResult.fromJson(Map<String, dynamic> json) => AgentActionResult(
        actionType: json['actionType'] as String,
        success: json['success'] as bool,
        details: json['details'] as String?,
      );
}
