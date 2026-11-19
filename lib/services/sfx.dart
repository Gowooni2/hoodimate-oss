import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Button feel: the pet's own mouth sound (assets/sfx, tools/gen_sfx_voice.py)
/// plus a trackpad haptic pattern, different for each care action.
class Sfx {
  static const _haptic = MethodChannel('hoodimong/haptic');
  static final _players = List.generate(3, (_) => AudioPlayer());
  static int _next = 0;

  /// 0..1, set from Settings (0 = no sounds). Haptics follow [haptics].
  static double volume = 0.6;
  static bool haptics = true;

  // [pattern, delay ms]: 0 generic tap, 1 alignment click, 2 level change.
  static const _patterns = {
    'buzz': [
      [0, 0], [0, 45], [0, 45]
    ], // phone-like buzz
    'feed': [
      [2, 0], [2, 110], [2, 110]
    ], // nom nom nom
    'play': [
      [0, 0], [1, 90], [0, 140]
    ], // bouncy
    'medicine': [
      [1, 0], [1, 200]
    ], // ding-ding
    'sleep': [
      [2, 0], [2, 380]
    ], // slow and soft
    'scold': [
      [0, 0], [0, 70], [0, 70], [0, 70]
    ], // sharp rattle
  };

  static Future<void> play(String name) async {
    if (haptics) {
      try {
        await _haptic.invokeMethod('play', _patterns[name] ?? const [[0, 0]]);
      } catch (_) {}
    }
    if (volume <= 0) return;
    final p = _players[_next];
    _next = (_next + 1) % _players.length;
    try {
      await p.stop();
      await p.setVolume(volume);
      await p.play(AssetSource('sfx/$name.mp3'));
    } catch (_) {}
  }
}
