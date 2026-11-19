import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/speech_out.dart';

void main() {
  test('mouth shapes for Korean, English and pauses', () {
    expect(SpeechOut.shapeFor('가'), 'D'); // ㅏ wide
    expect(SpeechOut.shapeFor('고'), 'E'); // ㅗ round
    expect(SpeechOut.shapeFor('구'), 'F'); // ㅜ pucker
    expect(SpeechOut.shapeFor('마'), 'A'); // ㅁ closed lips
    expect(SpeechOut.shapeFor('m'), 'A');
    expect(SpeechOut.shapeFor('a'), 'D');
    expect(SpeechOut.shapeFor('o'), 'E');
    expect(SpeechOut.shapeFor(' '), 'X');
    expect(SpeechOut.shapeFor('!'), 'X');
  });

  test('emoji and links are not read', () {
    expect(SpeechOut.speakable('Hi! 😊 see https://x.com **now**'), 'Hi! see now');
  });

  test('timestamps become a shape timeline that ends at rest', () {
    final c = SpeechOut.cuesFromAlignment(['h', 'a', 'a', ' ', 'm'], [0, 0.1, 0.2, 0.3, 0.4]);
    expect(c.map((e) => e.$2), ['B', 'D', 'X', 'A', 'X']);
    expect(c.first.$1, 0);
  });
}
