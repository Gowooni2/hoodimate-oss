import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/emotion_fx.dart';
import 'package:hoodimong/models/panel_theme.dart';
import 'package:hoodimong/models/profile.dart';

void main() {
  test('unknown theme falls back to cream; font choice changes the style', () {
    expect(PanelTheme.byId('nope').id, 'cream');
    CuteFont.cute = true;
    CuteFont.scale = 1.2;
    expect(CuteFont.style(size: 10).fontFamily, isNotNull);
    expect(CuteFont.style(size: 10).fontSize, closeTo(12, 0.001));
    CuteFont.cute = false;
    expect(CuteFont.style(size: 10).fontFamily, isNull);
    CuteFont.cute = true;
    CuteFont.scale = 1.0;
  });

  // Swatch sheet for eyeballing: test/tmp/panel_themes.png
  testWidgets('theme sheet', (tester) async {
    await tester.runAsync(() async {
      for (final (family, file) in [('Jua', 'Jua-Regular.ttf'), ('ZCOOLKuaiLe', 'ZCOOLKuaiLe-Regular.ttf')]) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()))))
            .load();
      }
    });
    Lang.code = 'ko';
    tester.view.physicalSize = const Size(1400, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    Widget card(PanelTheme t) => Container(
          width: 185,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: t.bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.border, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.tabBg, borderRadius: BorderRadius.circular(13)),
                child: Text('💬 대화  ${t.name}', style: TextStyle(color: t.label, fontSize: 12, fontWeight: FontWeight.w800))),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerRight,
                child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: t.userBubble, borderRadius: BorderRadius.circular(12)),
                    child: Text('오늘 날씨 어때?', style: CuteFont.style(size: 13.5)))),
            const SizedBox(height: 6),
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: t.petBubble, borderRadius: BorderRadius.circular(12)),
                child: Text('맑고 따뜻해! 산책 가자~', style: CuteFont.style(size: 13.5))),
          ]),
        );
    await tester.pumpWidget(MaterialApp(
        home: Material(
            color: Colors.white,
            child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                    key: key,
                    child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final t in PanelTheme.all) Padding(padding: const EdgeInsets.only(right: 10), child: card(t)),
                        ])))))));
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('test/tmp/panel_themes.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
