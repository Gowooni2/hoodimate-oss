import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/reminders.dart';

/// English reminder commands (the app runs in English for non-Korean users).
void main() {
  final now = DateTime(2026, 10, 5, 15, 0);
  setUp(() => Lang.ko = false);
  tearDown(() => Lang.ko = false);

  test('relative, absolute, tomorrow and daily phrasing', () {
    final r = Reminders();
    expect(r.handle('remind me to drink water in 10 minutes', now), contains('drink water'));
    expect(r.items.last.at, DateTime(2026, 10, 5, 15, 10));
    expect(r.handle('set an alarm for 6pm', now), contains('6:00 PM'));
    expect(r.items.last.text, 'Alarm');
    r.handle('remind me tomorrow at 9am to call mom', now);
    expect(r.items.last.at, DateTime(2026, 10, 6, 9, 0));
    expect(r.items.last.text, 'call mom');
    r.handle('/remind 18:30 take medicine', now);
    expect(r.items.last.text, 'take medicine');
    r.handle('wake me up in 1 hour 30 minutes', now);
    expect(r.items.last.at, DateTime(2026, 10, 5, 16, 30));
    r.handle('/remind every day 9am stretch', now);
    expect(r.items.last.daily, isTrue);
    expect(r.items.last.text, 'stretch');
  });

  test('questions stay with the AI; missing time gets a hint', () {
    final r = Reminders();
    expect(r.handle('what should I do in 10 minutes?', now), isNull);
    expect(r.handle('set an alarm', now), contains('When should it ring'));
    expect(r.items, isEmpty);
  });

  test('list and cancel in English', () {
    final r = Reminders()..handle('/remind 18:30 take medicine', now);
    expect(r.handle('/remind list', now), contains('1. today 6:30 PM - take medicine'));
    expect(r.handle('/remind cancel 1', now), contains('Cancelled'));
    expect(r.items, isEmpty);
  });
}
