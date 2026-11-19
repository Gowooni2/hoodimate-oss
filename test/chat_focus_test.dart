import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/widgets/chat_panel.dart';

void main() {
  testWidgets('input keeps focus after Enter so the next line can be typed', (t) async {
    final brain = PetBrain();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ChatPanel(brain: brain))));
    await t.pump();
    final field = find.byType(TextField).last;
    await t.tap(field);
    await t.enterText(field, '   '); // blank: the brain ignores it, so no bubble timers
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    final editable = t.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, isEmpty);
    await t.pump(const Duration(seconds: 2)); // let the scroll-to-bottom timers finish
    await t.pumpWidget(const SizedBox());
  });
}
