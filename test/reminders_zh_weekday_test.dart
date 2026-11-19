import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/reminders.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  test('Chinese relative and absolute times parse', () {
    Lang.code = 'zh';
    expect(Reminders.parse('10分钟后 喝水', now)!.at, now.add(const Duration(minutes: 10)));
    expect(Reminders.parse('明天早上8点 起床', now)!.at, DateTime(2026, 10, 11, 8));
    expect(Reminders.parse('下午3点半 开会', now)!.at, DateTime(2026, 10, 10, 15, 30));
  });
  test('weekday names are refused, not silently mis-dated', () {
    expect(Reminders.parse('Friday 17:00 deadline', now), isNull);
    expect(Reminders.parse('금요일 5시 회의', now), isNull);
    expect(Reminders.parse('周五 8:00 提醒', now), isNull);
  });
}
