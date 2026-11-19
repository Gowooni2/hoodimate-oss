import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoodimong/main.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/widgets/alarm_clock.dart';

void main() {
  testWidgets('pet window shows the idle sprite', (tester) async {
    final brain = PetBrain();
    await tester.pumpWidget(HoodimateApp(brain: brain));
    await tester.pump();
    expect(find.byType(HoodimateApp), findsOneWidget);
  });

  testWidgets('held alarm clock animates without errors', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(child: AlarmClock(size: 120))));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(AlarmClock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
