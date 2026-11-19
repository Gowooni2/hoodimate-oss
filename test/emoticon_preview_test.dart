import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/character.dart';
import 'package:hoodimong/models/emoticons.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/widgets/sticker.dart';

/// Contact sheet of the basic pack with lettering, one per language:
/// test/tmp/emoticons_<lang>.png (for eyeballing, not an assertion).
void main() {
  testWidgets('emoticon sheet', (tester) async {
    await tester.runAsync(() async {
      for (final (family, file) in [('Jua', 'Jua-Regular.ttf'), ('ZCOOLKuaiLe', 'ZCOOLKuaiLe-Regular.ttf')]) {
        final l = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync())));
        await l.load();
      }
      await Character.load('mongsil');
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final lang in ['ko', 'en', 'zh']) {
      Lang.code = lang;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Material(color: Colors.white, child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                  key: key,
                  child: Container(
                      color: Colors.white,
                      width: 1200,
                      padding: const EdgeInsets.all(12),
                      child: Wrap(spacing: 14, runSpacing: 14, children: [
                        for (final e in Emoticons.basic.items) StickerView(e, size: 130),
                      ])))))));
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('test/tmp/emoticons_$lang.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    }
  });
}
