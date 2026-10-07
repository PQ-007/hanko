import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

final speechProvider = Provider<Speech>((ref) {
  final speech = Speech();
  ref.onDispose(speech.dispose);
  return speech;
});

/// Japanese pronunciation through the phone's own text-to-speech engine
/// (Android: Google/Samsung TTS; iOS: AVSpeechSynthesizer). Free, offline once
/// the voice is installed, and needs no server — which is what lets the app
/// stand alone. Words that already have a recorded clip in Supabase still play
/// that clip (core/audio.dart); this is the fallback for everything else.
class Speech {
  Speech({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool? _japaneseReady;

  Future<bool> _prepare() async {
    if (_japaneseReady != null) return _japaneseReady!;
    try {
      final available = await _tts.isLanguageAvailable('ja-JP');
      if (available == true) {
        await _tts.setLanguage('ja-JP');
        // A touch slower than default: these are single words being learned,
        // not sentences being read.
        await _tts.setSpeechRate(defaultTargetPlatform == TargetPlatform.iOS ? 0.45 : 0.42);
        await _tts.awaitSpeakCompletion(true);
      }
      _japaneseReady = available == true;
    } catch (e) {
      debugPrint('TTS init failed: $e');
      _japaneseReady = false;
    }
    return _japaneseReady!;
  }

  /// Speaks [text] in Japanese. Returns false if the device has no Japanese
  /// voice, so the caller can tell the user to install one.
  Future<bool> speakJapanese(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    if (!await _prepare()) return false;
    try {
      await _tts.stop();
      await _tts.speak(t);
      return true;
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      return false;
    }
  }

  void dispose() => _tts.stop();
}
