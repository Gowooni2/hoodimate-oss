import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/onboarding.dart';
import 'package:hoodimong/models/panel_theme.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/chat_ai.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/services/sync_service.dart';
import 'package:hoodimong/widgets/onboarding.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding.needed', () {
    test('only the sold editions, only until done', () {
      for (final e in Edition.values) {
        final sold = e == Edition.store || e == Edition.direct;
        expect(Onboarding.needed(edition: e, done: false), sold, reason: e.name);
        expect(Onboarding.needed(edition: e, done: true), isFalse, reason: e.name);
      }
    });
    test('promo demo and film runs never show it', () {
      expect(Onboarding.needed(edition: Edition.store, done: false, demo: true), isFalse);
      expect(Onboarding.needed(edition: Edition.store, done: false, film: true), isFalse);
    });
    test('saved flag: no file = fresh install, file without key = existing owner', () {
      expect(Onboarding.savedDone(null), isFalse);
      expect(Onboarding.savedDone({'hunger': 50}), isTrue);
      expect(Onboarding.savedDone({'onboardingDone': false}), isFalse);
      expect(Onboarding.savedDone({'onboardingDone': true}), isTrue);
      expect(Onboarding.savedDone({'onboardingDone': 'yes'}), isTrue);
    });
    test('the flag is per Mac (never synced)', () {
      expect(SyncMerge.localOnly, contains('onboardingDone'));
    });
  });

  group('onboarding state in PetBrain', () {
    late Directory tmp;
    late PetBrain b;
    setUp(() {
      for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
      }
      tmp = Directory.systemTemp.createTempSync('onboarding');
      PathProviderPlatform.instance = _Paths(tmp.path);
      b = PetBrain();
    });
    tearDown(() {
      b.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('fresh install: not done; the owner\'s build never shows it', () async {
      await b.debugLoad();
      expect(b.onboardingDone, isFalse);
      expect(b.needsOnboarding, Ed.isSold); // tests run as the personal edition
      expect(b.needsOnboarding, isFalse);
    });

    test('a state file from 1.1.0 (no key) counts as done', () async {
      File('${tmp.path}/pet_state.json').writeAsStringSync(jsonEncode({'hunger': 70.0}));
      await b.debugLoad();
      expect(b.onboardingDone, isTrue);
    });

    test('done is saved and read back; unfinished stays unfinished', () async {
      await b.debugLoad();
      await b.debugSave();
      final b2 = PetBrain();
      await b2.debugLoad();
      expect(b2.onboardingDone, isFalse, reason: 'saved while unfinished');
      await b.completeOnboarding();
      final b3 = PetBrain();
      await b3.debugLoad();
      expect(b3.onboardingDone, isTrue);
      b2.dispose();
      b3.dispose();
    });
  });

  group('default AI provider (sold editions)', () {
    List<AiProvider> ps() => defaultProviders();
    String? pick({bool sold = true, bool apple = true, String active = 'gemini', List<AiProvider>? providers}) =>
        ChatAi.defaultProviderId(
            sold: sold, providers: providers ?? ps(), activeId: active, appleAvailable: apple);

    test('no key + Apple Intelligence available -> on-device', () => expect(pick(), 'apple'));
    test('Mac without Apple Intelligence keeps the no-key reply', () => expect(pick(apple: false), isNull));
    test('the owner\'s own build is untouched', () => expect(pick(sold: false), isNull));
    test('a configured cloud key wins', () {
      final p = ps();
      final g = p.firstWhere((x) => x.id == 'gemini');
      g.apiKey = 'k';
      g.model = 'm';
      expect(pick(providers: p), isNull);
    });
    test('a configured local model wins', () {
      final p = ps();
      p.firstWhere((x) => x.id == 'local').model = 'qwen';
      expect(pick(providers: p, active: 'local'), isNull);
    });
    test('already on-device: nothing to do', () => expect(pick(active: 'apple'), isNull));

    test('applyDefaultProvider switches the active id only when it should', () async {
      final ai = ChatAi();
      await ai.applyDefaultProvider(sold: true, available: () async => true);
      expect(ai.activeId, 'apple');
      expect(ai.active.isReady, isTrue);
      final other = ChatAi();
      await other.applyDefaultProvider(sold: true, available: () async => false);
      expect(other.activeId, 'gemini');
      final mine = ChatAi();
      await mine.applyDefaultProvider(sold: false, available: () async => true);
      expect(mine.activeId, 'gemini');
    });
  });

  group('OnboardingFlow widget', () {
    Future<void> pump(WidgetTester t, String lang, Size size, VoidCallback onDone) async {
      Lang.code = lang;
      final b = PetBrain();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: size,
              child: OnboardingFlow(brain: b, theme: PanelTheme.byId('cream'), onDone: onDone),
            ),
          ),
        ),
      ));
      await t.pump();
      addTearDown(b.dispose);
    }

    for (final lang in ['ko', 'en', 'zh']) {
      testWidgets('walks picker -> Feed, Play, Sleep, Hoodibot without overflow ($lang)', (t) async {
        var done = 0;
        await t.pumpWidget(const SizedBox());
        await pump(t, lang, PetBrain.panelMin, () => done++);
        expect(find.byKey(const Key('onboarding-skip')), findsNothing, reason: 'picker has no skip');
        for (final c in Onboarding.careCards) {
          await t.tap(find.byKey(const Key('onboarding-next')));
          await t.pump();
          expect(find.text(Onboarding.title(c)), findsOneWidget, reason: c);
          expect(find.text(Onboarding.line(c)), findsOneWidget, reason: c);
          expect(t.takeException(), isNull, reason: '$lang $c');
        }
        expect(find.text(Onboarding.start), findsOneWidget);
        expect(done, 0);
        await t.tap(find.byKey(const Key('onboarding-next')));
        expect(done, 1);
      });
    }

    testWidgets('skip is offered after the picker and finishes', (t) async {
      var done = 0;
      await pump(t, 'en', PetBrain.panelDefault, () => done++);
      await t.tap(find.byKey(const Key('onboarding-next')));
      await t.pump();
      await t.tap(find.byKey(const Key('onboarding-skip')));
      expect(done, 1);
    });

    test('the last card is about Hoodibot', () {
      expect(Onboarding.careCards.last, 'hoodibot');
      for (final l in ['ko', 'en', 'zh']) {
        Lang.code = l;
        expect(Onboarding.line('hoodibot'), contains(l == 'zh' ? 'Hoodibot' : (l == 'ko' ? '후디봇' : 'Hoodibot')));
      }
    });
  });
}
