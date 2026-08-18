import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_api_service.dart';
import 'tts_text_sanitizer.dart';

/// Handles speech-to-text and text-to-speech.
///
/// TTS engines:
/// - 'device'  -> flutter_tts (offline, system voices)
/// - 'api'     -> the AI provider's own TTS model via /audio/speech
///
/// Text is always run through [TtsTextSanitizer] before speaking, so
/// markdown (e.g. **bold**) is stripped and emojis are read out by name.
class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TtsApiService _apiTts = TtsApiService();

  bool _isInitialized = false;
  bool _isListening = false;

  // Persisted settings
  String ttsEngine = 'device'; // 'device' | 'api'
  String ttsModel = 'tts-1';
  String ttsVoice = 'alloy';
  String language = 'es-ES';
  double speechRate = 0.5;
  double pitch = 1.0;
  bool partialResults = true;

  bool get isListening => _isListening;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    ttsEngine = prefs.getString('voice_tts_engine') ?? 'device';
    ttsModel = prefs.getString('voice_tts_model') ?? 'tts-1';
    ttsVoice = prefs.getString('voice_tts_voice') ?? 'alloy';
    language = prefs.getString('voice_language') ?? 'es-ES';
    speechRate = prefs.getDouble('voice_rate') ?? 0.5;
    pitch = prefs.getDouble('voice_pitch') ?? 1.0;
    partialResults = prefs.getBool('voice_partial_results') ?? true;

    if (_isInitialized) return;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );

    await _applyDeviceTtsConfig();
  }

  Future<void> _applyDeviceTtsConfig() async {
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(speechRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(pitch);
    } catch (_) {}
  }

  Future<void> reloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ttsEngine = prefs.getString('voice_tts_engine') ?? ttsEngine;
    ttsModel = prefs.getString('voice_tts_model') ?? ttsModel;
    ttsVoice = prefs.getString('voice_tts_voice') ?? ttsVoice;
    language = prefs.getString('voice_language') ?? language;
    speechRate = prefs.getDouble('voice_rate') ?? speechRate;
    pitch = prefs.getDouble('voice_pitch') ?? pitch;
    partialResults = prefs.getBool('voice_partial_results') ?? partialResults;
    await _applyDeviceTtsConfig();
  }

  /// Start listening for speech.
  /// [onResult] fires with the final transcription.
  /// [onPartial] fires with in-progress words (when partialResults is on).
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
    Function(String)? onPartial,
  }) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return;

    _isListening = true;

    await _speech.listen(
      localeId: language,
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
          onDone();
        } else if (partialResults && onPartial != null) {
          onPartial(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: partialResults,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }

  /// Speak text aloud. Markdown is stripped and emojis are named.
  /// Uses the provider's TTS API when the 'api' engine is selected,
  /// with automatic fallback to the device engine if it fails.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final clean = TtsTextSanitizer.sanitize(text);
    if (clean.isEmpty) return;

    if (ttsEngine == 'api') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final baseUrl = prefs.getString('api_base_url') ?? '';
        final apiKey = prefs.getString('api_key') ?? '';
        if (baseUrl.isEmpty || apiKey.isEmpty) {
          throw Exception('No API configured for TTS');
        }
        await _apiTts.speak(
          text: clean,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: ttsModel,
          voice: ttsVoice,
        );
        return;
      } catch (_) {
        // Fall through to device TTS.
      }
    }

    try {
      await _tts.speak(clean);
    } catch (_) {}
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    await _apiTts.stop();
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
    _apiTts.dispose();
  }
}
