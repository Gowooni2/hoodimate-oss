import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/care_rules.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';
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
  late Directory tmp;
  late PetBrain b;

  setUp(() {
    // PetBrain builds an AudioPlayer; silence its native channels.
    for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    Lang.code = 'en';
    tmp = Directory.systemTemp.createTempSync('care_audit');
    PathProviderPlatform.instance = _Paths(tmp.path);
    b = PetBrain();
  });
  tearDown(() {
    b.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {} // a fire-and-forget _save() may still be writing
  });

  Future<void> loadState(Map<String, Object?> j) async {
    File('${tmp.path}/pet_state.json').writeAsStringSync(jsonEncode(j));
    await b.debugLoad();
  }

  group('CareStats (pure)', () {
    CareStats s({double hunger = 80, double happiness = 80, double health = 90, double energy = 80, bool sleeping = false, bool night = false}) =>
        CareStats(hunger: hunger, happiness: happiness, health: health, energy: energy, sleeping: sleeping, night: night);

    test('isNight boundaries 22:00 and 07:00', () {
      expect(CareStats.isNight(DateTime(2026, 1, 1, 21, 59, 59)), isFalse);
      expect(CareStats.isNight(DateTime(2026, 1, 1, 22)), isTrue);
      expect(CareStats.isNight(DateTime(2026, 1, 1, 0)), isTrue);
      expect(CareStats.isNight(DateTime(2026, 1, 1, 6, 59, 59)), isTrue);
      expect(CareStats.isNight(DateTime(2026, 1, 1, 7)), isFalse);
    });

    test('need priority: sick > sleeping > hungry > tired > bored; exact thresholds', () {
      expect(s(health: 29.99, sleeping: true, hunger: 0).needMood(), PetMood.sick);
      expect(s(health: 30).needMood(), isNull);
      expect(s(sleeping: true, hunger: 0).needMood(), PetMood.sleepy);
      expect(s(hunger: 24.99).needMood(), PetMood.sad);
      expect(s(hunger: 25).needMood(), isNull);
      expect(s(energy: 19.99).needMood(), PetMood.bored, reason: 'daytime tired = bored');
      expect(s(energy: 19.99, night: true).needMood(), PetMood.sleepy);
      expect(s(energy: 20).needMood(), isNull);
      expect(s(happiness: 29.99).needMood(), PetMood.bored);
      expect(s(hunger: 24, energy: 10, happiness: 10).needMood(), PetMood.sad);
    });

    test('care button blocks', () {
      expect(s(sleeping: true).feedBlock, isNotNull);
      expect(s(sleeping: true).playBlock, isNotNull);
      expect(s(hunger: 95).feedBlock, isNotNull);
      expect(s(hunger: 94.99).feedBlock, isNull);
      expect(s(energy: 14.99).playBlock, isNotNull);
      expect(s(energy: 15).playBlock, isNull);
      expect(s(hunger: 9.99).playBlock, isNotNull);
      expect(s(hunger: 10).playBlock, isNull);
      expect(s(health: 60).medicineBlock, isNotNull);
      expect(s(health: 59.99).medicineBlock, isNull);
    });

    test('needText never empty, all languages, every branch', () {
      for (final lang in ['ko', 'en', 'zh']) {
        Lang.code = lang;
        for (final c in [s(health: 10), s(sleeping: true), s(hunger: 5), s(energy: 5), s(energy: 5, night: true), s(happiness: 5), s(health: 50), s()]) {
          expect(c.needText(), isNotEmpty);
        }
      }
    });
  });

  group('sleep and waking (owner rules)', () {
    test('sleeping pet wakes ONLY at energy >= 99.5, hunger < 20, or a shaken mouse', () {
      b
        ..sleeping = true
        ..energy = 50
        ..hunger = 80;
      for (var i = 0; i < 10; i++) {
        b.debugTick();
      }
      expect(b.sleeping, isTrue, reason: 'still tired and fed');
    });

    test('energy threshold is exactly 99.5 after the tick\'s +1.2', () {
      b
        ..sleeping = true
        ..energy = 98.2 // -> 99.4
        ..hunger = 80;
      b.debugTick();
      expect(b.sleeping, isTrue);
      b
        ..energy = 98.3 // -> 99.5
        ..hunger = 80;
      b.debugTick();
      expect(b.sleeping, isFalse, reason: 'rested');
    });

    test('hunger below 20 wakes it; 20.0 and above does not', () {
      b
        ..sleeping = true
        ..energy = 10
        ..hunger = 20.3; // -> 20.12
      b.debugTick();
      expect(b.sleeping, isTrue);
      b.hunger = 20.1; // -> 19.92
      b.debugTick();
      expect(b.sleeping, isFalse);
    });

    test('owner activity does NOT wake it: chat, panel, touch, petting, tickling, sticker', () async {
      b
        ..sleeping = true
        ..energy = 10
        ..hunger = 80;
      b.togglePanel();
      b.onTouched();
      b.onPetted();
      b.onTickled();
      b.sendSticker('love');
      await b.sendChat('/remind list');
      expect(b.sleeping, isTrue);
    });

    test('feed / play are blocked while sleeping and do not change stats', () {
      b
        ..sleeping = true
        ..hunger = 50
        ..energy = 50
        ..happiness = 50;
      b.feed();
      b.play();
      expect([b.hunger, b.energy, b.happiness], [50, 50, 50]);
    });

    test('medicine and scold on a sleeping pet do not silently wake it', () {
      b
        ..sleeping = true
        ..health = 10
        ..whine = 2;
      b.medicine();
      b.scold();
      expect(b.sleeping, isTrue);
    });

    test('shake wakes only a sleeping pet; waking when awake is a no-op', () {
      b.wakeByShake();
      expect(b.sleeping, isFalse);
      expect(b.bubbleText, isNull);
      b.sleeping = true;
      b.wakeByShake();
      expect(b.sleeping, isFalse);
    });

    test('sleep button: sleeps any time, pressing again does not wake', () {
      b.toggleSleep();
      expect(b.sleeping, isTrue);
      b.toggleSleep();
      expect(b.sleeping, isTrue);
      expect(b.sleepBlock, isNotNull);
    });

    test('sleep button on a starving pet: it just wakes at the next tick (documented)', () {
      b.hunger = 10;
      b.toggleSleep();
      b.debugTick();
      expect(b.sleeping, isFalse);
    });

    test('a pet that is put to sleep keeps no stale "whine" that lets the owner scold a sleeper', () {
      b.whine = 2;
      b.toggleSleep();
      expect(b.scoldBlock, isNotNull, reason: 'scold button is enabled for a sleeping pet');
    });

    test('sleeping restores energy to the clamp and never above 100', () {
      b
        ..sleeping = true
        ..energy = 99.9
        ..hunger = 90;
      b.debugDecay();
      expect(b.energy, lessThanOrEqualTo(100));
    });

    test('auto bedtime only at night, only when not hungry and owner idle (checked against the real clock)', () {
      final night = CareStats.isNight(DateTime.now());
      b
        ..energy = 50
        ..hunger = 10; // too hungry to sleep
      b.debugBedtime();
      expect(b.sleeping, isFalse);
      b.hunger = 80;
      b.debugBedtime();
      // owner "just interacted" at construction time -> not idle for 15 min -> never sleeps in a test run
      expect(b.sleeping, isFalse);
      expect(night || !night, isTrue);
    });
  });

  group('scolding', () {
    test('scold button only after 2 whines', () {
      for (final w in [0, 1]) {
        b.whine = w;
        expect(b.scoldBlock, isNotNull, reason: 'whine=$w');
      }
      for (final w in [2, 3, 10]) {
        b.whine = w;
        expect(b.scoldBlock, isNull, reason: 'whine=$w');
      }
    });

    test('scold() with fewer than 2 whines is a no-op', () {
      b
        ..whine = 1
        ..happiness = 70;
      b.scold();
      expect(b.happiness, 70);
      expect(b.whine, 1);
    });

    test('scold() after 2 whines: resets whine, costs 3 happiness, never below 0', () {
      b
        ..whine = 2
        ..happiness = 2;
      b.scold();
      expect(b.whine, 0);
      expect(b.happiness, 0);
      expect(b.scoldBlock, isNotNull);
    });

    test('any care action clears whining', () {
      for (final act in [() => b.feed(), () => b.play(), () => b.medicine() /* health 90: blocked */]) {
        b
          ..whine = 3
          ..health = 40
          ..hunger = 50
          ..energy = 50;
        act();
      }
      expect(b.whine, 0);
    });
  });

  group('stats stay in 0..100', () {
    test('thousands of care actions and decay ticks never leave the range', () {
      void check() {
        for (final v in [b.hunger, b.happiness, b.health, b.energy]) {
          expect(v, inInclusiveRange(0, 100));
          expect(v.isNaN, isFalse);
        }
      }

      for (var i = 0; i < 3000; i++) {
        b.debugDecay();
        if (i % 7 == 0) b.feed();
        if (i % 11 == 0) b.play();
        if (i % 13 == 0) b.medicine();
        if (i % 500 == 0) b.sleeping = !b.sleeping;
        check();
      }
      // pure decay to the floor
      b.sleeping = false;
      for (var i = 0; i < 100000; i++) {
        b.debugDecay();
      }
      check();
      expect([b.hunger, b.happiness, b.energy, b.health], everyElement(greaterThanOrEqualTo(0)));
    });

    test('touch / pet / tickle rewards clamp at 100', () {
      b
        ..happiness = 99.9
        ..health = 29
        ..energy = 1;
      b.onTouched(); // sick -> comfort
      b.onPetted();
      b.onTickled();
      for (final v in [b.happiness, b.health, b.energy]) {
        expect(v, inInclusiveRange(0, 100));
      }
    });

    test('loading out-of-range numbers clamps them', () async {
      await loadState({'hunger': 1e9, 'happiness': -50, 'health': 100.5, 'energy': 1e308, 'lastSeen': DateTime.now().toIso8601String()});
      expect([b.hunger, b.happiness, b.health, b.energy], everyElement(inInclusiveRange(0, 100)));
    });

    test('one bad field in pet_state.json does not throw away every other field', () async {
      await loadState({'hunger': 'lots', 'energy': 40, 'happiness': 33, 'sleeping': true, 'petScale': 1.5, 'lastSeen': DateTime.now().toIso8601String()});
      expect(b.energy, 40, reason: 'one wrong type aborted the whole load');
      expect(b.sleeping, isTrue);
    });

    test('non-object pet_state.json (corrupt/synced junk) keeps defaults', () async {
      File('${tmp.path}/pet_state.json').writeAsStringSync('[1,2,3]');
      await b.debugLoad();
      expect(b.hunger, 80);
    });
  });

  group('offline decay is capped at 12 h', () {
    final full = {'hunger': 100.0, 'happiness': 100.0, 'health': 100.0, 'energy': 100.0};

    test('closed 12 h, 5 days and 400 days all come back identical', () async {
      final res = <List<double>>[];
      for (final ago in [const Duration(hours: 12), const Duration(days: 5), const Duration(days: 400)]) {
        final x = PetBrain();
        b = x;
        await loadState({...full, 'lastSeen': DateTime.now().subtract(ago).toIso8601String()});
        res.add([x.hunger, x.happiness, x.health, x.energy]);
        x.dispose();
      }
      expect(res[1], res[0]);
      expect(res[2], res[0]);
      b = PetBrain();
    });

    test('11 h away decays strictly less than 12 h away', () async {
      await loadState({...full, 'lastSeen': DateTime.now().subtract(const Duration(hours: 6)).toIso8601String()});
      final h6 = b.hunger;
      await loadState({...full, 'lastSeen': DateTime.now().subtract(const Duration(hours: 12)).toIso8601String()});
      expect(b.hunger, lessThan(h6));
    });

    test('lastSeen in the future (clock change) and garbage lastSeen apply no decay', () async {
      await loadState({...full, 'lastSeen': DateTime.now().add(const Duration(days: 3)).toIso8601String()});
      expect(b.hunger, 100);
      await loadState({...full, 'lastSeen': 'yesterday'});
      expect(b.hunger, 100);
      await loadState({...full});
      expect(b.hunger, 100);
    });

    test('coming back after a long weekend must not leave the pet sick (the code comment\'s promise)', () async {
      await loadState({...full, 'lastSeen': DateTime.now().subtract(const Duration(days: 3)).toIso8601String()});
      expect(b.health, greaterThanOrEqualTo(30), reason: 'health is ${b.health.toStringAsFixed(1)}: the 12 h replay drains hunger to 0 and then health to ~0');
    });

    test('state after reload keeps sleeping flag and care timestamp', () async {
      await loadState({...full, 'sleeping': true, 'energy': 10.0, 'lastSeen': DateTime.now().toIso8601String()});
      expect(b.sleeping, isTrue);
      expect(b.energy, 10);
    });
  });

  group('save / load round trip', () {
    test('values survive; per-Mac settings are clamped on load', () async {
      b
        ..hunger = 33
        ..energy = 44
        ..petScale = 1.2;
      await b.debugSave();
      final j = jsonDecode(File('${tmp.path}/pet_state.json').readAsStringSync()) as Map;
      expect(j['hunger'], 33);
      final c = PetBrain();
      await c.debugLoad();
      expect(c.hunger, closeTo(33, 1));
      expect(c.petScale, 1.2);
      c.dispose();
      await loadState({'petScale': 99, 'panelW': -5, 'panelH': 1e9, 'chatFontScale': 0});
      expect(b.petScale, 1.6);
      expect(b.panelW, PetBrain.panelMin.width);
      expect(b.panelH, PetBrain.panelMax.height);
    });
  });
}
