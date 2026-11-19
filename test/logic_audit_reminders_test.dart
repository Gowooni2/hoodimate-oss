import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:http/testing.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:hoodimong/services/reminders.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// Pure parsing of reminders in Korean / English / Chinese, midnight and DST
/// edges, past times, list / cancel, persistence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 5, 15, 0); // Monday 3 PM
  setUp(() => Lang.code = 'en');
  tearDown(() => Lang.code = 'en');

  Reminder one(String s, {DateTime? at, String lang = 'en'}) {
    Lang.code = lang;
    final r = Reminders();
    final out = r.handle(s, at ?? now);
    expect(out, isNotNull, reason: 'not handled: $s');
    expect(r.items, hasLength(1), reason: '"$s" -> $out');
    return r.items.single;
  }

  group('Korean', () {
    test('relative forms', () {
      expect(one('10분 뒤에 알려줘', lang: 'ko').at, DateTime(2026, 10, 5, 15, 10));
      expect(one('10분 뒤에 빨래 꺼내라고 알려줘', lang: 'ko').text, '빨래 꺼내기');
      expect(one('1시간 반 후에 알림 산책', lang: 'ko').at, DateTime(2026, 10, 5, 16, 30));
      expect(one('2시간 30분 뒤에 알려줘', lang: 'ko').at, DateTime(2026, 10, 5, 17, 30));
      expect(one('30분 있다가 알려줘', lang: 'ko').at, DateTime(2026, 10, 5, 15, 30));
      expect(one('90초 뒤에 알려줘', lang: 'ko').at, DateTime(2026, 10, 5, 15, 1, 30));
    });

    test('absolute with 오전/오후/아침/저녁/새벽', () {
      expect(one('내일 오후 3시에 회의 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 15));
      expect(one('내일 아침 7시에 깨워줘', lang: 'ko').at, DateTime(2026, 10, 6, 7));
      expect(one('모레 오후 2시 30분 병원 알림', lang: 'ko').at, DateTime(2026, 10, 7, 14, 30));
      expect(one('새벽 1시에 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 1));
      expect(one('오후 3시 반에 알려줘', lang: 'ko').at, DateTime(2026, 10, 5, 15, 30));
    });

    test('"내일 오후 3시" alone is not a command (needs a trigger word)', () {
      expect(Reminders().handle('내일 오후 3시', now), isNull);
      expect(Reminders().handle('오늘 날씨 알려줘', now), isNull);
      expect(Reminders().handle('지금 몇시야 알려줘', now), isNull);
      expect(Reminders().handle('10분 뒤에 뭐 하지?', now), isNull);
    });

    test('midnight and noon: 밤 12시 is 00:00, 오후 12시 is 12:00, 오전 12시 is 00:00', () {
      expect(one('밤 12시에 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 0, 0), reason: '밤 12시 = midnight, not noon');
      expect(one('새벽 12시에 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 0, 0));
      expect(one('오후 12시에 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 12, 0));
      expect(one('오전 12시에 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 0, 0));
      expect(one('0시에 알려줘', lang: 'ko').at, DateTime(2026, 10, 6, 0, 0));
    });

    test('invalid clock values are not scheduled', () {
      for (final s in ['24시에 알려줘', '25:00에 알려줘', '3시 70분에 알려줘', 'remind me at 25:00', 'remind me at 24:00']) {
        final r = Reminders();
        final out = r.handle(s, now);
        expect(r.items, isEmpty, reason: s);
        expect(out, anyOf(isNull, isNotEmpty));
      }
    });

    test('"N일 뒤/후" is honoured, not silently dropped', () {
      final r = one('3일 후 오전 9시에 알려줘', lang: 'ko');
      expect(r.at, DateTime(2026, 10, 8, 9), reason: 'was scheduled for ${r.at}');
    });

    test('weekday / calendar-date words must not silently fall back to today', () {
      for (final s in ['다음 주 월요일 9시에 알려줘', '3월 5일 오후 3시에 알려줘', 'remind me on Friday at 5pm', 'remind me next week at 9am']) {
        final r = Reminders();
        r.handle(s, now);
        // Either understood properly (not today) or refused with the hint.
        if (r.items.isNotEmpty) {
          expect(r.items.single.at.day, isNot(5), reason: '"$s" scheduled for today: ${r.items.single.at}');
        }
      }
    });

    test('daily ambiguous hour does not depend on when it was typed', () {
      final a = one('매일 9시 물 마시기 알림', at: DateTime(2026, 10, 5, 8, 0), lang: 'ko');
      final b = one('매일 9시 물 마시기 알림', at: DateTime(2026, 10, 5, 15, 0), lang: 'ko');
      expect(a.at.hour, b.at.hour, reason: 'daily "9시" fires at ${a.at.hour}:00 when typed at 8 AM but ${b.at.hour}:00 when typed at 3 PM');
    });

    test('daily keeps its flag and text', () {
      final r = one('매일 아침 8시에 약 먹으라고 알려줘', lang: 'ko');
      expect(r.daily, isTrue);
      expect(r.at.hour, 8);
      expect(r.text, '약 먹기');
    });

    test('"매일 10분 뒤" is one-off', () {
      final r = Reminders()..handle('매일 10분 뒤 스트레칭 알려줘', now);
      expect(r.items.single.daily, isFalse);
    });

    test('timer wording', () {
      expect(one('5분 타이머 맞춰줘', lang: 'ko').at, DateTime(2026, 10, 5, 15, 5));
      expect(one('타이머 5분', lang: 'ko').at, DateTime(2026, 10, 5, 15, 5));
    });
  });

  group('English', () {
    test('basic relative phrasing', () {
      expect(one('remind me in 10 minutes').at, DateTime(2026, 10, 5, 15, 10));
      expect(one('remind me in an hour').at, DateTime(2026, 10, 5, 16));
      expect(one('remind me in 2 hours').at, DateTime(2026, 10, 5, 17));
      expect(one('10 minutes later remind me').at, DateTime(2026, 10, 5, 15, 10));
      expect(one('remind me in 90 seconds to blink').text, 'blink');
    });

    test('"in a minute" works like "in an hour"', () {
      expect(one('remind me in a minute').at, DateTime(2026, 10, 5, 15, 1));
    });

    test('"in half an hour"', () {
      expect(one('remind me in half an hour').at, DateTime(2026, 10, 5, 15, 30));
    });

    test('bare hour after "at": "remind me at 5", "wake me at 7", "every day at 9"', () {
      expect(one('remind me at 5').at, DateTime(2026, 10, 5, 17));
      expect(one('wake me at 7').at.hour % 12, 7, reason: 'ambiguous AM/PM: 07:00 or 19:00 are both fine');
    });

    test('"/remind every day at 9" is accepted', () {
      final r = Reminders();
      final out = r.handle('/remind every day at 9', now);
      expect(r.items, hasLength(1), reason: out);
      expect(r.items.single.daily, isTrue);
    });

    test('am / pm / noon / midnight spellings', () {
      expect(one('remind me at 5PM').at, DateTime(2026, 10, 5, 17));
      expect(one('remind me at 5 pm').at, DateTime(2026, 10, 5, 17));
      expect(one('remind me at 12am').at, DateTime(2026, 10, 6, 0));
      expect(one('remind me at 12pm').at, DateTime(2026, 10, 6, 12));
      expect(one('remind me at 5 p.m.').at, DateTime(2026, 10, 5, 17));
      expect(one('remind me at noon').at, DateTime(2026, 10, 6, 12));
      expect(one('remind me at midnight').at, DateTime(2026, 10, 6, 0));
    });

    test('day word AFTER the time is honoured and not left in the text', () {
      final r = one('remind me at 3pm tomorrow to call mom');
      expect(r.at, DateTime(2026, 10, 6, 15));
      expect(r.text, 'call mom');
      final r2 = one('alarm 7:30am tomorrow');
      expect(r2.at, DateTime(2026, 10, 6, 7, 30));
      expect(r2.text.contains('내일'), isFalse, reason: 'Korean token leaked into English text: ${r2.text}');
    });

    test('"today at 3pm" typed at 3:00:00 sharp rolls to tomorrow, 1 s earlier does not', () {
      expect(one('remind me today at 3pm').at, DateTime(2026, 10, 6, 15));
      expect(one('remind me today at 3pm', at: DateTime(2026, 10, 5, 14, 59, 59)).at, DateTime(2026, 10, 5, 15));
    });

    test('leading-zero 24-hour clock', () {
      expect(one('/remind 07:30 pills').at, DateTime(2026, 10, 6, 7, 30), reason: '07:30 is a 24h time; 3 PM today -> tomorrow 07:30');
      expect(one('/remind 00:00 pills').at, DateTime(2026, 10, 6, 0, 0));
      expect(one('/remind 18:30 take medicine').at, DateTime(2026, 10, 5, 18, 30));
    });

    test('timer', () {
      expect(one('set a timer for 5 minutes').at, DateTime(2026, 10, 5, 15, 5));
    });

    test('"cancelled", "delete files" etc. after /remind are reminders, not cancel commands', () {
      final r = Reminders();
      r.handle('/remind cancelled party at 5pm', now);
      expect(r.items, hasLength(1));
      final r2 = Reminders();
      r2.handle('/remind delete old files 18:00', now);
      expect(r2.items, hasLength(1));
    });

    test('questions and chit-chat go to the AI', () {
      for (final s in ['what should I do in 10 minutes?', 'hello', 'I will be there at 5', 'tell me about alarm clocks in history']) {
        expect(Reminders().handle(s, now), isNull, reason: s);
      }
    });

    test('missing time gets a hint, nothing is scheduled', () {
      final r = Reminders();
      expect(r.handle('remind me tomorrow', now), contains('When should it ring'));
      expect(r.handle('set an alarm', now), contains('When should it ring'));
      expect(r.items, isEmpty);
    });
  });

  group('Chinese', () {
    test('relative: "10分钟后提醒我喝水"', () {
      final r = one('10分钟后提醒我喝水', lang: 'zh');
      expect(r.at, DateTime(2026, 10, 5, 15, 10));
      expect(r.text, contains('喝水'));
      expect(r.text.contains('提醒'), isFalse);
    });
    test('absolute with 明天/下午/点', () {
      expect(one('明天下午3点提醒我开会', lang: 'zh').at, DateTime(2026, 10, 6, 15));
      expect(one('提醒我晚上8点半吃药', lang: 'zh').at, DateTime(2026, 10, 5, 20, 30));
      expect(one('每天早上9点提醒我喝水', lang: 'zh').daily, isTrue);
    });
    test('hours, seconds, 闹钟 and 叫我', () {
      expect(one('1小时后提醒我', lang: 'zh').at, DateTime(2026, 10, 5, 16));
      expect(one('30秒后提醒我', lang: 'zh').at, DateTime(2026, 10, 5, 15, 0, 30));
      expect(one('明天早上7点叫我起床', lang: 'zh').at, DateTime(2026, 10, 6, 7));
      expect(one('设个闹钟 18:30', lang: 'zh').at, DateTime(2026, 10, 5, 18, 30));
    });
    test('Chinese chit-chat is not a reminder', () {
      expect(Reminders().handle('明天天气怎么样', now), isNull);
      expect(Reminders().handle('你好', now), isNull);
    });
    test('reply is Chinese', () {
      Lang.code = 'zh';
      final r = Reminders();
      expect(r.handle('10分钟后提醒我喝水', now), contains('提醒'));
    });
  });

  group('range, midnight, DST', () {
    test('absurd relative values are rejected, not scheduled in year 154391', () {
      final r = Reminders();
      r.handle('99999999999999분 뒤에 알려줘', now);
      for (final i in r.items) {
        expect(i.at.difference(now).inDays, lessThan(400), reason: '${i.at}');
      }
      expect(() => Reminders().handle('99999999999999999999999분 뒤에 알려줘', now), returnsNormally);
      expect(() => Reminders().handle('remind me in 999999999999999 hours', now), returnsNormally);
    });

    test('exactly midnight and one second to midnight', () {
      final r = one('내일 오전 12시 알려줘', at: DateTime(2026, 10, 5, 23, 59, 59), lang: 'ko');
      expect(r.at, DateTime(2026, 10, 6, 0, 0)); // "tomorrow midnight" typed just before midnight is the NEXT midnight
      final r2 = one('오전 12시 알려줘', at: DateTime(2026, 10, 5, 23, 59, 59), lang: 'ko');
      expect(r2.at, DateTime(2026, 10, 6, 0, 0));
      final r3 = one('오전 12시 알려줘', at: DateTime(2026, 10, 6, 0, 0, 0), lang: 'ko');
      expect(r3.at, DateTime(2026, 10, 7, 0, 0), reason: 'at exactly 00:00:00 the alarm is for the next midnight');
    });

    test('year / month / leap boundaries', () {
      expect(one('내일 오전 9시 알려줘', at: DateTime(2026, 12, 31, 23, 0), lang: 'ko').at, DateTime(2027, 1, 1, 9));
      expect(one('모레 오전 9시 알려줘', at: DateTime(2028, 2, 28, 12, 0), lang: 'ko').at, DateTime(2028, 3, 1, 9));
      expect(one('내일 오전 9시 알려줘', at: DateTime(2026, 2, 28, 12, 0), lang: 'ko').at, DateTime(2026, 3, 1, 9));
    });

    // Finds a real DST transition in the machine's zone; skipped (loudly) in UTC.
    DateTime? findSpringForward() {
      for (var d = DateTime(2026, 1, 1); d.year == 2026; d = d.add(const Duration(days: 1))) {
        final a = DateTime(d.year, d.month, d.day, 12).timeZoneOffset;
        final b = DateTime(d.year, d.month, d.day + 1, 12).timeZoneOffset;
        if (a != b) return DateTime(d.year, d.month, d.day);
      }
      return null;
    }

    test('a one-off for "9시" typed after 9 on the day before a DST change lands on 9:00 wall-clock', () {
      final d = findSpringForward();
      if (d == null) {
        markTestSkipped('no DST in ${DateTime.now().timeZoneName}');
        return;
      }
      final typed = DateTime(d.year, d.month, d.day, 22, 0);
      final r = one('오전 9시 알려줘', at: typed, lang: 'ko');
      expect(r.at.hour, 9, reason: 'wall-clock 9:00 expected, got ${r.at} (the +24h add drifts across DST)');
      expect(r.at.minute, 0);
    });

    test('a daily reminder keeps its wall-clock time across a DST change', () {
      final d = findSpringForward();
      if (d == null) {
        markTestSkipped('no DST in ${DateTime.now().timeZoneName}');
        return;
      }
      final r = Reminders()..loadJson([
          {'id': 1, 'at': DateTime(d.year, d.month, d.day, 9).toIso8601String(), 'text': 'water', 'daily': true}
        ]);
      final fired = r.takeDue(DateTime(d.year, d.month, d.day, 9, 1));
      expect(fired, hasLength(1));
      expect(r.items.single.at.hour, 9, reason: 'next day is ${r.items.single.at}; a daily 9:00 alarm drifted by an hour');
      // and a week later
      r.takeDue(DateTime(d.year, d.month, d.day + 7, 9, 1));
      expect(r.items.single.at.hour, 9);
    });

    test('a nonexistent local time (spring-forward gap) never schedules in the past', () {
      final d = findSpringForward();
      if (d == null) {
        markTestSkipped('no DST');
        return;
      }
      final typed = DateTime(d.year, d.month, d.day, 0, 30);
      final r = Reminders();
      r.handle('오전 2시 30분 알려줘', typed);
      for (final i in r.items) {
        expect(i.at.isAfter(typed), isTrue);
      }
    });
  });

  group('list / cancel / due', () {
    Reminders three() => Reminders()
      ..handle('/remind 18:30 b', now)
      ..handle('/remind 17:00 a', now)
      ..handle('/remind 20:00 c', now);

    test('numbers in list are the same numbers cancel uses (time order, not insertion order)', () {
      final r = three();
      final list = r.listText(now);
      expect(list, contains('1. today 5:00 PM - a'));
      expect(list, contains('2. today 6:30 PM - b'));
      expect(r.handle('/remind cancel 2', now), contains('"b"'));
      expect(r.items.map((e) => e.text), ['a', 'c']);
    });

    test('cancel out of range / zero / negative / junk', () {
      final r = three();
      for (final s in ['/remind cancel 0', '/remind cancel 4', '/remind cancel 99999999999999999999', '/remind cancel -1', '/remind cancel x']) {
        final out = r.handle(s, now);
        expect(out, isNotNull, reason: s);
        expect(r.items, hasLength(3), reason: s);
      }
    });

    test('cancel all, any case; Korean words', () {
      final r = three();
      expect(r.handle('/remind CANCEL ALL', now), contains('3'));
      expect(r.items, isEmpty);
      final k = three();
      k.handle('/알림 취소 전부', now);
      expect(k.items, isEmpty);
      expect(Reminders().handle('/알림 취소', now), isNotNull);
    });

    test('bare slash command lists', () {
      expect(Reminders().handle('/remind', now), contains('No reminders'));
      expect(three().handle('/알림', now), contains('1.'));
    });

    test('takeDue: one-offs removed, daily rolled to the future, due time reported', () {
      final r = Reminders()
        ..handle('/remind 16:00 once', now)
        ..handle('/remind every day 16:00 water', now);
      final due = r.takeDue(DateTime(2026, 10, 8, 16, 0, 1)); // 3 days later (app was closed)
      expect(due.map((e) => e.text).toSet(), {'once', 'water'});
      expect(due.every((e) => e.at.day == 5), isTrue);
      expect(r.items, hasLength(1));
      expect(r.items.single.at.isAfter(DateTime(2026, 10, 8, 16, 0, 1)), isTrue);
      expect(r.items.single.at.hour, 16);
    });

    test('takeDue with exactly-now and not-yet', () {
      final r = Reminders()..handle('/remind 16:00 once', now);
      expect(r.takeDue(DateTime(2026, 10, 5, 15, 59, 59)), isEmpty);
      expect(r.takeDue(DateTime(2026, 10, 5, 16, 0, 0)), hasLength(1));
    });

    test('daily whose stored time is absurdly old does not hang', () {
      final r = Reminders()..loadJson([{'id': 1, 'at': '0001-01-01T09:00:00', 'text': 'x', 'daily': true}]);
      final sw = Stopwatch()..start();
      r.takeDue(now);
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(r.items.single.at.isAfter(now), isTrue);
    });

    test('promptLine caps at 5 and is null when empty', () {
      expect(Reminders().promptLine(now), isNull);
      final r = Reminders();
      for (var i = 0; i < 9; i++) {
        r.handle('/remind ${10 + i}:00 t$i', now);
      }
      expect(r.promptLine(now)!.split(', ').length, 5);
    });
  });

  group('persistence', () {
    test('JSON round trip and next id', () {
      final r = Reminders()..handle('/remind 18:30 a', now)..handle('/remind every day 9am b', now);
      final j = jsonDecode(jsonEncode(r.toJson())) as List;
      final back = Reminders()..loadJson(j);
      expect(back.items.map((e) => [e.id, e.text, e.daily]), r.items.map((e) => [e.id, e.text, e.daily]));
      back.handle('/remind 21:00 c', now);
      expect(back.items.map((e) => e.id).toSet().length, 3);
    });

    test('loadJson tolerates junk entries (from a synced file)', () {
      final r = Reminders();
      r.loadJson([
        null,
        5,
        'x',
        {'at': 'not a date'},
        {'id': 'abc', 'at': '2026-10-05T18:00:00', 'text': null},
        {'id': 2, 'at': '2026-10-05T19:00:00', 'text': 'ok', 'daily': 'yes'},
        {'id': 3.7, 'at': '2026-10-05T19:00:00Z', 'text': 'utc'},
      ]);
      expect(r.items.length, greaterThanOrEqualTo(2));
      expect(r.items.any((e) => e.text == 'ok' && !e.daily), isTrue);
      final ids = r.items.map((e) => e.id).toList();
      r.handle('/remind 21:00 new', now);
      expect(r.items.last.id, isNot(anyOf(ids)), reason: 'new id must not collide with loaded ones');
    });
  });

  group('PetBrain.sendChat pre-AI handling', () {
    late Directory tmp;
    setUp(() {
      for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
      }
      tmp = Directory.systemTemp.createTempSync('rem_audit');
      PathProviderPlatform.instance = _Paths(tmp.path);
    });
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    test('a reminder line never reaches the AI and nothing is sent', () async {
      final b = PetBrain();
      addTearDown(b.dispose);
      b.ai.client = MockClient((_) async => throw StateError('network must not be touched'));
      b.ai.active
        ..apiKey = 'k'
        ..model = 'm';
      await b.sendChat('remind me in 10 minutes to drink water');
      expect(b.reminders.items, hasLength(1));
      expect(b.thinking, isFalse);
      expect(b.chat.map((m) => m.text).join('|'), contains('drink water'));
    });

    test('Chinese reminder line is handled locally too', () async {
      Lang.code = 'zh';
      final b = PetBrain();
      addTearDown(b.dispose);
      b.ai.client = MockClient((_) async => throw StateError('network must not be touched'));
      b.ai.active
        ..apiKey = 'k'
        ..model = 'm';
      b.ai.consented.add(b.ai.active.id);
      await b.sendChat('10分钟后提醒我喝水');
      expect(b.reminders.items, hasLength(1), reason: 'went to the AI instead');
    });

    test('empty / whitespace input is ignored', () async {
      final b = PetBrain();
      addTearDown(b.dispose);
      await b.sendChat('   ');
      expect(b.chat, isEmpty);
    });

    test('absurd reminder text does not throw out of sendChat', () async {
      final b = PetBrain();
      addTearDown(b.dispose);
      b.ai.client = MockClient((_) async => throw StateError('network must not be touched'));
      await expectLater(b.sendChat('99999999999999999999999 minutes later remind me ${'x' * 5000}'), completes);
    });
  });
}
