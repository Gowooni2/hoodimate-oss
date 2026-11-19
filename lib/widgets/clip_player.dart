import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/character.dart';
import '../models/pet_state.dart';

/// Frame-sequence clips rendered by the ComfyUI pipeline
/// (`tools/comfy_clip.py`): transparent PNGs at
/// `assets/anim/<mood>_0001.png ...`. Loops at [fps].
/// Falls back to the static sprite when a mood has no clip yet.
class PetClips {
  static final Map<String, List<String>> _frames = {};
  static final Map<String, double> _scale = {};
  static String? _loadedFor;

  /// `assets/characters/<pack>/anim/<key>_<frame>.webp` (or .png); keys may
  /// contain `_` and digits (act_pet, act_jump2). Frames have 4 digits.
  static final fileRe = RegExp(
      r'^assets/characters/([a-z0-9_]+)/anim/([a-z0-9_]+?)_(\d{4})\.(?:webp|png)$');

  /// Loads the clips of the current character pack (again after a switch).
  static Future<void> load() async {
    final id = Character.current.id;
    if (_loadedFor == id) return;
    _loadedFor = id;
    _frames.clear();
    _scale.clear();
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final path in manifest.listAssets()) {
        final m = fileRe.firstMatch(path);
        if (m != null && m.group(1) == id) {
          _frames.putIfAbsent(m.group(2)!, () => []).add(path);
        }
      }
      for (final list in _frames.values) {
        list.sort();
      }
      for (final mood in _frames.keys) {
        try {
          final j = jsonDecode(await rootBundle
              .loadString('${Character.current.dir}/anim/$mood.json'));
          _scale[mood] = (j['scale'] as num).toDouble();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static String keyFor(PetMood mood) => mood.name;

  static List<String>? framesForKey(String key) {
    final f = _frames[key];
    return (f == null || f.isEmpty) ? null : f;
  }

  static List<String>? framesFor(PetMood mood) => framesForKey(keyFor(mood));

  /// One-shot reaction clips are named `act_<name>` (see tools/comfy_clip.py).
  static bool hasAction(String name) => framesForKey('act_$name') != null;

  static bool has(PetMood mood) => framesFor(mood) != null;

  /// The clip to play for an action: a newer re-render (`act_<name>2`,
  /// e.g. started from a pose with props) wins over the first version.
  /// Null when neither is installed.
  static String? resolveAction(String name) {
    if (hasAction('${name}2')) return '${name}2';
    if (hasAction(name)) return name;
    final alt = _fallback[name];
    return alt == null ? null : resolveAction(alt);
  }

  /// Stand-ins until a clip is rendered (comic -> reading, ...).
  static const _fallback = {
    'comic': 'reading',
    'whine': 'sigh',
    'scolded': 'gloomy',
    'sunny': 'jump',
  };

  /// How much bigger a clip frame is than the static sprite (the frame
  /// keeps room around the character so moving arms are never cut).
  static double scaleFor(PetMood mood) => scaleForKey(keyFor(mood));
  static double scaleForKey(String key) => _scale[key] ?? 1.0;
}

class ClipPlayer extends StatefulWidget {
  final PetMood mood;
  final double size;
  final int fps;

  /// When set, plays the one-shot clip `act_<action>` once instead of the
  /// mood loop and then calls [onDone].
  final String? action;
  final VoidCallback? onDone;

  /// A state clip (`act_think`, `act_listen`, ...) looped instead of the
  /// mood clip while the pet is busy. Ignored when not installed.
  final String? loop;
  const ClipPlayer(
      {super.key,
      required this.mood,
      this.size = 200,
      this.fps = 16,
      this.action,
      this.onDone,
      this.loop});

  @override
  State<ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends State<ClipPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  List<String>? _frames;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    _setup();
  }

  @override
  void didUpdateWidget(ClipPlayer old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood ||
        old.action != widget.action ||
        old.loop != widget.loop) {
      _setup();
    }
  }

  String get _key {
    if (widget.action != null) return 'act_${widget.action}';
    final l = widget.loop == null ? null : PetClips.resolveAction(widget.loop!);
    return l != null ? 'act_$l' : PetClips.keyFor(widget.mood);
  }

  void _setup() {
    _frames = PetClips.framesForKey(_key);
    final f = _frames;
    if (f == null) {
      _ctrl.stop();
      if (widget.action != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onDone?.call());
      }
      return;
    }
    _ctrl.duration =
        Duration(milliseconds: (f.length * 1000 / widget.fps).round());
    if (widget.action != null) {
      _ctrl.forward(from: 0).whenComplete(() {
        if (mounted) widget.onDone?.call();
      });
    } else {
      _ctrl.repeat();
    }
    // Decode every frame up front so the loop never flickers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final p in f) {
        precacheImage(AssetImage(p), context);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _frames;
    if (f == null) {
      return Image.asset(widget.mood.sprite,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          gaplessPlayback: true);
    }
    final big = widget.size * PetClips.scaleForKey(_key);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: OverflowBox(
        maxWidth: big,
        maxHeight: big,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final i = (_ctrl.value * f.length).floor().clamp(0, f.length - 1);
            return Image.asset(f[i],
                width: big,
                height: big,
                fit: BoxFit.contain,
                gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}
