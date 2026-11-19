import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import 'eleven_tts.dart';

enum SpeechMode { off, mac, eleven }

/// Reads the AI's replies aloud and moves the mouth with it.
///  - mac: the Mac's built-in voice (free, offline); mouth shapes follow the
///    letters at speaking speed.
///  - eleven: ElevenLabs with the owner's own key and voice; mouth shapes
///    follow the per-character timestamps ElevenLabs returns.
/// Writes Rhubarb-style shapes (A..H, X) into [mouth], the same notifier the
/// recorded voice lines use, so the face code draws both.
class SpeechOut {
  final ValueNotifier<String?> mouth;
  SpeechOut(this.mouth);

  SpeechMode mode = SpeechMode.off;
  final ElevenTtsService eleven = ElevenTtsService();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  Timer? _timer;
  int _token = 0;

  Future<void> init() async {
    await eleven.load();
    try {
      await _tts.awaitSpeakCompletion(false);
      _tts.setCompletionHandler(_rest);
      _tts.setCancelHandler(_rest);
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    final say = speakable(text);
    if (mode == SpeechMode.off || say.isEmpty) return;
    await stop();
    final token = ++_token;
    if (mode == SpeechMode.eleven && eleven.config.isConfigured) {
      if (await _eleven(say, token)) return;
    }
    await _mac(say, token);
  }

  Future<void> stop() async {
    _token++;
    _rest();
    try {
      await _tts.stop();
      await _player.stop();
    } catch (_) {}
  }

  void _rest() {
    _timer?.cancel();
    mouth.value = null;
  }

  // ---------- Mac voice ----------

  Future<void> _mac(String text, int token) async {
    try {
      await _tts.setLanguage(switch (Lang.code) { 'ko' => 'ko-KR', 'zh' => 'zh-CN', _ => 'en-US' });
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.15);
      await _tts.speak(text);
    } catch (_) {
      return;
    }
    // No timestamps from the system voice: step through the letters at an
    // average speaking pace (syllables for Korean/Chinese).
    final perChar = Lang.code == 'en' ? 0.065 : 0.17;
    _run(token, cuesFromText(text, perChar));
  }

  // ---------- ElevenLabs with timestamps ----------

  Future<bool> _eleven(String text, int token) async {
    final c = eleven.config;
    try {
      final res = await http
          .post(Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/${c.voiceId}/with-timestamps'),
              headers: {'xi-api-key': c.apiKey, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'text': text,
                'model_id': c.modelId,
                'voice_settings': {'stability': 0.45, 'similarity_boost': 0.75},
              }))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 || token != _token) return false;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final audio = base64Decode(j['audio_base64'] as String);
      final al = (j['alignment'] ?? j['normalized_alignment']) as Map?;
      await _player.play(BytesSource(audio));
      if (al != null) {
        final chars = (al['characters'] as List).cast<String>();
        final starts = (al['character_start_times_seconds'] as List).map((e) => (e as num).toDouble()).toList();
        _run(token, cuesFromAlignment(chars, starts));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- mouth timeline ----------

  void _run(int token, List<(double, String)> cues) {
    _timer?.cancel();
    if (cues.isEmpty) return;
    final clock = Stopwatch()..start();
    var i = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (token != _token) return t.cancel();
      final now = clock.elapsedMilliseconds / 1000;
      while (i + 1 < cues.length && cues[i + 1].$1 <= now) {
        i++;
      }
      if (i == cues.length - 1 && now > cues[i].$1 + 0.25) {
        _rest();
        return;
      }
      mouth.value = cues[i].$2;
    });
  }

  /// Text to read: no emoji or symbols that voices spell out.
  static String speakable(String s) => s
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'[*_#`>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<(double, String)> cuesFromText(String text, double perChar) {
    final out = <(double, String)>[];
    var t = 0.0;
    for (final ch in text.runes.map(String.fromCharCode)) {
      out.add((t, shapeFor(ch)));
      t += ch == ' ' ? perChar * 0.6 : perChar;
    }
    out.add((t, 'X'));
    return out;
  }

  static List<(double, String)> cuesFromAlignment(List<String> chars, List<double> starts) {
    final out = <(double, String)>[];
    for (var i = 0; i < chars.length && i < starts.length; i++) {
      final s = shapeFor(chars[i]);
      if (out.isEmpty || out.last.$2 != s) out.add((starts[i], s));
    }
    out.add(((starts.isEmpty ? 0 : starts.last) + 0.12, 'X'));
    return out;
  }

  /// One character -> mouth shape (Rhubarb names): A closed (m/b/p),
  /// B slightly open, C open (e/i), D wide (a), E rounded (o), F pucker (u/w),
  /// G teeth on lip (f/v), H tongue (l), X rest.
  static String shapeFor(String ch) {
    if (ch.trim().isEmpty || RegExp(r'[.,!?~…·:;、。，！？]').hasMatch(ch)) return 'X';
    final code = ch.runes.first;
    if (code >= 0xAC00 && code <= 0xD7A3) {
      final initial = (code - 0xAC00) ~/ 588;
      if (initial == 6 || initial == 7 || initial == 8 || initial == 17) {
        // ㅁ ㅂ ㅃ ㅍ start with closed lips; the vowel follows quickly
        return 'A';
      }
      const v = 'DCDCCCCCEDCEEFFFFFBBB'; // ㅏ..ㅣ
      return v[((code - 0xAC00) % 588) ~/ 28];
    }
    if (code >= 0x4E00 && code <= 0x9FFF) return const ['C', 'D', 'B', 'E'][code % 4];
    final c = ch.toLowerCase();
    if ('mbp'.contains(c)) return 'A';
    if ('fv'.contains(c)) return 'G';
    if (c == 'l') return 'H';
    if (c == 'a') return 'D';
    if ('ei'.contains(c)) return 'C';
    if (c == 'o') return 'E';
    if ('uwq'.contains(c)) return 'F';
    return 'B';
  }
}
