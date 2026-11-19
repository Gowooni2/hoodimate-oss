import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/services/sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  notifyTests();
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late PetBrain b;

  setUp(() {
    for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    Lang.code = 'en';
    tmp = Directory.systemTemp.createTempSync('native_extras');
    PathProviderPlatform.instance = _Paths(tmp.path);
    b = PetBrain();
  });
  tearDown(() {
    b.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('menu bar status item', () {
    test('every mood has a face; sleeping overrides', () {
      for (final m in PetMood.values) {
        expect(PetBrainNative.statusFace(m), isNotEmpty, reason: m.name);
      }
      expect(PetBrainNative.statusFace(PetMood.happy, sleeping: true), '😴');
      expect(PetBrainNative.statusFace(PetMood.sick), '🤒');
    });

    test('payload carries hunger, energy and localized menu labels', () {
      b.hunger = 72.4;
      b.energy = 55.0;
      final p = b.statusBarPayload();
      expect(p['hunger'], contains('72%'));
      expect(p['energy'], contains('55%'));
      expect(p['feed'], 'Feed');
      expect(p['sleep'], 'Put to sleep');
      expect(p['alarm'], 'New alarm…');
      expect(p['feedEnabled'], isTrue);
      Lang.code = 'ko';
      expect(b.statusBarPayload()['feed'], '밥 주기');
      expect(b.statusBarPayload()['alarm'], '새 알람…');
      Lang.code = 'zh';
      expect(b.statusBarPayload()['show'], contains('Hoodimate'));
    });

    test('Feed is disabled when full, Sleep shows the state and is disabled when asleep', () {
      b.hunger = 98;
      expect(b.statusBarPayload()['feedEnabled'], isFalse);
      b.sleeping = true;
      expect(b.statusBarPayload()['sleep'], 'Sleeping (shake to wake)');
      expect(b.statusBarPayload()['sleepEnabled'], isFalse);
      expect(b.statusBarPayload()['face'], '😴');
    });

    test('the status item exists only in the sold editions (tests run as personal)', () {
      expect(b.statusBarPayload()['enabled'], isFalse);
    });

    test('menu actions: feed, sleep/wake, alarm, show', () {
      b.hunger = 40;
      b.statusBarAction('feed');
      expect(b.hunger, greaterThan(40));
      b.statusBarAction('sleep');
      expect(b.sleeping, isTrue);
      b.statusBarAction('sleep'); // waking is by shaking, not from the menu
      expect(b.sleeping, isTrue);
      b.wakeByShake();
      expect(b.sleeping, isFalse);
      var talk = 0, shown = 0;
      b.openTalk = () => talk++;
      b.showPet = () async => shown++;
      b.statusBarAction('alarm');
      b.statusBarAction('show');
      expect(talk, 1);
      expect(shown, 1);
      expect(b.bubbleText, contains('remind me'));
    });

    test('feeding a full pet says why instead of feeding', () {
      b.hunger = 99;
      b.statusBarAction('feed');
      expect(b.hunger, 99);
      expect(b.bubbleText, isNotEmpty);
    });

    test('the toggle is saved per Mac and never synced', () async {
      expect(b.menuBarEnabled, isTrue);
      b.setMenuBar(false);
      await b.debugSave();
      final b2 = PetBrain();
      await b2.debugLoad();
      expect(b2.menuBarEnabled, isFalse);
      b2.dispose();
      expect(SyncMerge.localOnly, contains('menuBarEnabled'));
    });
  });
}

void notifyTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late PetBrain b;
  final posted = <Map>[];
  var asked = 0;
  var grant = true;

  setUp(() {
    for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    posted.clear();
    asked = 0;
    grant = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hoodimong/notify'), (call) async {
      if (call.method == 'requestAuth') {
        asked++;
        return grant;
      }
      if (call.method == 'post') posted.add(Map.from(call.arguments as Map));
      return null;
    });
    Lang.code = 'en';
    tmp = Directory.systemTemp.createTempSync('notify');
    PathProviderPlatform.instance = _Paths(tmp.path);
    b = PetBrain();
  });
  tearDown(() {
    b.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Notification Center', () {
    test('off by default: nothing is posted and macOS is never asked', () async {
      expect(b.notifyEnabled, isFalse);
      b.hunger = 10;
      b.debugTick();
      await b.postNotice('alarm', 't', 'b');
      expect(posted, isEmpty);
      expect(asked, 0);
    });

    test('permission is requested only when switched on; refusal keeps it off', () async {
      grant = false;
      await b.setNotifications(true);
      expect(asked, 1);
      expect(b.notifyEnabled, isFalse);
      expect(b.notifyDenied, isTrue);
      grant = true;
      await b.setNotifications(true);
      expect(b.notifyEnabled, isTrue);
      expect(b.notifyDenied, isFalse);
      await b.setNotifications(false);
      expect(asked, 2);
      expect(b.notifyEnabled, isFalse);
    });

    test('hungry notice fires once per hunger spell and re-arms after eating', () async {
      await b.setNotifications(true);
      b.hunger = 20;
      b.debugTick();
      await Future<void>.delayed(Duration.zero);
      expect(posted.where((p) => p['id'] == 'hungry'), hasLength(1));
      b.debugTick();
      await Future<void>.delayed(Duration.zero);
      expect(posted.where((p) => p['id'] == 'hungry'), hasLength(1), reason: 'not again while still hungry');
      b.hunger = 60;
      b.debugTick();
      b.hunger = 10;
      b.debugTick();
      await Future<void>.delayed(Duration.zero);
      expect(posted.where((p) => p['id'] == 'hungry'), hasLength(2));
    });

    test('rules: sleeping pets and fed pets get no hungry notice', () {
      expect(PetBrainNative.shouldNoticeHungry(alreadyNoticed: false, hunger: 24, sleeping: false), isTrue);
      expect(PetBrainNative.shouldNoticeHungry(alreadyNoticed: false, hunger: 24, sleeping: true), isFalse);
      expect(PetBrainNative.shouldNoticeHungry(alreadyNoticed: false, hunger: 25, sleeping: false), isFalse);
      expect(PetBrainNative.shouldNoticeHungry(alreadyNoticed: true, hunger: 5, sleeping: false), isFalse);
    });

    test('a ringing alarm posts its text, in the owner\'s language', () async {
      await b.setNotifications(true);
      Lang.code = 'ko';
      b.reminders.handle('1분 뒤에 라면 알려줘', DateTime.now());
      b.debugStartAlarm('라면', '10:00');
      await Future<void>.delayed(Duration.zero);
      final a = posted.singleWhere((p) => p['id'] == 'alarm');
      expect(a['body'], '라면');
      expect(a['title'], contains('알람'));
      b.dismissAlarm();
    });

    test('the switch is saved per Mac and never synced', () async {
      await b.setNotifications(true);
      final b2 = PetBrain();
      await b2.debugLoad();
      expect(b2.notifyEnabled, isTrue);
      b2.dispose();
      expect(SyncMerge.localOnly, contains('notifyEnabled'));
    });
  });
}
