import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/widgets/chat_panel.dart';

void main() {
  testWidgets('first cloud chat asks first, naming the provider and the area sent', (t) async {
    Lang.code = 'en';
    final brain = PetBrain();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ChatPanel(brain: brain))));
    await t.pump();
    expect(brain.askAiConsent, isNotNull);
    final answer = brain.askAiConsent!('Gemini');
    await t.pumpAndSettle();
    expect(find.text('Send chats to an AI?'), findsOneWidget);
    expect(find.textContaining('are sent to Gemini'), findsOneWidget);
    expect(find.textContaining('city, ZIP code, state, country'), findsOneWidget);
    await t.tap(find.text("Don't send"));
    await t.pumpAndSettle();
    expect(await answer, isFalse);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
