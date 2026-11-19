import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/widgets/pet_window.dart';

void main() {
  test('a quick left-right shake counts, slow drifts and small jitters do not', () {
    expect(isMouseShake([0, 80, 0, 80, 0, 80, 0]), isTrue);
    expect(isMouseShake([0, 40, 80, 120, 160, 200]), isFalse); // one direction
    expect(isMouseShake([0, 3, 0, 3, 0, 3, 0, 3]), isFalse); // jitter
    expect(isMouseShake([0, 30, 0, 30, 0]), isFalse); // too little travel
  });
}
