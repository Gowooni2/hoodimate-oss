import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/sync_service.dart';

Map<String, dynamic> msg(String at, String t, {bool u = true}) =>
    {'at': at, 'u': u, 't': t};

void main() {
  group('projects', () {
    test('chats from both Macs are combined in time order, no duplicates', () {
      final home = {
        'active': 'general',
        'projects': [
          {
            'id': 'general', 'name': '일상', 'notes': ['a'],
            'updatedAt': '2026-10-06T08:00:00',
            'chat': [msg('2026-10-06T07:00:00', 'home 1'), msg('2026-10-06T08:00:00', 'home 2')],
          }
        ],
      };
      final work = {
        'projects': [
          {
            'id': 'general', 'name': '일상', 'notes': ['a', 'b'],
            'updatedAt': '2026-10-06T09:00:00',
            'chat': [msg('2026-10-06T07:00:00', 'home 1'), msg('2026-10-06T09:00:00', 'work 1')],
          },
          {'id': 'p1', 'name': 'Work project', 'notes': [], 'updatedAt': '2026-10-06T09:00:00', 'chat': []},
        ],
      };
      final m = SyncMerge.projects(home, work);
      final general = (m['projects'] as List).first;
      expect((general['chat'] as List).map((c) => c['t']), ['home 1', 'home 2', 'work 1']);
      expect(general['notes'], ['a', 'b']);
      expect((m['projects'] as List).map((p) => p['id']), ['general', 'p1']);
      expect(m['active'], 'general'); // the open room stays per Mac
    });

    test('closing a room on the other Mac closes it here (later update wins)', () {
      final here = {
        'projects': [
          {'id': 'p1', 'name': 'X', 'updatedAt': '2026-10-06T08:00:00', 'chat': [], 'notes': []}
        ]
      };
      final there = {
        'projects': [
          {'id': 'p1', 'name': 'X', 'archived': true, 'updatedAt': '2026-10-06T09:00:00', 'chat': [], 'notes': []}
        ]
      };
      expect((SyncMerge.projects(here, there)['projects'] as List).first['archived'], true);
    });

    test('the manual room is never shared', () {
      final m = {
        'active': 'manual',
        'projects': [
          {'id': 'general', 'chat': []},
          {'id': 'manual', 'chat': []},
        ]
      };
      final shared = SyncMerge.forShare('projects.json', m);
      expect((shared['projects'] as List).map((p) => p['id']), ['general']);
      expect(shared.containsKey('active'), isFalse);
    });
  });

  group('pet state', () {
    final here = {
      'hunger': 30.0, 'lastSeen': '2026-10-06T10:00:00', 'careAt': '2026-10-06T08:00:00',
      'petScale': 1.4, 'sfxVolume': 0.2,
    };
    test('a feeding on the other Mac wins even if this Mac saved later', () {
      final there = {
        'hunger': 90.0, 'lastSeen': '2026-10-06T09:59:00', 'careAt': '2026-10-06T09:58:00',
        'petScale': 1.0, 'sfxVolume': 1.0,
      };
      final m = SyncMerge.petState(here, there, joined: true);
      expect(m['hunger'], 90.0);
      expect(m['petScale'], 1.4); // size and volume stay per Mac
      expect(m['sfxVolume'], 0.2);
    });
    test('no newer care there: this Mac keeps its stats', () {
      final there = {'hunger': 10.0, 'lastSeen': '2026-10-06T09:00:00', 'careAt': '2026-10-06T08:00:00'};
      expect(SyncMerge.petState(here, there, joined: true)['hunger'], 30.0);
    });
  });

  group('later edit wins', () {
    final a = {'language': 'ko'}, b = {'language': 'en'};
    final t1 = DateTime(2026, 10, 6, 8), t2 = DateTime(2026, 10, 6, 9);
    test('newer shared copy replaces the local one', () {
      expect(SyncMerge.file('profile.json', local: a, remote: b, localAt: t1, remoteAt: t2, joined: true), b);
      expect(SyncMerge.file('profile.json', local: a, remote: b, localAt: t2, remoteAt: t1, joined: true), a);
    });
    test('a fresh install takes the shared copy first', () {
      expect(SyncMerge.file('profile.json', local: a, remote: b, localAt: t2, remoteAt: t1, joined: false), b);
    });
    test('nothing shared yet: local goes up as is', () {
      expect(SyncMerge.file('reminders.json', local: [], remote: null, localAt: t1, remoteAt: t1, joined: false), []);
    });
  });
}
