import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

/// Speaks text using the configured AI provider's own TTS endpoint
/// (OpenAI-compatible POST /audio/speech). Falls back is handled by the
/// caller (VoiceService) — this class throws on failure.
class TtsApiService {
  final AudioPlayer _player = AudioPlayer();
  bool _disposed = false;

  bool get isPlaying => _player.state == PlayerState.playing;

  Future<void> speak({
    required String text,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String voice,
  }) async {
    if (text.trim().isEmpty) return;

    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.endsWith('/audio/speech')) {
      url = '$url/audio/speech';
    }

    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'voice': voice,
            'input': text,
            'response_format': 'mp3',
          }),
        )
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw Exception(
        'TTS API error (${response.statusCode}): '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(response.bodyBytes);

    await _player.stop();
    await _player.play(DeviceFileSource(file.path));
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _player.dispose();
  }
}
