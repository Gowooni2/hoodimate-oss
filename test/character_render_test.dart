import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/character.dart';
import 'package:hoodimong/widgets/tracking_eyes.dart';

/// Each character pack with its live eyes (left, center, up-right, talking)
/// -> test/tmp/character_<id>.png for visual review.
void main() {
  testWidgets('character packs draw their eyes in place', (tester) async {
    tester.view.physicalSize = const Size(1500, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => Character.load());
    final packs = [...Character.available];
    expect(packs, isNotEmpty);
    const gazes = [Offset(-1, 0), Offset(0, 0), Offset(1, -0.8)];
    final talking = ValueNotifier<String?>('D');
    for (final c in packs) {
      Character.current = c;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                  key: key,
                  child: Container(
                      color: const Color(0xFFDDDDDD),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final g in gazes) TrackingEyesSprite(size: 150, gaze: g),
                        TrackingEyesSprite(size: 150, gaze: Offset.zero, mouth: talking),
                        if (!c.hasMouth)
                          for (final l in [EyeLook.happy, EyeLook.sad, EyeLook.bored, EyeLook.surprised])
                            TrackingEyesSprite(size: 150, gaze: const Offset(0.3, 0), look: l),
                      ]))))));
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('test/tmp/character_${c.id}.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    }
    expect(tester.takeException(), isNull);
  });
}
