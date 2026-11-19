import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/emoticons.dart';
import 'package:hoodimong/models/emotion_fx.dart';
import 'package:hoodimong/models/pet_state.dart';

void main() {
  test('every emoticon and every mood has lettering in all three languages', () {
    for (final e in Emoticons.basic.items) {
      final fx = EmotionFx.byEmoticon[e.id];
      expect(fx, isNotNull, reason: e.id);
      expect([fx!.ko, fx.en, fx.zh].every((t) => t.trim().isNotEmpty), isTrue, reason: e.id);
    }
    for (final m in PetMood.values) {
      expect(EmotionFx.byMood[m], isNotNull, reason: m.name);
    }
  });

  testWidgets('lettering renders', (t) async {
    await t.pumpWidget(MaterialApp(home: Center(child: FxText(EmotionFx.byEmoticon['yummy']!))));
    expect(find.text('냠냠쩝쩝!!').evaluate().isNotEmpty || find.text('Nom nom!!').evaluate().isNotEmpty, isTrue);
  });
}
