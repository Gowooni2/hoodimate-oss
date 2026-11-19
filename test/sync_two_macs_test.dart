import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/sync_service.dart';

/// Two "Macs" (two app-data folders) syncing through one shared folder;
/// the native folder channel is replaced by plain file access.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, home, work, shared;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lite_sync');
    home = Directory('${root.path}/home')..createSync();
    work = Directory('${root.path}/work')..createSync();
    shared = Directory('${root.path}/shared')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hoodimong/sync'), (call) async {
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

  void put(Directory d, String name, Object data) =>
      File('${d.path}/$name').writeAsStringSync(jsonEncode(data));
  dynamic get(Directory d, String name) =>
      jsonDecode(File('${d.path}/$name').readAsStringSync());

  test('home → shared → work, then work chat comes back home', () async {
    put(home, 'projects.json', {
      'active': 'general',
      'projects': [
        {'id': 'general', 'name': '일상', 'notes': [], 'updatedAt': '2026-10-06T08:00:00',
         'chat': [{'t': 'hi from home', 'u': true, 'at': '2026-10-06T08:00:00'}]}
      ]
    });
    put(home, 'profile.json', {'language': 'ko', 'birthday': '03-14'});
    put(home, 'pet_state.json', {'hunger': 80.0, 'lastSeen': '2026-10-06T08:00:00',
        'careAt': '2026-10-06T08:00:00', 'petScale': 1.4});

    // A fresh work Mac with its own default files.
    put(work, 'profile.json', {'language': 'en', 'birthday': ''});
    put(work, 'pet_state.json', {'hunger': 50.0, 'lastSeen': '2026-10-06T09:00:00', 'petScale': 1.0});

    final a = SyncService(), b = SyncService();
    await a.init(home);
    await b.init(work);
    expect(await a.run(home), isFalse); // first upload: nothing new here
    expect(await b.run(work), isTrue); // work takes the shared copy

    expect(get(work, 'profile.json')['birthday'], '03-14');
    expect(get(work, 'pet_state.json')['hunger'], 80.0);
    expect(get(work, 'pet_state.json')['petScale'], 1.0); // size stays per Mac
    expect((get(work, 'projects.json')['projects'] as List).first['chat'].length, 1);

    // Chat at work, then sync both ways.
    final pj = get(work, 'projects.json');
    (pj['projects'] as List).first['chat']
        .add({'t': 'hi from work', 'u': true, 'at': '2026-10-06T10:00:00'});
    (pj['projects'] as List).first['updatedAt'] = '2026-10-06T10:00:00';
    put(work, 'projects.json', pj);
    await b.run(work);
    expect(await a.run(home), isTrue);
    final chat = (get(home, 'projects.json')['projects'] as List).first['chat'] as List;
    expect(chat.map((c) => c['t']), ['hi from home', 'hi from work']);
    expect(b.lastError, isNull);
    expect(a.lastError, isNull);
  });
}
