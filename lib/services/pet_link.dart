import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

/// Where a pet is and what it's doing (`presence/<app>.json`).
class PetPresence {
  final String app, character, state, emotion;

  /// Pet's feet in screen points, origin at the main screen's bottom-left.
  final double x, y, height;

  /// Unix seconds.
  final double ts;
  const PetPresence({
    required this.app,
    required this.character,
    required this.x,
    required this.y,
    required this.height,
    required this.state,
    required this.emotion,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'app': app, 'character': character, 'x': x, 'y': y, 'height': height,
        'state': state, 'emotion': emotion, 'ts': ts,
      };

  static PetPresence? fromJson(Object? j) {
    if (j is! Map) return null;
    double n(Object? v) => (v is num) ? v.toDouble() : 0;
    return PetPresence(
      app: '${j['app'] ?? ''}',
      character: '${j['character'] ?? ''}',
      x: n(j['x']),
      y: n(j['y']),
      height: n(j['height']),
      state: '${j['state'] ?? 'idle'}',
      emotion: '${j['emotion'] ?? ''}',
      ts: n(j['ts']),
    );
  }
}

/// One short message between the pets (`signals/<app>.json`, latest only).
class PetSignal {
  final String app, type, to;
  final int seq;
  final Map<String, dynamic> data;
  final double ts;
  const PetSignal(this.app, this.seq, this.type, this.to, this.data, this.ts);

  Map<String, dynamic> toJson() =>
      {'app': app, 'seq': seq, 'type': type, 'to': to, 'data': data, 'ts': ts};

  static PetSignal? fromJson(Object? j) {
    if (j is! Map) return null;
    final seq = j['seq'], ts = j['ts'];
    return PetSignal('${j['app'] ?? ''}', seq is num && seq.isFinite ? seq.toInt() : 0, '${j['type'] ?? ''}',
        '${j['to'] ?? '*'}', (j['data'] is Map) ? Map<String, dynamic>.from(j['data'] as Map) : {},
        ts is num ? ts.toDouble() : 0);
  }
}

/// Hoodimate's side of the Hoodies interaction protocol v1 (Hoodibot's
/// docs/INTERACTION_PROTOCOL.md): both apps share an App Group folder,
/// each overwrites only its own `presence/` and `signals/` file, and reads
/// the other's. Nothing leaves this Mac.
class PetLink {
  static const me = 'hoodimate', friend = 'hoodibot';
  static const _channel = MethodChannel('hoodimong/group');

  /// The shared folder; null when the App Group isn't available.
  Directory? dir;
  final double Function() _now;
  PetLink({double Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch / 1000);

  int _seq = 0;
  int _seenSeq = -1;
  double _lastHello = -1e9, _lastAlarm = -1e9, _lastVisit = -1e9;

  bool get ready => dir != null;

  /// Finds the shared folder. [testDir] replaces the App Group in tests.
  Future<void> init({Directory? testDir}) async {
    try {
      final path = testDir?.path ?? await _channel.invokeMethod<String>('dir');
      if (path == null) return;
      final d = Directory(path);
      for (final sub in ['presence', 'signals']) {
        Directory('${d.path}/$sub').createSync(recursive: true);
      }
      dir = d;
      _seq = PetSignal.fromJson(_read('signals/$me.json'))?.seq ?? 0;
      // Signals already waiting from before we started are old news.
      _seenSeq = PetSignal.fromJson(_read('signals/$friend.json'))?.seq ?? -1;
    } catch (_) {
      dir = null;
    }
  }

  Object? _read(String rel) {
    try {
      final f = File('${dir!.path}/$rel');
      return f.existsSync() ? jsonDecode(f.readAsStringSync()) : null;
    } catch (_) {
      return null;
    }
  }

  void _write(String rel, Map<String, dynamic> j) {
    final f = File('${dir!.path}/$rel');
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(j));
    tmp.renameSync(f.path); // atomic: the other app never reads half a file
  }

  /// Publish where our pet is (call every 1-2 s).
  void publish({
    required String character,
    required double x,
    required double y,
    required double height,
    required String state,
    required String emotion,
  }) {
    if (dir == null) return;
    try {
      _write('presence/$me.json', PetPresence(
        app: me, character: character, x: x, y: y, height: height,
        state: state, emotion: emotion, ts: _now(),
      ).toJson());
    } catch (_) {}
  }

  /// Hoodibot's presence, or null when it isn't running (stale > 10 s).
  PetPresence? friendPresence() {
    if (dir == null) return null;
    final p = PetPresence.fromJson(_read('presence/$friend.json'));
    // Stale (> 10 s) or dated in the future (wrong clock / garbage): not alive.
    if (p == null) return null;
    final age = _now() - p.ts;
    if (age > 10 || age < -5) return null;
    return p;
  }

  void send(String type, {String to = friend, Map<String, dynamic> data = const {}}) {
    if (dir == null) return;
    try {
      _write('signals/$me.json', PetSignal(me, ++_seq, type, to, data, _now()).toJson());
    } catch (_) {}
  }

  /// A new signal for us (newer seq, under 30 s old), at most once.
  PetSignal? takeSignal() {
    if (dir == null) return null;
    final s = PetSignal.fromJson(_read('signals/$friend.json'));
    // Any seq we have not seen is new: Hoodibot may have been reinstalled
    // (seq restarts) and a huge junk seq must not block later ones.
    if (s == null || s.seq == _seenSeq) return null;
    _seenSeq = s.seq;
    final age = _now() - s.ts;
    if (age > 30 || age < -5 || (s.to != me && s.to != '*')) return null;
    return s;
  }

  /// Meeting rule: feet closer than 1.8x the average height, the other
  /// pet out and about, and no hello to it in the last 10 minutes.
  bool shouldGreet(PetPresence mine, PetPresence other) {
    // home: visit instead; alarm: ring along instead (protocol 4-1)
    if (const {'home', 'hide', 'sleep', 'alarm'}.contains(other.state)) return false;
    if (const {'sleep', 'alarm'}.contains(mine.state)) return false;
    if (!_close(mine, other)) return false;
    if (_now() - _lastHello < 600) return false;
    _lastHello = _now();
    return true;
  }

  /// Walking past Hoodibot's house while it's inside: drop by (10 min).
  bool shouldVisit(PetPresence mine, PetPresence other) {
    if (other.state != 'home' || const {'sleep', 'alarm'}.contains(mine.state)) return false;
    if (!_close(mine, other) || _now() - _lastVisit < 600) return false;
    _lastVisit = _now();
    return true;
  }

  bool _close(PetPresence a, PetPresence b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)) < (a.height + b.height) / 2 * 1.8;

  /// Ring along with the other pet's alarm, once a minute at most.
  bool shouldJoinAlarm(PetPresence other) {
    if (other.state != 'alarm' || _now() - _lastAlarm < 60) return false;
    _lastAlarm = _now();
    return true;
  }

  /// A hello arrived: count it as our greeting too (no ping-pong).
  void noteHello() => _lastHello = _now();
}
