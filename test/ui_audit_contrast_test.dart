// WCAG contrast of the 7 panel themes (informational thresholds: label >= 4.5, dim label >= 3.0).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/panel_theme.dart';

double ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('panel theme contrast', () {
    final low = <String>[];
    for (final t in PanelTheme.all) {
      final sel = ratio(t.label, Colors.white); // selected tab: label on white pill
      final dim = ratio(t.tabDim, t.tabBg); // unselected tab label on tab bar
      final txtUser = ratio(Colors.black87, t.userBubble);
      // ignore: avoid_print
      print('${t.id}: selected ${sel.toStringAsFixed(2)}  unselected ${dim.toStringAsFixed(2)}  userBubble ${txtUser.toStringAsFixed(2)}');
      if (sel < 4.5) low.add('${t.id} selected tab label $sel');
      if (dim < 3.0) low.add('${t.id} unselected tab label ${dim.toStringAsFixed(2)}');
      if (txtUser < 4.5) low.add('${t.id} user bubble text $txtUser');
    }
    expect(low, isEmpty, reason: low.join('; '));
  });
}
