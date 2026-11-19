// Pumps Chat/Care/Settings at min/default/max panel size for ko/en/zh and
// font scale 0.85/1.0/1.5 and fails on any FlutterError (RenderFlex overflow...).
// Run for each edition:  flutter test test/ui_audit_overflow_test.dart [--dart-define=EDITION=store|lite]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/emotion_fx.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/widgets/care_panel.dart';
import 'package:hoodimong/widgets/chat_panel.dart';
import 'package:hoodimong/widgets/settings_panel.dart';

import 'ui_audit_helpers.dart';

void main() {
  final failures = <String>[];

  Future<void> check(WidgetTester t, String label, Widget Function() build, {bool scrollSettings = false}) async {
    final brain = newBrain();
    final errs = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => errs.add(d.exceptionAsString().split('\n').first);
    addTearDown(() => FlutterError.onError = prev);
    await t.pumpWidget(host(build(), size: tabBody(sizes[label.split('/')[1]]!)));
    await settle(t);
    if (scrollSettings) {
      final sc = find.byType(Scrollable);
      if (sc.evaluate().isNotEmpty) {
        final s = t.state<ScrollableState>(sc.first);
        s.position.jumpTo(s.position.maxScrollExtent);
        await t.pump();
      }
    }
    for (final e in errs.toSet()) {
      failures.add('$label: $e');
    }
    FlutterError.onError = prev;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    brain.dispose();
  }

  testWidgets('no overflow: ${Ed.current.name}', (t) async {
    await auditSetUp(t);
    for (final sizeKey in sizes.keys) {
      setView(t, const Size(1000, 1100));
      for (final lang in langs) {
        for (final sc in scales) {
          Lang.code = lang;
          CuteFont.scale = sc;
          final tag = '$lang/$sizeKey/x$sc';
          final b1 = newBrain();
          await check(t, 'chat/$sizeKey/$lang/x$sc', () => ChatPanel(brain: b1));
          await check(t, 'care/$sizeKey/$lang/x$sc', () => CarePanel(brain: b1));
          await check(t, 'settings/$sizeKey/$lang/x$sc', () => SettingsPanel(brain: b1), scrollSettings: true);
          b1.dispose();
          // ignore: unused_local_variable
          final _ = tag;
        }
      }
    }
    resetGlobals();
    // ignore: avoid_print
    print('EDITION=${Ed.current.name} failures=${failures.length}');
    for (final f in failures) {
      // ignore: avoid_print
      print('FAIL $f');
    }
    expect(failures, isEmpty);
  });
}
