import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_attachment.dart';

/// Picks files/photos from the device and turns them into [ChatAttachment]s
/// ready to be sent to a vision-capable model or included as text context.
class AttachmentService {
  static const int _maxImageBytes = 8 * 1024 * 1024; // 8 MB
  static const int _maxTextBytes = 200 * 1024; // 200 KB

  final ImagePicker _imagePicker = ImagePicker();

  Future<ChatAttachment?> pickImage({bool fromCamera = false}) async {
    final XFile? file = await _imagePicker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (file == null) return null;
    return _toAttachment(file.name, file.path, _guessMime(file.name));
  }

  Future<ChatAttachment?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final picked = result?.files.firstOrNull;
    if (picked == null || picked.path == null) return null;
    return _toAttachment(picked.name, picked.path!, _guessMime(picked.name));
  }

  String _guessMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
      'txt': 'text/plain', 'md': 'text/markdown', 'csv': 'text/csv',
      'json': 'application/json', 'pdf': 'application/pdf',
      'dart': 'text/x-dart', 'kt': 'text/x-kotlin', 'py': 'text/x-python',
      'js': 'text/javascript', 'yaml': 'text/yaml', 'yml': 'text/yaml',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  Future<ChatAttachment> _toAttachment(
    String name,
    String path,
    String mimeType,
  ) async {
    final file = File(path);
    final size = await file.length();

    String? base64;
    final isImage = mimeType.startsWith('image/');
    final isText = mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        name.endsWith('.dart') ||
        name.endsWith('.kt') ||
        name.endsWith('.py') ||
        name.endsWith('.js') ||
        name.endsWith('.md') ||
        name.endsWith('.yaml') ||
        name.endsWith('.yml') ||
        name.endsWith('.csv');

    if (isImage && size <= _maxImageBytes) {
      base64 = base64Encode(await file.readAsBytes());
    } else if (isText && size <= _maxTextBytes) {
      base64 = base64Encode(await file.readAsBytes());
    }

    return ChatAttachment(
      name: name,
      path: path,
      mimeType: mimeType,
      sizeBytes: size,
      base64Data: base64,
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
