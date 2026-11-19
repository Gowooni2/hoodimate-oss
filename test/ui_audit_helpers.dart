import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/character.dart';
import 'package:hoodimong/models/emotion_fx.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';

/// Shared setup for the ui_audit_* tests: sandboxed app-support dir (so the
/// real container is never touched), real bundled fonts + Roboto metrics.
Directory? _tmp;

Future<void> auditSetUp(WidgetTester t) async {
  _tmp ??= Directory.systemTemp.createTempSync('ui_audit_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => _tmp!.path);
  for (final ch in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }
  await t.runAsync(() async {
    for (final (family, file) in [
      ('Jua', 'assets/fonts/Jua-Regular.ttf'),
      ('ZCOOLKuaiLe', 'assets/fonts/ZCOOLKuaiLe-Regular.ttf'),
    ]) {
      final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
      await l.load();
    }
    final home = Platform.environment['HOME'] ?? '';
    final roboto = File('$home/flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    final bold = File('$home/flutter-sdk/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf');
    if (roboto.existsSync()) {
      final l = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(roboto.readAsBytesSync())));
      if (bold.existsSync()) l.addFont(Future.value(ByteData.sublistView(bold.readAsBytesSync())));
      await l.load();
    }
    await Character.load('mongsil');
  });
}

void setView(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1.0;
}

ThemeData auditTheme() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5E6C8)),
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['Jua', 'ZCOOLKuaiLe']);

Widget host(Widget child, {Size? size, Color? bg}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: auditTheme(),
    home: Scaffold(
        backgroundColor: bg ?? Colors.white,
        body: Align(
            alignment: Alignment.topLeft,
            child: size == null ? child : SizedBox(width: size.width, height: size.height, child: child))));

const langs = ['ko', 'en', 'zh'];
const scales = [0.85, 1.0, 1.5];
const sizes = <String, Size>{'min': Size(300, 280), 'default': Size(340, 370), 'max': Size(900, 1000)};

/// What a tab body actually gets inside PetWindow's panel container:
/// 1.5px border on each side and a 36px tab bar + 10 top / 2 bottom margin.
Size tabBody(Size panel) => Size(panel.width - 3, panel.height - 3 - 48);

void resetGlobals() {
  Lang.code = 'en';
  CuteFont.scale = 1.0;
  CuteFont.cute = true;
}

/// Drain timers the panels start (scroll-to-bottom, bubbles).
Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 3));
}

PetBrain newBrain() => PetBrain();

/// audioplayers opens per-player event channels we cannot mock by name; drop
/// only those MissingPluginException reports and forward everything else.
void ignoreMissingPlugins() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('MissingPluginException')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}
