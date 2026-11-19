import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/sync_service.dart';

Map<String, dynamic> msg(String at, String t, {bool u = true}) => {'at': at, 'u': u, 't': t};
Map<String, dynamic> proj(String id, {String? upd, List<Map<String, dynamic>>? chat, List<String>? notes, bool archived = false, String? name}) => {
      'id': id,
      'name': name ?? id,
      'notes': notes ?? <String>[],
      'chat': chat ?? <Map<String, dynamic>>[],
      if (upd != null) 'updatedAt': upd,
      if (archived) 'archived': true,
    };
List ids(Map m) => (m['projects'] as List).map((p) => p['id']).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('projects merge', () {
    test('empty / missing keys on either side', () {
      expect(ids(SyncMerge.projects({}, {})), isEmpty);
      expect(ids(SyncMerge.projects({'projects': [proj('a')]}, {})), ['a']);
      expect(ids(SyncMerge.projects({}, {'projects': [proj('a')]})), ['a']);
      expect(SyncMerge.projects({'projects': null}, {'projects': null})['projects'], isEmpty);
    });

    test('merging the same data twice changes nothing (idempotent) and is stable in both directions', () {
      final a = {'projects': [proj('p', upd: '2026-10-06T08:00:00', chat: [msg('2026-10-06T07:00:00', 'x'), msg('2026-10-06T08:00:00', 'y')], notes: ['n1'])]};
      final b = {'projects': [proj('p', upd: '2026-10-06T09:00:00', chat: [msg('2026-10-06T07:00:00', 'x'), msg('2026-10-06T09:00:00', 'z')], notes: ['n2'])]};
      final ab = SyncMerge.projects(a, b);
      final ba = SyncMerge.projects(b, a);
      expect(jsonEncode(SyncMerge.projects(ab, b)), jsonEncode(ab));
      expect(jsonEncode(SyncMerge.projects(ab, ab)), jsonEncode(ab));
      final cab = (ab['projects'] as List).first;
      final cba = (ba['projects'] as List).first;
      expect((cab['chat'] as List).map((c) => c['t']), (cba['chat'] as List).map((c) => c['t']));
      expect((cab['notes'] as List).toSet(), (cba['notes'] as List).toSet());
    });

    test('duplicate message in a chat is collapsed (same at+sender+text)', () {
      final c = msg('2026-10-06T07:00:00', 'dup');
      final m = SyncMerge.projects({'projects': [proj('p', chat: [c, c])]}, {'projects': [proj('p', chat: [c])]});
      expect(((m['projects'] as List).first['chat'] as List), hasLength(1));
    });

    test('same text twice at different times, and same time by user vs pet, are both kept', () {
      final m = SyncMerge.projects({
        'projects': [proj('p', chat: [msg('2026-10-06T07:00:00', 'ok'), msg('2026-10-06T07:00:00', 'ok', u: false)])]
      }, {
        'projects': [proj('p', chat: [msg('2026-10-06T07:05:00', 'ok')])]
      });
      expect(((m['projects'] as List).first['chat'] as List), hasLength(3));
    });

    test('chat is capped at 200 and the newest are kept; notes capped at 40 newest', () {
      final big = [for (var i = 0; i < 250; i++) msg('2026-10-06T10:${(i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}', 'm$i')];
      final m = SyncMerge.projects({'projects': [proj('p', chat: big, notes: [for (var i = 0; i < 50; i++) 'n$i'])]},
          {'projects': [proj('p', chat: [], notes: ['extra'])]});
      final p = (m['projects'] as List).first;
      expect(p['chat'], hasLength(200));
      expect(p['chat'].last['t'], 'm249');
      expect(p['notes'], hasLength(40));
      expect(p['notes'].last, 'extra');
    });

    test('clock skew: remote updatedAt far in the future wins for name/archived, but chats are still unioned', () {
      final here = {'projects': [proj('p', upd: '2026-10-06T08:00:00', name: 'Old', chat: [msg('2026-10-06T08:00:00', 'mine')])]};
      final there = {'projects': [proj('p', upd: '2099-01-01T00:00:00', name: 'New', archived: true, chat: [msg('2026-10-06T07:00:00', 'theirs')])]};
      final p = (SyncMerge.projects(here, there)['projects'] as List).first;
      expect(p['name'], 'New');
      expect(p['archived'], true);
      expect((p['chat'] as List).map((c) => c['t']), ['theirs', 'mine']);
    });

    test('a far-future updatedAt must not freeze the project: merged updatedAt is capped to now+skew', () {
      final there = {'projects': [proj('p', upd: '2099-01-01T00:00:00')]};
      final p = (SyncMerge.projects({'projects': [proj('p', upd: '2026-10-06T08:00:00')]}, there)['projects'] as List).first;
      expect(DateTime.parse(p['updatedAt']).isBefore(DateTime.now().add(const Duration(days: 2))), isTrue,
          reason: 'one Mac with a wrong clock makes every later edit on the other Mac lose forever');
    });

    test('missing updatedAt on both sides: deterministic and not data-losing', () {
      final m = SyncMerge.projects({'projects': [proj('p', name: 'A', chat: [msg('2026-10-06T08:00:00', 'a')])]},
          {'projects': [proj('p', name: 'B', chat: [msg('2026-10-06T08:00:01', 'b')])]});
      expect(((m['projects'] as List).first['chat'] as List), hasLength(2));
    });

    test('archived on one Mac but newer chat activity on the other Mac: the newer update wins', () {
      final m = SyncMerge.projects({'projects': [proj('p', upd: '2026-10-06T08:00:00', archived: true)]},
          {'projects': [proj('p', upd: '2026-10-06T09:00:00', chat: [msg('2026-10-06T09:00:00', 'back again')])]});
      expect((m['projects'] as List).first['archived'], isNull);
    });

    test('the remote manual room never enters; the local manual room stays local', () {
      final m = SyncMerge.projects({'projects': [proj('general'), proj('manual', chat: [msg('2026-10-06T07:00:00', 'local manual')])]},
          {'projects': [proj('manual', chat: [msg('2026-10-06T07:00:00', 'REMOTE')]), proj('p1')]});
      expect(ids(m), ['general', 'manual', 'p1']);
      final manual = (m['projects'] as List).firstWhere((p) => p['id'] == 'manual');
      expect((manual['chat'] as List).map((c) => c['t']), ['local manual']);
    });

    test('forShare strips the manual room and "active" but leaves everything else, and does not mutate its input', () {
      final merged = {'active': 'manual', 'projects': [proj('general'), proj('manual'), proj('p1')]};
      final shared = SyncMerge.forShare('projects.json', merged);
      expect(ids(shared), ['general', 'p1']);
      expect(shared.containsKey('active'), isFalse);
      expect(ids(merged), ['general', 'manual', 'p1']);
      expect(merged['active'], 'manual');
    });

    test('forShare of other files is a pass-through', () {
      final j = {'language': 'ko'};
      expect(SyncMerge.forShare('profile.json', j), j);
    });

    test('active: this Mac\'s open room is kept; falls back to remote only if none locally', () {
      expect(SyncMerge.projects({'active': 'a', 'projects': []}, {'active': 'b', 'projects': []})['active'], 'a');
      expect(SyncMerge.projects({'projects': []}, {'active': 'b', 'projects': []})['active'], 'b');
    });

    test('active may point at a room that exists only remotely / was removed: merged result still contains it or falls back', () {
      final m = SyncMerge.projects({'active': 'gone', 'projects': [proj('general')]}, {'projects': [proj('general')]});
      // ProjectMemory.active already falls back to projects.first for an unknown id; just make sure we do not crash.
      expect(m['active'], anyOf('gone', 'general'));
    });

    test('malformed remote: project without id / non-map entries / non-list chat do not abort the whole file', () {
      final good = {'projects': [proj('a', chat: [msg('2026-10-06T07:00:00', 'x')])]};
      final bad = {
        'projects': [
          {'name': 'no id'},
          'junk',
          null,
          5,
          {'id': 'a', 'chat': 'not a list', 'notes': 7},
          proj('b'),
        ]
      };
      final m = SyncMerge.projects(good, bad);
      expect(ids(m), containsAll(['a', 'b']));
    });

    test('malformed notes / chat entries inside valid projects', () {
      final m = SyncMerge.projects({'projects': [proj('a')]}, {'projects': [{'id': 'a', 'name': 'a', 'notes': [1, null, 'ok'], 'chat': [null, 'x', {'t': 'no at'}], 'updatedAt': 'bad'}]});
      expect(ids(m), ['a']);
    });

    test('duplicate ids inside ONE side do not produce duplicate projects', () {
      final m = SyncMerge.projects({'projects': [proj('a'), proj('a')]}, {'projects': []});
      expect(ids(m), ['a']);
    });

    test('mixed timezone timestamps order by instant, not by string', () {
      final m = SyncMerge.projects({
        'projects': [proj('p', chat: [msg('2026-10-06T05:00:00Z', 'later (05:00Z)')])]
      }, {
        'projects': [proj('p', chat: [msg('2026-10-06T10:00:00+09:00', 'earlier (01:00Z)')])]
      });
      expect(((m['projects'] as List).first['chat'] as List).map((c) => c['t']), ['earlier (01:00Z)', 'later (05:00Z)']);
    });
  });

  group('pet_state merge', () {
    const localOnlyKeys = SyncMerge.localOnly;
    Map<String, dynamic> st({double hunger = 50, String seen = '2026-10-06T10:00:00', String? care, Map<String, dynamic> extra = const {}}) => {
          'hunger': hunger,
          'lastSeen': seen,
          if (care != null) 'careAt': care,
          ...extra
        };

    test('every per-Mac key is listed as local-only', () {
      expect(localOnlyKeys, containsAll(['cuesEnabled', 'macFallback', 'roam', 'sfxVolume', 'haptics', 'speechMode', 'petScale', 'panelW', 'panelH', 'panelTheme', 'chatFont', 'chatFontScale']));
    });

    test('remote wins: stats come over, EVERY local-only key stays local even if the remote has a different value', () {
      final local = st(hunger: 10, care: '2026-10-06T08:00:00', extra: {for (final k in localOnlyKeys) k: 'LOCAL'});
      final remote = st(hunger: 90, care: '2026-10-06T09:00:00', extra: {for (final k in localOnlyKeys) k: 'REMOTE'});
      final m = SyncMerge.petState(local, remote, joined: true);
      expect(m['hunger'], 90);
      for (final k in localOnlyKeys) {
        expect(m[k], 'LOCAL', reason: k);
      }
    });

    test('local-only keys the local file does not have are NOT adopted from the remote', () {
      final m = SyncMerge.petState(st(care: '2026-10-06T08:00:00'), st(hunger: 90, care: '2026-10-06T09:00:00', extra: {'petScale': 1.5, 'panelW': 800}), joined: true);
      expect(m.containsKey('petScale'), isFalse);
      expect(m.containsKey('panelW'), isFalse);
    });

    test('fresh Mac (no local pet_state) adopting the remote file must not inherit the other Mac\'s size/volume/theme', () {
      final m = SyncMerge.file('pet_state.json',
          local: null, remote: st(extra: {'petScale': 1.5, 'panelW': 800, 'sfxVolume': 0.0, 'chatFont': 'system', 'panelTheme': 'night'}),
          localAt: DateTime(2026), remoteAt: DateTime(2026), joined: false) as Map;
      for (final k in ['petScale', 'panelW', 'sfxVolume', 'chatFont', 'panelTheme']) {
        expect(m.containsKey(k), isFalse, reason: '$k travelled');
      }
    });

    test('what is written to the shared folder contains no per-Mac keys', () {
      final merged = st(extra: {for (final k in localOnlyKeys) k: 'LOCAL'});
      final shared = SyncMerge.forShare('pet_state.json', merged) as Map;
      for (final k in localOnlyKeys) {
        expect(shared.containsKey(k), isFalse, reason: '$k is published');
      }
      expect(shared['hunger'], 50);
    });

    test('keys missing from the remote keep the local value (older app version)', () {
      final m = SyncMerge.petState({...st(care: '2026-10-06T08:00:00'), 'energy': 40}, st(hunger: 90, care: '2026-10-06T09:00:00'), joined: true);
      expect(m['energy'], 40);
    });

    test('care wins over lastSeen; equal care falls to lastSeen; unparsable dates lose', () {
      expect(SyncMerge.petState(st(hunger: 1, care: '2026-10-06T09:00:00', seen: '2026-10-06T12:00:00'), st(hunger: 2, care: '2026-10-06T08:00:00', seen: '2026-10-06T23:00:00'), joined: true)['hunger'], 1);
      expect(SyncMerge.petState(st(hunger: 1, seen: '2026-10-06T10:00:00'), st(hunger: 2, seen: '2026-10-06T10:00:01'), joined: true)['hunger'], 2);
      expect(SyncMerge.petState(st(hunger: 1, seen: '2026-10-06T10:00:00'), {'hunger': 2, 'lastSeen': 'garbage', 'careAt': 5}, joined: true)['hunger'], 1);
      expect(SyncMerge.petState(st(hunger: 1), {'hunger': 2}, joined: true)['hunger'], 1);
    });

    test('fresh install (joined=false) always takes the remote stats', () {
      expect(SyncMerge.petState(st(hunger: 1, care: '2099-01-01T00:00:00'), st(hunger: 2), joined: false)['hunger'], 2);
    });

    test('a Mac with a clock years ahead must not pin the pet forever', () {
      final ahead = st(hunger: 1, care: '2099-01-01T00:00:00');
      final m = SyncMerge.petState(ahead, st(hunger: 2, care: '2026-10-06T09:00:00'), joined: true);
      // the 2099 care time is accepted at face value today: the other Mac can never win again
      expect(m['hunger'], 2, reason: 'a future careAt (bad clock) makes this side win forever');
    });

    test('out-of-range stats from a bad remote are passed through (PetBrain clamps on load)', () {
      final m = SyncMerge.petState(st(care: '2026-10-06T08:00:00'), st(hunger: 1e30, care: '2026-10-06T09:00:00'), joined: true);
      expect(m['hunger'], 1e30);
    });
  });

  group('SyncMerge.file dispatch', () {
    final t1 = DateTime(2026, 10, 6, 8), t2 = DateTime(2026, 10, 6, 9);
    test('nothing on either side -> null; one side only -> that side', () {
      expect(SyncMerge.file('profile.json', local: null, remote: null, localAt: t1, remoteAt: t1, joined: true), isNull);
      expect(SyncMerge.file('profile.json', local: {'a': 1}, remote: null, localAt: t1, remoteAt: t1, joined: true), {'a': 1});
      expect(SyncMerge.file('profile.json', local: null, remote: {'a': 2}, localAt: t1, remoteAt: t1, joined: true), {'a': 2});
    });
    test('equal timestamps keep local (no flip-flop)', () {
      expect(SyncMerge.file('profile.json', local: {'a': 1}, remote: {'a': 2}, localAt: t1, remoteAt: t1, joined: true), {'a': 1});
    });
    test('profile.json: the profile language / home are synced but AI keys cannot be (not in file list)', () {
      expect(SyncService.files, isNot(contains('ai_config.json')));
      expect(SyncService.files.every((f) => !f.contains('ai') && !f.contains('config')), isTrue);
    });
    test('wrong JSON shape from the shared folder is ignored, not thrown', () {
      expect(() => SyncMerge.file('projects.json', local: {'projects': []}, remote: [1, 2], localAt: t1, remoteAt: t2, joined: true), returnsNormally);
      expect(() => SyncMerge.file('pet_state.json', local: {'hunger': 1}, remote: 'x', localAt: t1, remoteAt: t2, joined: true), returnsNormally);
    });
  });

  group('SyncService.run with a shared folder (channel mocked)', () {
    late Directory root, base, shared;
    setUp(() {
      root = Directory.systemTemp.createTempSync('sync_audit');
      base = Directory('${root.path}/local')..createSync();
      shared = Directory('${root.path}/shared')..createSync();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('hoodimong/sync'), (call) async {
        final a = (call.arguments as Map?) ?? {};
        final f = File('${shared.path}/${a['name']}');
        switch (call.method) {
          case 'restore':
            return shared.path;
          case 'read':
            return f.existsSync() ? f.readAsStringSync() : null;
          case 'write':
            f.parent.createSync(recursive: true);
            f.writeAsStringSync(a['text'] as String);
            return true;
        }
        return null;
      });
    });
    tearDown(() => root.deleteSync(recursive: true));

    void putShared(String name, String text) {
      final f = File('${shared.path}/${SyncService.dirName}/$name')..parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }

    test('one corrupt shared file does not stop the other files from syncing', () async {
      File('${base.path}/reminders.json').writeAsStringSync('[]');
      File('${base.path}/profile.json').writeAsStringSync(jsonEncode({'language': 'ko'}));
      putShared('projects.json', '{{{ not json');
      putShared('pet_state.json', jsonEncode({'savedAt': '2026-10-06T00:00:00Z', 'device': 'x', 'data': [1, 2, 3]}));
      final s = SyncService();
      await s.init(base);
      await s.run(base);
      // profile.json and reminders.json must have been pushed even though earlier files were junk
      expect(File('${shared.path}/${SyncService.dirName}/profile.json').existsSync(), isTrue, reason: 'lastError=${s.lastError}');
    });

    test('a corrupt LOCAL file is skipped, not fatal for the rest', () async {
      File('${base.path}/projects.json').writeAsStringSync('garbage');
      File('${base.path}/profile.json').writeAsStringSync(jsonEncode({'language': 'ko'}));
      final s = SyncService();
      await s.init(base);
      await s.run(base);
      expect(File('${shared.path}/${SyncService.dirName}/profile.json').existsSync(), isTrue, reason: 'lastError=${s.lastError}');
    });

    test('local-only keys never reach the shared folder', () async {
      File('${base.path}/pet_state.json').writeAsStringSync(jsonEncode({'hunger': 50, 'lastSeen': '2026-10-06T10:00:00', 'petScale': 1.5, 'panelW': 700, 'sfxVolume': 0.1}));
      final s = SyncService();
      await s.init(base);
      await s.run(base);
      final text = File('${shared.path}/${SyncService.dirName}/pet_state.json').readAsStringSync();
      for (final k in ['petScale', 'panelW', 'sfxVolume']) {
        expect(text.contains('"$k"'), isFalse, reason: '$k was published');
      }
    });

    test('running twice with no changes writes nothing the second time', () async {
      File('${base.path}/profile.json').writeAsStringSync(jsonEncode({'language': 'ko'}));
      final s = SyncService();
      await s.init(base);
      await s.run(base);
      final f = File('${shared.path}/${SyncService.dirName}/profile.json');
      final first = f.readAsStringSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final changed = await s.run(base);
      expect(changed, isFalse);
      expect(f.readAsStringSync(), first);
    });

    test('no folder -> run is a no-op', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('hoodimong/sync'), (c) async => null);
      final s = SyncService();
      await s.init(base);
      expect(s.ready, isFalse);
      expect(await s.run(base), isFalse);
    });
  });
}
