import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/pet_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  var now = 1000.0;
  late PetLink link;

  void put(String rel, Map<String, dynamic> j) =>
      File('${dir.path}/$rel').writeAsStringSync(jsonEncode(j));
  Map<String, dynamic> bot({double x = 100, double y = 50, String state = 'walk', double? ts}) =>
      {'app': 'hoodibot', 'character': 'mongsil', 'x': x, 'y': y, 'height': 100, 'state': state, 'emotion': 'happy', 'ts': ts ?? now};
  PetPresence me({double x = 160, double y = 50, String state = 'idle'}) => PetPresence(
      app: 'hoodimate', character: 'mongsil', x: x, y: y, height: 200, state: state, emotion: '', ts: now);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('pet_link');
    now = 1000;
    link = PetLink(now: () => now);
    await link.init(testDir: dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('publishes presence in the protocol format', () {
    link.publish(character: 'sobok', x: 10, y: 20, height: 200, state: 'idle', emotion: 'happy');
    final j = jsonDecode(File('${dir.path}/presence/hoodimate.json').readAsStringSync());
    expect(j, {'app': 'hoodimate', 'character': 'sobok', 'x': 10.0, 'y': 20.0, 'height': 200.0,
        'state': 'idle', 'emotion': 'happy', 'ts': 1000.0});
    expect(File('${dir.path}/presence/hoodimate.json.tmp').existsSync(), isFalse);
  });

  test('friend is gone once its presence is over 10 s old', () {
    put('presence/hoodibot.json', bot(ts: now - 5));
    expect(link.friendPresence()?.app, 'hoodibot');
    put('presence/hoodibot.json', bot(ts: now - 11));
    expect(link.friendPresence(), isNull);
  });

  test('meeting: close enough, other pet out, once per 10 minutes', () {
    expect(link.shouldGreet(me(x: 1000), PetPresence.fromJson(bot())!), isFalse); // too far
    expect(link.shouldGreet(me(), PetPresence.fromJson(bot(state: 'home'))!), isFalse);
    expect(link.shouldGreet(me(state: 'sleep'), PetPresence.fromJson(bot())!), isFalse);
    expect(link.shouldGreet(me(), PetPresence.fromJson(bot())!), isTrue); // 60 < 150*1.8
    expect(link.shouldGreet(me(), PetPresence.fromJson(bot())!), isFalse); // cooldown
    now += 601;
    expect(link.shouldGreet(me(), PetPresence.fromJson(bot())!), isTrue);
  });

  test('signals: new seq only, under 30 s, addressed to us or everyone', () {
    put('signals/hoodibot.json', {'app': 'hoodibot', 'seq': 1, 'type': 'hoodimong/hello', 'to': 'hoodimate', 'data': {}, 'ts': now});
    expect(link.takeSignal()?.type, 'hoodimong/hello');
    expect(link.takeSignal(), isNull); // same seq
    put('signals/hoodibot.json', {'app': 'hoodibot', 'seq': 2, 'type': 'hoodimong/alarm', 'to': '*', 'data': {'text': 'Meeting'}, 'ts': now - 40});
    expect(link.takeSignal(), isNull); // stale
    put('signals/hoodibot.json', {'app': 'hoodibot', 'seq': 3, 'type': 'hoodimong/play', 'to': 'someone_else', 'data': {}, 'ts': now});
    expect(link.takeSignal(), isNull);
    put('signals/hoodibot.json', {'app': 'hoodibot', 'seq': 4, 'type': 'hoodimong/alarm', 'to': '*', 'data': {'text': 'Meeting'}, 'ts': now});
    expect(link.takeSignal()?.data['text'], 'Meeting');
  });

  test('sending bumps seq; a restart ignores signals that were already waiting', () async {
    link.send('hoodimong/hello');
    link.send('hoodimong/alarm', to: '*', data: {'text': 'x'});
    final j = jsonDecode(File('${dir.path}/signals/hoodimate.json').readAsStringSync());
    expect([j['seq'], j['type'], j['to']], [2, 'hoodimong/alarm', '*']);
    put('signals/hoodibot.json', {'app': 'hoodibot', 'seq': 9, 'type': 'hoodimong/hello', 'to': 'hoodimate', 'data': {}, 'ts': now});
    final again = PetLink(now: () => now);
    await again.init(testDir: dir);
    expect(again.takeSignal(), isNull);
    again.send('hoodimong/cheer');
    expect(jsonDecode(File('${dir.path}/signals/hoodimate.json').readAsStringSync())['seq'], 3);
  });

  test('joins the other alarm at most once a minute', () {
    final ringing = PetPresence.fromJson(bot(state: 'alarm'))!;
    expect(link.shouldJoinAlarm(ringing), isTrue);
    expect(link.shouldJoinAlarm(ringing), isFalse);
    now += 61;
    expect(link.shouldJoinAlarm(ringing), isTrue);
  });

  test('home means visit (10 min), alarm means no hello', () {
    final home = PetPresence.fromJson(bot(state: 'home'))!;
    expect(link.shouldGreet(me(), home), isFalse);
    expect(link.shouldVisit(me(), home), isTrue);
    expect(link.shouldVisit(me(), home), isFalse);
    now += 601;
    expect(link.shouldVisit(me(x: 2000), home), isFalse); // too far
    expect(link.shouldGreet(me(), PetPresence.fromJson(bot(state: 'alarm'))!), isFalse);
    expect(link.shouldVisit(me(), PetPresence.fromJson(bot(state: 'walk'))!), isFalse);
  });
}
