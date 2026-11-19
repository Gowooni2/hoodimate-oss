import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/emotion_fx.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/widgets/pet_window.dart';

// Store-page review (2026-10-12): "I’ m" (Jua has no ’, the wide CJK
// fallback drew it) and bubble text spilling out of the box at 140 %.
void main() {
  tearDown(() {
    Lang.code = 'en';
    CuteFont.cute = true;
    CuteFont.scale = 1.0;
  });

  test('cute font: punctuation Jua lacks becomes Jua glyphs', () {
    Lang.code = 'en';
    expect(CuteFont.fit('I’m here… Let‘s go — now – ok'), "I'm here... Let's go - now - ok");
    Lang.code = 'ko';
    expect(CuteFont.fit('좋아… 그치’'), "좋아... 그치'");
  });

  test('system font and Chinese (ZCOOL has the glyphs) keep the text', () {
    CuteFont.cute = false;
    expect(CuteFont.fit('I’m…'), 'I’m…');
    CuteFont.cute = true;
    Lang.code = 'zh';
    expect(CuteFont.fit('好的…'), '好的…');
  });

  test('bubble lines always fit inside the box', () {
    for (final s in [0.85, 1.0, 1.2, 1.4, 1.5]) {
      CuteFont.scale = s;
      for (final cute in [true, false]) {
        CuteFont.cute = cute;
        final style = CuteFont.style(size: 13.5);
        final lineH = style.fontSize! * style.height!;
        for (final lettering in [false, true]) {
          final n = PetLayout.bubbleLines(style, lettering: lettering);
          final used = 24 + (lettering ? 16 : 0) + n * lineH;
          expect(used, lessThanOrEqualTo(PetLayout.bubbleH), reason: 'scale $s cute $cute fx $lettering');
          expect(n, greaterThanOrEqualTo(lettering ? 1 : 2), reason: 'scale $s cute $cute fx $lettering');
        }
      }
    }
  });

  test('bubble row grows with the text size', () {
    CuteFont.scale = 1.0;
    expect(PetLayout.bubbleH, 72);
    CuteFont.scale = 1.4;
    expect(PetLayout.bubbleH, closeTo(100.8, 0.01));
  });
}
