import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

// Owner (2026-10-12): a switch for people who don't want emoticons on replies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late PetBrain b;

  setUp(() {
    for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    Lang.code = 'en';
    tmp = Directory.systemTemp.createTempSync('reply_stickers');
    PathProviderPlatform.instance = _Paths(tmp.path);
    b = PetBrain();
  });
  tearDown(() {
    b.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('on by default, and an old state file without the key keeps it on', () async {
    expect(b.replyStickers, isTrue);
    File('${tmp.path}/pet_state.json').writeAsStringSync(jsonEncode({'hunger': 50}));
    await b.debugLoad();
    expect(b.replyStickers, isTrue);
  });

  test('turning it off is saved and loaded back', () async {
    b.setReplyStickers(false);
    final f = File('${tmp.path}/pet_state.json');
    for (var i = 0; i < 50 && !(f.existsSync() && f.readAsStringSync().contains('replyStickers')); i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(jsonDecode(f.readAsStringSync())['replyStickers'], isFalse);
    final again = PetBrain();
    await again.debugLoad();
    expect(again.replyStickers, isFalse);
    again.dispose();
  });

  test('a per-Mac choice: not carried by sync', () {
    expect(SyncMerge.localOnly, contains('replyStickers'));
  });
}
