import 'dart:convert';

/// A file or photo the user attached to a chat message.
class ChatAttachment {
  final String name;
  final String path;
  final String mimeType;
  final int sizeBytes;

  /// Base64 payload sent to the model (images and small text files only).
  /// Intentionally NOT persisted to history to keep storage small.
  final String? base64Data;

  const ChatAttachment({
    required this.name,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    this.base64Data,
  });

  bool get isImage => mimeType.startsWith('image/');

  bool get isTextLike =>
      mimeType.startsWith('text/') ||
      mimeType == 'application/json' ||
      name.endsWith('.md') ||
      name.endsWith('.dart') ||
      name.endsWith('.kt') ||
      name.endsWith('.json') ||
      name.endsWith('.yaml') ||
      name.endsWith('.yml') ||
      name.endsWith('.txt') ||
      name.endsWith('.csv') ||
      name.endsWith('.py') ||
      name.endsWith('.js');

  String get humanSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Decoded text content for text-like files (null for binaries).
  String? get textContent {
    if (!isTextLike || base64Data == null) return null;
    try {
      return utf8.decode(base64Decode(base64Data!));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        name: json['name'] as String? ?? 'file',
        path: json['path'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}
