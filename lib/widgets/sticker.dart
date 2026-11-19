import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/emoticons.dart';
import '../models/emotion_fx.dart';
import 'clip_player.dart';

/// An animated KakaoTalk-style emoticon: the current character playing the
/// emoticon's clip on a loop (or its still sprite until the clip exists).
class StickerView extends StatefulWidget {
  final Emoticon emoticon;
  final double size;

  /// Draw the emoticon's lettering on top (big stickers only by default).
  final bool? lettering;
  const StickerView(this.emoticon, {super.key, this.size = 110, this.lettering});

  @override
  State<StickerView> createState() => _StickerViewState();
}

class _StickerViewState extends State<StickerView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  List<String>? _frames;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(StickerView old) {
    super.didUpdateWidget(old);
    if (old.emoticon.id != widget.emoticon.id) _setup();
  }

  void _setup() {
    final key = widget.emoticon.clip;
    final resolved = key.startsWith('act_') ? PetClips.resolveAction(key.substring(4)) : key;
    _frames = resolved == null
        ? null
        : PetClips.framesForKey(key.startsWith('act_') ? 'act_$resolved' : resolved);
    final f = _frames;
    if (f == null || f.isEmpty) {
      _c.stop();
      return;
    }
    _c.duration = Duration(milliseconds: (f.length * 1000 / 16).round());
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final fx = (widget.lettering ?? s >= 64) ? EmotionFx.byEmoticon[widget.emoticon.id] : null;
    final art = _art(s);
    if (fx == null) return art;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          art,
          Positioned(
            left: 0,
            right: 0,
            bottom: s * 0.02,
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  // pop in time with the clip for excited feelings
                  final t = fx.bouncy && _c.isAnimating ? math.sin(_c.value * math.pi * 4).abs() : 0.0;
                  return Transform.scale(scale: 1 + 0.08 * t, child: child);
                },
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FxText(fx, size: (s * 0.17).clamp(12, 22)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _art(double s) {
    final f = _frames;
    if (f == null || f.isEmpty) {
      return Image.asset(Character.current.sprite(widget.emoticon.still.name),
          width: s, height: s, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final i = (_c.value * f.length).floor().clamp(0, f.length - 1);
          return Image.asset(f[i], width: s, height: s, fit: BoxFit.contain, gaplessPlayback: true);
        },
      ),
    );
  }
}
