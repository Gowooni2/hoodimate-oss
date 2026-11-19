import 'dart:convert';

import 'package:flutter/services.dart';

import 'profile.dart';

/// A character pack: who the pet is and where its face is drawn.
/// Each pack lives in `assets/characters/<id>/` with `character.json`,
/// `sprites/*.webp` and `anim/*.webp` (see docs/CHARACTER_GUIDE.md).
class Character {
  final String id;
  final String name;

  /// Localized display names ({ko, en, zh}); [name] is the fallback.
  final Map<String, String> names;

  /// False for faces without a mouth (the Hoodies): talking is shown with
  /// the eyes and a little bounce instead of lip shapes.
  final bool hasMouth;
  final Map<String, String> persona;

  /// Character personality ({ko, en, zh}), the brand's canon
  /// (hoodimong-site/HOODIES_CHARACTERS.md). Empty for packs without one.
  final Map<String, String> personality;

  /// Size of `assets/sprites/idle_noeyes.webp`; all points below are in
  /// that image's pixels.
  final Size spriteSize;
  final Offset leftEye, rightEye;
  final double eyeRadius;
  final Offset lookRange; // how far the pupils move (x, y)
  final Color eyeColor;
  final Offset mouthCenter;
  final double mouthWidth;
  final Color skin, mouthLine;

  /// Face colour around the eyes (eyelids for sad/bored eyes are painted
  /// in it).
  final Color face;

  const Character({
    this.id = 'default',
    this.name = 'Hoodie',
    this.names = const {},
    this.hasMouth = true,
    this.persona = const {'en': 'a cute desktop pet'},
    this.personality = const {},
    this.spriteSize = const Size(430, 512),
    this.leftEye = const Offset(165, 116),
    this.rightEye = const Offset(264, 116),
    this.eyeRadius = 10,
    this.lookRange = const Offset(15, 10),
    this.eyeColor = const Color(0xFF111111),
    this.mouthCenter = const Offset(216.5, 137.5),
    this.mouthWidth = 31,
    this.skin = const Color(0xFFEBD8B5),
    this.mouthLine = const Color(0xFF1E1A18),
    this.order = 99,
    this.face = const Color(0xFFA08C80),
  });

  /// Mongsil, the pack every edition ships: shown until [load] has read
  /// the bundle (the constructor defaults only fill gaps in character.json).
  static const fallback = Character(
    id: 'mongsil',
    name: 'Mongsil',
    names: {'ko': '몽실', 'en': 'Mongsil', 'zh': '蒙实'},
    hasMouth: false,
    persona: {'en': 'an ivory hoodie friend with a cloud-shaped hood pulled down low'},
    spriteSize: Size(872, 983),
    leftEye: Offset(362.0, 412.0),
    rightEye: Offset(558.5, 405.2),
    eyeRadius: 47.6,
    lookRange: Offset(16.7, 11.9),
    eyeColor: Color(0xFF0B0B0B),
    order: 0,
    face: Color(0xFF8D7C73),
  );

  static Character current = fallback;

  /// Packs found in the app bundle (ids), filled by [load].
  static List<Character> available = [];

  String get personalityText =>
      personality[Lang.code] ?? personality['en'] ?? '';

  String get personaText =>
      persona[Lang.code] ?? persona['en'] ?? persona.values.first;

  String get displayName => names[Lang.code] ?? names['en'] ?? name;

  String get dir => 'assets/characters/$id';

  /// Asset paths in the bundle (filled by [load]) for sprite fallbacks.
  static Set<String> _assets = {};

  /// Mood sprite, or the plain idle sprite when this pack has none yet.
  String sprite(String mood) {
    final p = '$dir/sprites/$mood.webp';
    return _assets.isEmpty || _assets.contains(p) ? p : '$dir/sprites/idle.webp';
  }
  String get noEyes => sprite('idle_noeyes');

  /// Reads every pack in the bundle, then switches to [id] (or the first
  /// complete one). A pack counts once it has its eyeless idle sprite.
  static Future<void> load([String? id]) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();
      _assets = assets;
      final found = <Character>[];
      for (final a in assets) {
        final m = RegExp(r'^assets/characters/([a-z0-9_]+)/character\.json$').firstMatch(a);
        if (m == null) continue;
        try {
          final c = fromJson(jsonDecode(await rootBundle.loadString(a)) as Map, m.group(1)!);
          if (assets.contains(c.noEyes)) found.add(c);
        } catch (_) {}
      }
      found.sort((a, b) => a.order.compareTo(b.order));
      available = found;
      current = found.where((c) => c.id == id).firstOrNull ?? (found.isEmpty ? fallback : found.first);
    } catch (_) {}
  }

  /// Sort order in the picker (character.json "order").
  final int order;

  static Character fromJson(Map j, [String id = 'default']) {
    Offset pt(Object? v, Offset d) =>
        v is List && v.length == 2 ? Offset((v[0] as num).toDouble(), (v[1] as num).toDouble()) : d;
    Color col(Object? v, Color d) {
      final s = v?.toString().replaceFirst('#', '') ?? '';
      final n = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
      return n == null ? d : Color(n);
    }

    const d = Character();
    final e = (j['eyes'] as Map?) ?? {};
    final m = (j['mouth'] as Map?) ?? {};
    final size = pt(j['spriteSize'], Offset(d.spriteSize.width, d.spriteSize.height));
    return Character(
      id: id,
      name: (j['name'] ?? d.name).toString(),
      names: ((j['names'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')),
      hasMouth: j['mouth'] != null,
      order: (j['order'] as num?)?.toInt() ?? 99,
      persona: ((j['persona'] as Map?) ?? d.persona).map((k, v) => MapEntry('$k', '$v')),
      personality: ((j['personality'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      spriteSize: Size(size.dx, size.dy),
      leftEye: pt(e['left'], d.leftEye),
      rightEye: pt(e['right'], d.rightEye),
      eyeRadius: (e['radius'] as num?)?.toDouble() ?? d.eyeRadius,
      lookRange: pt(e['lookRange'], d.lookRange),
      eyeColor: col(e['color'], d.eyeColor),
      mouthCenter: pt(m['center'], d.mouthCenter),
      mouthWidth: (m['width'] as num?)?.toDouble() ?? d.mouthWidth,
      skin: col(m['skin'], d.skin),
      mouthLine: col(m['line'], d.mouthLine),
      face: col(j['face'], col(m['skin'], d.face)),
    );
  }
}
