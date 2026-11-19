import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/widgets/tracking_eyes.dart';

/// Renders the chat close-up face with the eyes looking in a few
/// directions and writes a PNG for visual review (test/tmp/face.png).
void main() {
  testWidgets('face view renders eyes following the gaze', (tester) async {
    final key = GlobalKey();
    const gazes = [Offset(-1, 0), Offset(0, 0), Offset(1, -0.6), Offset(0.7, -0.8)];
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Container(
          color: Colors.white,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < gazes.length; i++)
                Padding(padding: const EdgeInsets.all(8), child: FaceView(width: 170, gaze: gazes[i], talking: i == 3)),
            ],
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        final img = (e.widget as Image).image;
        await precacheImage(img, e);
      }
    });
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('test/tmp/face.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // dispose blink timers
  });
}
