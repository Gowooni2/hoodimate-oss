import 'package:flutter_tts/flutter_tts.dart';

import 'eleven_tts.dart';

/// Thin wrapper around the platform TTS engine (macOS: native voices,
/// e.g. Korean "Yuna"). Used as a fallback when ElevenLabs is unavailable.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool enabled = true;
  bool _ready = false;

  Future<void> init() async {
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.55);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.15);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> speak(String text) async {
    if (!enabled || !_ready || text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Unified voice: ElevenLabs first (user's own API key), macOS native TTS
/// as fallback.
class SmartTts {
  final TtsService native = TtsService();
  final ElevenTtsService eleven = ElevenTtsService();

  bool enabled = true;
  bool preferEleven = true;

  Future<void> init() async {
    await native.init();
    await eleven.load();
  }

  Future<void> speak(String text) async {
    if (!enabled || text.trim().isEmpty) return;
    if (preferEleven && eleven.config.isConfigured) {
      if (await eleven.speak(text)) return;
    }
    await native.speak(text);
  }

  Future<void> stop() async {
    await eleven.stop();
    await native.stop();
  }
}
