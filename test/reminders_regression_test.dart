import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/reminders.dart';

/// Everyday reminder sentences in all three languages must keep working
/// after the Chinese and weekday handling (audit 2026-10-11).
void main() {
  final now = DateTime(2026, 10, 10, 12); // Saturday noon
  DateTime? at(String s) => Reminders.parse(s, now)?.at;

  test('Korean', () {
    Lang.code = 'ko';
    expect(at('10분 뒤에 물 마시기'), now.add(const Duration(minutes: 10)));
    expect(at('1시간 뒤에 회의'), now.add(const Duration(hours: 1)));
    expect(at('30초 뒤 확인'), now.add(const Duration(seconds: 30)));
    expect(at('내일 오후 3시 치과'), DateTime(2026, 10, 11, 15));
    expect(at('오후 6시 반 운동'), DateTime(2026, 10, 10, 18, 30));
    expect(Reminders.parse('매일 9시 물 마시기', now)?.daily, isTrue);
  });

  test('English', () {
    Lang.code = 'en';
    expect(at('in 10 minutes drink water'), now.add(const Duration(minutes: 10)));
    expect(at('tomorrow at 3pm meeting'), DateTime(2026, 10, 11, 15));
    expect(at('at 6pm watch the sun set'), DateTime(2026, 10, 10, 18));
    expect(at('at 6:30pm wear sunscreen'), DateTime(2026, 10, 10, 18, 30));
    expect(Reminders.parse('every day at 9 drink water', now)?.daily, isTrue);
  });

  test('Chinese', () {
    Lang.code = 'zh';
    expect(at('10分钟后 喝水'), now.add(const Duration(minutes: 10)));
    expect(at('明天下午3点半 开会'), DateTime(2026, 10, 11, 15, 30));
  });

  test('weekdays are still refused in every language', () {
    expect(at('Friday 5pm deadline'), isNull);
    expect(at('on Mon at 9 standup'), isNull);
    expect(at('금요일 오후 5시 회의'), isNull);
    expect(at('星期五 下午5点 开会'), isNull);
  });
}
