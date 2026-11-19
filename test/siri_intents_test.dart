import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/services/reminders.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

// Owner (2026-10-28): "Hey Siri, ask Hoodimate / Hoodimate reminder / feed".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Siri reminder sentence is understood offline, in all three languages', () {
    for (final code in ['ko', 'en', 'zh']) {
      test(code, () {
        Lang.code = code;
        final now = DateTime(2026, 10, 28, 9, 0);
        final r = Reminders();
        final line = Lang.t('10분 뒤에 물 마시기 알려줘', 'remind me in 10 minutes to drink water', '10分钟后提醒我喝水');
        final reply = r.handle(line, now);
        expect(reply, isNotNull, reason: line);
        expect(r.items, hasLength(1));
        expect(r.items.single.at, now.add(const Duration(minutes: 10)));
        expect(r.items.single.text, contains(Lang.t('물 마시기', 'drink water', '喝水')));
      });
    }
  });

  group('brain side', () {
    late Directory tmp;
    late PetBrain b;
    setUp(() {
      for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
      }
      Lang.code = 'en';
      tmp = Directory.systemTemp.createTempSync('siri');
      PathProviderPlatform.instance = _Paths(tmp.path);
      b = PetBrain();
    });
    tearDown(() {
      b.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('reminder through Siri lands in the reminders list and Siri hears the confirmation', () async {
      final said = await b.siriRemind(15, 'stretch');
      expect(b.reminders.items, hasLength(1));
      expect(b.reminders.items.single.text, contains('stretch'));
      expect(said, contains('stretch'));
    });

    test('zero minutes asks again instead of setting anything', () async {
      expect(await b.siriRemind(0, 'x'), isNotEmpty);
      expect(b.reminders.items, isEmpty);
    });

    test('empty question gets a "say it again", not a blank answer', () async {
      expect(await b.siriAsk('  '), isNotEmpty);
    });

    test('cloud AI chosen but no consent yet: Siri says to agree in the app and sends nothing (5.1.2)', () async {
      b.ai.activeId = 'gemini';
      final p = b.ai.active;
      p
        ..apiKey = 'test-key'
        ..model = 'test-model';
      expect(p.isReady, isTrue);
      expect(b.ai.needsConsent(p), isTrue);
      var asked = false;
      b.askAiConsent = (_) async {
        asked = true;
        return true;
      };
      final said = await b.siriAsk('오늘 뭐 하면 좋을까?');
      expect(said, PetBrainSiri.siriNeedsConsent);
      expect(asked, isFalse, reason: 'no dialog behind Siri');
      expect(b.memory.active.chat.where((m) => m.fromUser), isEmpty, reason: 'nothing sent or logged');
    });

    test('an error line is never read out by Siri (provider names stay in the app)', () async {
      b.ai.activeId = 'gemini';
      b.ai.active
        ..apiKey = 'test-key'
        ..model = 'test-model';
      b.ai.consented.add('gemini');
      b.ai.client = MockClient((_) async => http.Response('nope', 500));
      final said = await b.siriAsk('hello there friend, what should I do today');
      expect(said, isNot(startsWith('⚠️')));
      expect(said.toLowerCase(), isNot(contains('gemini')));
    });

    test('"how is it feeling" answers from the pet\'s own stats, in every language, with no AI', () {
      b.hunger = 72;
      b.energy = 41;
      b.happiness = 88;
      b.ai.activeId = 'gemini';
      b.ai.active
        ..apiKey = 'test-key'
        ..model = 'test-model'; // a cloud AI that has no consent yet
      for (final code in ['en', 'ko', 'zh']) {
        Lang.code = code;
        final said = b.siriFeeling();
        expect(said, contains('72%'), reason: code);
        expect(said, contains('41%'), reason: code);
        expect(said, contains('88%'), reason: code);
      }
      expect(b.memory.active.chat, isEmpty, reason: 'nothing is sent or logged');
    });

    test('feed through Siri feeds the pet', () {
      b.hunger = 30;
      final said = b.siriFeed();
      expect(said, isNotEmpty);
      expect(b.hunger, greaterThan(30));
    });
  });
}
