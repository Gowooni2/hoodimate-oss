import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';

void main() {
  test('birthday matches month and day only', () {
    final p = OwnerProfile(birthday: '03-14');
    expect(p.isBirthday(DateTime(2027, 3, 14, 9)), isTrue);
    expect(p.isBirthday(DateTime(2027, 3, 15)), isFalse);
    expect(OwnerProfile().isBirthday(DateTime(2027, 3, 14)), isFalse);
  });

  test('birthday survives a save round trip', () {
    final p = OwnerProfile(birthday: '12-01');
    final q = OwnerProfile()..fromJson(p.toJson());
    expect(q.birthday, '12-01');
  });
}
