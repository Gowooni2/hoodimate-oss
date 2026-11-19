import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/pet_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  var now = 1000.0;
  late PetLink link;

  void raw(String rel, String text) => File('${dir.path}/$rel').writeAsStringSync(text);
  void put(String rel, Object j) => raw(rel, jsonEncode(j));
  Map<String, dynamic> bot({Object? x = 100, Object? y = 50, Object? state = 'walk', Object? ts, Object? height = 100}) =>
      {'app': 'hoodibot', 'character': 'mongsil', 'x': x, 'y': y, 'height': height, 'state': state, 'emotion': 'happy', 'ts': ts ?? now};
  Map<String, dynamic> sig({Object? seq = 1, Object? ts, String to = 'hoodimate', String type = 'hoodimong/hello', Object? data = const {}}) =>
      {'app': 'hoodibot', 'seq': seq, 'type': type, 'to': to, 'data': data, 'ts': ts ?? now};

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('pet_link_audit');
    now = 1000;
    link = PetLink(now: () => now);
    await link.init(testDir: dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('presence', () {
    test('missing file / empty file / truncated JSON / wrong type -> no friend, no throw', () {
      expect(link.friendPresence(), isNull);
      for (final t in ['', '{', '{"app":"hoodibot","x":', '[]', 'null', '"str"', '123', '{"ts": 1000', '\u0000\u0000']) {
        raw('presence/hoodibot.json', t);
        expect(link.friendPresence, returnsNormally, reason: t);
        expect(link.friendPresence(), isNull, reason: t);
      }
    });

    test('missing fields default sanely; ts missing means stale', () {
      put('presence/hoodibot.json', {'app': 'hoodibot'});
      expect(link.friendPresence(), isNull); // ts 0 -> stale
      put('presence/hoodibot.json', {'ts': now});
      final p = link.friendPresence()!;
      expect(p.state, 'idle');
      expect([p.x, p.y, p.height], [0, 0, 0]);
    });

    test('wrong-typed numbers are treated as 0, strings are not parsed', () {
      put('presence/hoodibot.json', bot(x: '12', y: null, height: [1], ts: now));
      final p = link.friendPresence()!;
      expect([p.x, p.y, p.height], [0, 0, 0]);
    });

    test('huge / tiny numbers do not break the distance maths', () {
      put('presence/hoodibot.json', bot(x: 1e308, y: -1e308, ts: now));
      final o = link.friendPresence()!;
      final me = PetPresence(app: 'hoodimate', character: 'm', x: 0, y: 0, height: 200, state: 'idle', emotion: '', ts: now);
      expect(link.shouldGreet(me, o), isFalse);
      put('presence/hoodibot.json', bot(x: 1e-300, y: 0, ts: now));
      expect(link.shouldGreet(me, link.friendPresence()!), isTrue);
    });

    test('negative height or zero heights never greet from across the screen', () {
      final me = PetPresence(app: 'hoodimate', character: 'm', x: 0, y: 0, height: -500, state: 'idle', emotion: '', ts: now);
      final o = PetPresence.fromJson(bot(x: 0, y: 0, height: -500))!;
      expect(link.shouldGreet(me, o), isFalse);
    });

    test('stale boundary: exactly 10 s old is alive, 10.001 s is gone', () {
      put('presence/hoodibot.json', bot(ts: now - 10));
      expect(link.friendPresence(), isNotNull);
      put('presence/hoodibot.json', bot(ts: now - 10.001));
      expect(link.friendPresence(), isNull);
    });

    test('a ts in the far future (bad clock / garbage) must not keep a dead friend alive forever', () {
      put('presence/hoodibot.json', bot(ts: now + 1e9));
      expect(link.friendPresence(), isNull);
      put('presence/hoodibot.json', bot(ts: 1e300));
      expect(link.friendPresence(), isNull);
    });

    test('a friend that is a few seconds ahead (clock skew within 5 s) is still alive', () {
      put('presence/hoodibot.json', bot(ts: now + 3));
      expect(link.friendPresence(), isNotNull);
    });

    test('file vanishing between exists() and read -> null, not an exception', () async {
      // Directory replaced by a plain file: every read fails.
      Directory('${dir.path}/presence').deleteSync(recursive: true);
      File('${dir.path}/presence').writeAsStringSync('x');
      expect(link.friendPresence, returnsNormally);
      expect(link.friendPresence(), isNull);
    });

    test('publish: unwritable folder is swallowed; no .tmp left behind on success; ts is now', () {
      link.publish(character: 'c', x: 1e308, y: -1, height: 0, state: 's', emotion: 'e');
      expect(File('${dir.path}/presence/hoodimate.json.tmp').existsSync(), isFalse);
      Directory('${dir.path}/presence').deleteSync(recursive: true);
      expect(() => link.publish(character: 'c', x: 0, y: 0, height: 0, state: 's', emotion: 'e'), returnsNormally);
    });

    test('publish with NaN / infinity coordinates must still produce readable JSON', () {
      link.publish(character: 'c', x: double.nan, y: double.infinity, height: 1, state: 's', emotion: 'e');
      final f = File('${dir.path}/presence/hoodimate.json');
      if (f.existsSync()) {
        expect(() => jsonDecode(f.readAsStringSync()), returnsNormally);
      }
    });
  });

  group('signals', () {
    test('malformed signal file -> null', () {
      for (final t in ['', '{', '[]', 'null', '{"seq":"x"}']) {
        raw('signals/hoodibot.json', t);
        expect(link.takeSignal, returnsNormally, reason: t);
      }
    });

    test('string seq / ts (other app wrote wrong types) is ignored without throwing', () {
      put('signals/hoodibot.json', sig(seq: '5'));
      expect(link.takeSignal, returnsNormally);
      put('signals/hoodibot.json', sig(seq: 5, ts: '1000'));
      expect(link.takeSignal, returnsNormally);
    });

    test('init survives a signal file with a string seq: the link stays ready', () async {
      put('signals/hoodibot.json', sig(seq: '3'));
      put('signals/hoodimate.json', {'app': 'hoodimate', 'seq': 'x', 'type': 't', 'to': '*', 'data': {}, 'ts': 1});
      final l = PetLink(now: () => now);
      await l.init(testDir: dir);
      expect(l.ready, isTrue, reason: 'one malformed friend file disabled the whole link for this session');
    });

    test('data that is not a map becomes {}', () {
      put('signals/hoodibot.json', sig(seq: 2, data: 'text'));
      expect(link.takeSignal()?.data, isEmpty);
    });

    test('seq goes backwards after the friend reinstalls: new signals are still delivered', () {
      put('signals/hoodibot.json', sig(seq: 50));
      expect(link.takeSignal(), isNotNull);
      put('signals/hoodibot.json', sig(seq: 1, ts: now + 5));
      now += 5;
      expect(link.takeSignal(), isNotNull, reason: 'seq 1 < 50 is dropped until this app restarts');
    });

    test('absurd seq (1e30 / negative) does not poison later delivery', () {
      put('signals/hoodibot.json', sig(seq: 1e30));
      link.takeSignal();
      put('signals/hoodibot.json', sig(seq: 7, ts: now));
      expect(link.takeSignal(), isNotNull, reason: 'seq 1e30 became the high-water mark');
    });

    test('stale (>30 s) is dropped but still consumed; exactly 30 s is delivered', () {
      put('signals/hoodibot.json', sig(seq: 1, ts: now - 30));
      expect(link.takeSignal(), isNotNull);
      put('signals/hoodibot.json', sig(seq: 2, ts: now - 30.5));
      expect(link.takeSignal(), isNull);
      expect(link.takeSignal(), isNull);
    });

    test('a signal dated in the future is not delivered forever or out of order', () {
      put('signals/hoodibot.json', sig(seq: 1, ts: now + 1e6));
      expect(link.takeSignal(), isNull, reason: 'future-dated signal would trigger actions an hour from now');
    });

    test('same signal is delivered once, even if the file is rewritten identically', () {
      put('signals/hoodibot.json', sig(seq: 3));
      expect(link.takeSignal(), isNotNull);
      put('signals/hoodibot.json', sig(seq: 3));
      expect(link.takeSignal(), isNull);
    });

    test('send: seq increments, survives restart, huge data / unencodable data does not throw', () async {
      link.send('a');
      link.send('b', data: {'t': 'x' * 100000});
      link.send('c', data: {'bad': Object()});
      final j = jsonDecode(File('${dir.path}/signals/hoodimate.json').readAsStringSync()) as Map;
      expect(j['seq'], anyOf(2, 3));
      final again = PetLink(now: () => now);
      await again.init(testDir: dir);
      again.send('d');
      expect(jsonDecode(File('${dir.path}/signals/hoodimate.json').readAsStringSync())['seq'], (j['seq'] as int) + 1);
    });

    test('send to a vanished folder is swallowed', () {
      Directory('${dir.path}/signals').deleteSync(recursive: true);
      expect(() => link.send('x'), returnsNormally);
    });
  });

  group('rules', () {
    PetPresence me({String state = 'idle', double x = 0, double y = 0, double h = 100}) =>
        PetPresence(app: 'hoodimate', character: 'm', x: x, y: y, height: h, state: state, emotion: '', ts: now);
    PetPresence other({String state = 'walk', double x = 50, double y = 0, double h = 100}) =>
        PetPresence(app: 'hoodibot', character: 'm', x: x, y: y, height: h, state: state, emotion: '', ts: now);

    test('distance threshold is exactly 1.8x average height', () {
      expect(link.shouldGreet(me(), other(x: 179.9)), isTrue);
      now += 601;
      expect(link.shouldGreet(me(), other(x: 180)), isFalse);
    });

    test('a failed (too far) check does not burn the cooldown', () {
      expect(link.shouldGreet(me(), other(x: 5000)), isFalse);
      expect(link.shouldGreet(me(), other(x: 10)), isTrue);
    });

    test('cooldown boundary: 599.9 s still blocked, 600 s allowed', () {
      expect(link.shouldGreet(me(), other()), isTrue);
      now += 599.9;
      expect(link.shouldGreet(me(), other()), isFalse);
      now += 0.1;
      expect(link.shouldGreet(me(), other()), isTrue);
    });

    test('states that must never greet / visit / join', () {
      for (final s in ['home', 'hide', 'sleep', 'alarm']) {
        expect(link.shouldGreet(me(), other(state: s)), isFalse, reason: s);
      }
      expect(link.shouldGreet(me(state: 'alarm'), other()), isFalse);
      expect(link.shouldVisit(me(state: 'sleep'), other(state: 'home')), isFalse);
      expect(link.shouldVisit(me(), other(state: 'walk')), isFalse);
      expect(link.shouldJoinAlarm(other(state: 'walk')), isFalse);
    });

    test('noteHello suppresses our own greeting for 10 minutes (no ping-pong)', () {
      link.noteHello();
      expect(link.shouldGreet(me(), other()), isFalse);
      now += 601;
      expect(link.shouldGreet(me(), other()), isTrue);
    });

    test('operations before init (no folder) are inert', () {
      final l = PetLink(now: () => now);
      expect(l.ready, isFalse);
      expect(l.friendPresence(), isNull);
      expect(l.takeSignal(), isNull);
      expect(() => l.send('x'), returnsNormally);
      expect(() => l.publish(character: 'c', x: 0, y: 0, height: 0, state: 's', emotion: 'e'), returnsNormally);
    });
  });
}
