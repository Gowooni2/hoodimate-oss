import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

// 1.1 (owner, 2026-10-28): the pet reacts to the owner's words without any
// AI, sulks after an insult until an apology, and answers by itself when no
// AI key is set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late PetBrain b;

  setUp(() {
    for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    Lang.code = 'ko';
    tmp = Directory.systemTemp.createTempSync('feelings');
    PathProviderPlatform.instance = _Paths(tmp.path);
    b = PetBrain();
    // No AI set up: the default provider has no key.
    expect(b.ai.active.isReady, isFalse);
  });
  tearDown(() {
    Lang.code = 'en';
    b.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String lastPet() => b.memory.active.chat.lastWhere((m) => !m.fromUser).text;

  test('insult -> sulks and says so, no "add a key" error', () async {
    await b.sendChat('바보야');
    expect(b.sulk.sulking, isTrue);
    expect(lastPet(), anyOf(contains('흥'), contains('칫')));
    expect(lastPet(), isNot(contains('키')));
  });

  test('still sulking: a question gets a sulk line, not an answer', () async {
    await b.sendChat('바보야');
    await b.sendChat('오늘 뭐 할까?');
    expect(b.sulk.sulking, isTrue);
    expect(lastPet(), anyOf(contains('흥'), contains('칫'), contains('사과')));
  });

  test('apology lifts the sulk', () async {
    await b.sendChat('바보야');
    await b.sendChat('미안해');
    expect(b.sulk.sulking, isFalse);
  });

  test('praise without an AI key gets a happy line', () async {
    await b.sendChat('너 진짜 귀엽다!');
    expect(b.sulk.sulking, isFalse);
    expect(lastPet(), isNotEmpty);
    expect(lastPet(), isNot(contains('설정 탭')));
  });

  test('sulking survives a restart', () async {
    await b.sendChat('바보야');
    final f = File('${tmp.path}/pet_state.json');
    for (var i = 0; i < 50 && !(f.existsSync() && f.readAsStringSync().contains('"sulking":true')); i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(jsonDecode(f.readAsStringSync())['sulk']['sulking'], isTrue);
    final again = PetBrain();
    await again.debugLoad();
    expect(again.sulk.sulking, isTrue);
    again.dispose();
  });

  test('English works too (2026-10-28): insult sulks, sorry lifts it', () async {
    Lang.code = 'en';
    await b.sendChat('you are stupid');
    expect(b.sulk.sulking, isTrue);
    expect(lastPet(), anyOf(contains('Hmph'), contains('Tsk')));
    await b.sendChat("I'm sorry");
    expect(b.sulk.sulking, isFalse);
  });

  test('typing preview never throws and ignores empty text', () {
    b.ownerTyping('');
    b.ownerTyping('오늘 날씨 어때?');
    b.ownerTyping('ㅋㅋㅋ');
  });
}
