import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/profile.dart';

/// One reminder. [daily] ones roll forward to the next day after firing.
class Reminder {
  final int id;
  DateTime at;
  final String text;
  final bool daily;

  Reminder({required this.id, required this.at, required this.text, this.daily = false});

  Map<String, dynamic> toJson() =>
      {'id': id, 'at': at.toIso8601String(), 'text': text, 'daily': daily};

  static Reminder? fromJson(Map j) {
    final at = DateTime.tryParse(j['at']?.toString() ?? '');
    if (at == null) return null;
    final id = j['id'];
    return Reminder(
      id: id is num ? id.toInt() : (int.tryParse('$id') ?? 0),
      at: at.isUtc ? at.toLocal() : at,
      text: (j['text'] ?? '').toString(),
      daily: j['daily'] == true,
    );
  }
}

/// Result of reading a reminder request out of a chat line.
class ParsedReminder {
  final DateTime at;
  final String text;
  final bool daily;
  ParsedReminder(this.at, this.text, this.daily);
}

/// Reminders set from chat, in Korean:
///   /알림 18:30 약 먹기      /알림 내일 오후 3시 회의
///   /알림 매일 9시 물 마시기  /알림 (목록)   /알림 취소 2
///   10분 뒤에 빨래 꺼내라고 알려줘   1시간 반 후에 알림 산책
/// Plain chat needs a trigger word (알려줘, 알림, 깨워줘 ...) so that
/// "10분 뒤에 뭐 하지?" stays a normal question for the AI.
class Reminders {
  final List<Reminder> items = [];
  int _nextId = 1;

  List<Reminder> get upcoming => [...items]..sort((a, b) => a.at.compareTo(b.at));

  static final _slash =
      RegExp(r'^/(알림|알람|리마인드|remind|alarm)\s*', caseSensitive: false);
  // English triggers: "remind me to ...", "set an alarm for ...", "wake me up".
  static final _triggerEn = RegExp(
      r'\b(remind\s+me(\s+to)?|set\s+(an?\s+)?(alarm|reminder|timer)(\s+for)?|wake\s+me(\s+up)?|alarm|(an?\s+)?timer)\b',
      caseSensitive: false);
  // Chinese: "10分钟后提醒我喝水", "设个闹钟", "明天早上7点叫我起床".
  static final _triggerZh = RegExp(
      r'(帮我)?(设|定|订|设置)(个|一个)?(闹钟|提醒|定时|计时器?)|提醒我?|闹钟|叫醒?我|喊我|计时器?');

  /// English phrasing -> the Korean tokens the parser understands
  /// ("in 10 minutes" -> "10분 뒤", "tomorrow" -> "내일", "every day" -> "매일").
  static String normalizeEn(String s) {
    String num(String? w) => w == null
        ? ''
        : (w.toLowerCase() == 'an' || w.toLowerCase() == 'a' ? '1' : w);
    s = s.replaceAllMapped(RegExp(r'\b([ap])\.m\.?', caseSensitive: false), (m) => '${m[1]}m');
    s = s
        .replaceAll(RegExp(r'\bnoon\b', caseSensitive: false), '12pm')
        .replaceAll(RegExp(r'\bmidnight\b', caseSensitive: false), '12am');
    // "set a timer for 5 minutes" means "in 5 minutes"
    if (RegExp(r'\btimer\b', caseSensitive: false).hasMatch(s)) {
      s = s.replaceAll(RegExp(r'\bfor\s+(?=\d|an?\s)', caseSensitive: false), 'in ');
    }
    s = s.replaceAll(RegExp(r'\bin\s+half\s+an?\s+hour\b', caseSensitive: false), ' 30분 뒤 ');
    s = s.replaceAllMapped(
        RegExp(r'\bin\s+(\d+|an?)\s*(?:hours?|hrs?|h)\b(?:\s*(?:and\s+)?(\d+)\s*(?:minutes?|mins?|m)\b)?',
            caseSensitive: false),
        (m) => ' ${num(m[1])}시간 ${m[2] != null ? '${m[2]}분 ' : ''}뒤 ');
    s = s.replaceAllMapped(
        RegExp(r'\bin\s+(\d+|an?)\s*(?:minutes?|mins?|m)\b', caseSensitive: false),
        (m) => ' ${num(m[1])}분 뒤 ');
    s = s.replaceAllMapped(
        RegExp(r'\bin\s+(\d+|an?)\s*(?:seconds?|secs?|s)\b', caseSensitive: false),
        (m) => ' ${num(m[1])}초 뒤 ');
    s = s.replaceAllMapped(
        RegExp(r'\bin\s+(\d+|an?)\s*days?\b', caseSensitive: false),
        (m) => ' ${num(m[1])}일 뒤 ');
    s = s.replaceAllMapped(
        RegExp(r'\b(\d+)\s*(minutes?|mins?|hours?|seconds?|days?)\s+(?:from\s+now|later)\b',
            caseSensitive: false),
        (m) {
      final u = m[2]!.toLowerCase();
      return ' ${m[1]}${u.startsWith('h') ? '시간' : u.startsWith('s') ? '초' : u.startsWith('d') ? '일' : '분'} 뒤 ';
    });
    // "at 5" (no am/pm, no minutes): a bare hour, like Korean "5시"
    s = s.replaceAllMapped(
        RegExp(r'\bat\s+(\d{1,2})\b(?!\s*(?::|\d|am\b|pm\b|시))', caseSensitive: false),
        (m) => ' ${m[1]}시 ');
    s = s
        .replaceAll(RegExp(r'\b(every\s*day|daily)\b', caseSensitive: false), ' 매일 ')
        .replaceAll(RegExp(r'\btomorrow(\s+at)?\b', caseSensitive: false), ' 내일 ')
        .replaceAll(RegExp(r'\b(today|tonight)(\s+at)?\b', caseSensitive: false), ' 오늘 ');
    return s;
  }

  static const _zhDigits = {
    '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };

  /// "12", "十", "二十五", "三" -> int (up to 99); null if not a number.
  static int? _zhNum(String w) {
    final n = int.tryParse(w);
    if (n != null || w.isEmpty) return n;
    if (w.contains('十')) {
      final parts = w.split('十');
      final tens = parts[0].isEmpty ? 1 : _zhDigits[parts[0]];
      final ones = parts.length > 1 && parts[1].isNotEmpty ? _zhDigits[parts[1]] : 0;
      return tens == null || ones == null ? null : tens * 10 + ones;
    }
    return w.length == 1 ? _zhDigits[w] : null;
  }

  static const _zn = r'([0-9]{1,9}|[零〇一二两三四五六七八九十]{1,3})';
  static const _zAfter = r'\s*(?:以后|之后|后)';

  /// Chinese phrasing -> the same Korean tokens ("10分钟后" -> "10분 뒤",
  /// "明天下午3点" -> "내일 오후 3시", "每天" -> "매일").
  static String normalizeZh(String s) {
    if (!RegExp(r'[一-鿿]').hasMatch(s)) return s;
    String n(String? w) => '${_zhNum(w ?? '') ?? w}';
    s = s.replaceAllMapped(RegExp('$_zn\\s*个半\\s*小时$_zAfter'), (m) => ' ${n(m[1])}시간 30분 뒤 ');
    s = s.replaceAll(RegExp('半个?小时$_zAfter'), ' 30분 뒤 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*个?\\s*小时(?:\\s*$_zn\\s*分钟?)?$_zAfter'),
        (m) => ' ${n(m[1])}시간 ${m[2] != null ? '${n(m[2])}분 ' : ''}뒤 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*分钟?$_zAfter'), (m) => ' ${n(m[1])}분 뒤 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*秒钟?$_zAfter'), (m) => ' ${n(m[1])}초 뒤 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*天$_zAfter'), (m) => ' ${n(m[1])}일 뒤 ');
    s = s
        .replaceAll(RegExp('每天|每日'), ' 매일 ')
        .replaceAll('今天', ' 오늘 ')
        .replaceAll('明天', ' 내일 ')
        .replaceAll('后天', ' 모레 ')
        .replaceAll('凌晨', ' 새벽 ')
        .replaceAll(RegExp('早上|早晨|清晨|上午'), ' 오전 ')
        .replaceAll('中午', ' 낮 ')
        .replaceAll('下午', ' 오후 ')
        .replaceAll('夜里', ' 밤 ')
        .replaceAll(RegExp('晚上|夜晚|傍晚'), ' 저녁 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*[点點]\\s*半'), (m) => ' ${n(m[1])}시 반 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*[点點]\\s*$_zn\\s*分?'), (m) => ' ${n(m[1])}시 ${n(m[2])}분 ');
    s = s.replaceAllMapped(RegExp('$_zn\\s*[点點](?:钟|整)?'), (m) => ' ${n(m[1])}시 ');
    return s;
  }

  // Dates and weekdays are not understood: refuse instead of guessing "today".
  static final _unsupportedDate = RegExp(
      r'[월화수목금토일]요일|다음\s*주|이번\s*주|주말|\d{1,2}\s*월(\s*\d{1,2}\s*일)?|\b\d{1,2}/\d{1,2}\b'
      r'|\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri)\b'
      r'|\bnext\s+(week|month|year)\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b'
      r'|星期[一二三四五六日天]|周[一二三四五六日天]|下周|下个月|\d{1,2}月\d{0,2}[日号]?',
      caseSensitive: false);

  // "알람해", "알람 맞춰줘", "울려줘" ... longest forms first.
  static final _trigger = RegExp(
      r'((알람|알림|타이머)\s*(좀\s*)?(설정\s*해\s*줘|설정\s*해|설정|맞춰\s*줘|맞춰|해\s*줘|해\s*줄래|해\s*주세요|해)?'
      r'|알려\s*줘|알려\s*주세요|알려\s*줄래|리마인드|깨워\s*줘|울려\s*줘|말해\s*줘)');

  /// Handles a chat line. Returns the pet's reply if the line was a
  /// reminder command, or null to pass it on to the AI.
  String? handle(String input, DateTime now) {
    final line = input.trim();
    final slash = _slash.firstMatch(line);
    if (slash != null) {
      final args = line.substring(slash.end).trim();
      if (args.isEmpty || RegExp(r'^(목록|보기|list)$', caseSensitive: false).hasMatch(args)) {
        return listText(now);
      }
      final cancel = RegExp(r'^(?:취소|삭제|지워|끄기|(?:cancel|delete|remove)(?![a-z]))(?:\s*해?\s*줘)?\s*(\d+|전부|모두|all)?\s*(?:번째?)?\s*$',
              caseSensitive: false)
          .firstMatch(args);
      if (cancel != null) return _cancel(cancel.group(1), now);
      final p = parse(args, now);
      if (p == null) {
        return Lang.t('언제 알려줄지 모르겠어 😅 이렇게 말해줘: "/알림 18:30 약 먹기", "/알림 10분 뒤 빨래"',
            'Not sure when 😅 Try: "/remind 18:30 take medicine" or "/remind in 10 minutes laundry"', '不知道什么时候提醒 😅 试试这样说："/remind 18:30 吃药" 或 "/remind in 10 minutes laundry"');
      }
      return _add(p, now);
    }
    if (!_trigger.hasMatch(line) && !_triggerEn.hasMatch(line) && !_triggerZh.hasMatch(line)) return null;
    final isQuestion = RegExp(r'[?？]\s*$').hasMatch(line);
    // "How do I set an alarm?" asks about the feature; it is not a command.
    if (isQuestion && RegExp(r'^(how|what|why|where|which|does|is|are)\b', caseSensitive: false).hasMatch(line)) {
      return null;
    }
    final p = parse(line, now);
    if (p == null) {
      if (isQuestion) return null;
      // Clearly about an alarm but no time we can read: explain, instead
      // of letting the AI pretend it set one.
      if (RegExp(r'(알람|알림)\s*(좀\s*)?(해|맞춰|설정|울려)|울려\s*줘').hasMatch(line) ||
          RegExp(r'\b(set\s+(an?\s+)?(alarm|timer)|remind\s+me|wake\s+me)\b', caseSensitive: false)
              .hasMatch(line) ||
          RegExp(r'(设|定|订|设置)(个|一个)?(闹钟|提醒|计时)|提醒我|叫醒?我').hasMatch(line)) {
        return Lang.t('몇 시에 울릴지 알려줘! 예: "오후 5시에 알람", "10분 뒤 알람 해줘", "/알림 18:30 약 먹기"',
            'When should it ring? e.g. "set an alarm for 5pm", "remind me in 10 minutes", "/remind 18:30 take medicine"', '什么时候响呢？例如："下午 5 点设闹钟"、"10 分钟后提醒我"、"/remind 18:30 吃药"');
      }
      return null;
    }
    return _add(p, now);
  }

  String _add(ParsedReminder p, DateTime now) {
    final r = Reminder(id: _nextId++, at: p.at, text: p.text, daily: p.daily);
    items.add(r);
    final when = p.daily
        ? Lang.t('매일 ${clock(p.at)}', 'every day at ${clock(p.at)}', '每天 ${clock(p.at)}')
        : '${dayWord(p.at, now)} ${clock(p.at)}';
    final left = p.daily ? '' : ' (${untilText(p.at, now)})';
    return Lang.t('알았어! $when$left에 "${p.text}" 알려줄게 ⏰',
        'Got it! I\'ll remind you "${p.text}" $when$left ⏰', '知道啦！我会在 $when$left 提醒你"${p.text}" ⏰');
  }

  String _cancel(String? which, DateTime now) {
    final list = upcoming;
    if (list.isEmpty) return Lang.t('취소할 알림이 없어!', 'No reminders to cancel!', '没有可以取消的提醒！');
    if (which == '전부' || which == '모두' || which?.toLowerCase() == 'all') {
      items.clear();
      return Lang.t('알림 ${list.length}개 다 지웠어!', 'Cleared all ${list.length} reminders!', '已清除全部 ${list.length} 个提醒！');
    }
    final n = int.tryParse(which ?? '');
    if (n == null || n < 1 || n > list.length) {
      return Lang.t('몇 번 알림을 취소할까? 번호를 붙여줘 (예: /알림 취소 1)\n${listText(now)}',
          'Which one? Add its number (e.g. /remind cancel 1)\n${listText(now)}', '取消哪一个？请加上编号（例如 /remind cancel 1）\n${listText(now)}');
    }
    final r = list[n - 1];
    items.remove(r);
    return Lang.t('"${r.text}" 알림 취소했어!', 'Cancelled "${r.text}"!', '已取消"${r.text}"！');
  }

  String listText(DateTime now) {
    final list = upcoming;
    if (list.isEmpty) {
      return Lang.t('예정된 알림이 없어. "/알림 18:30 약 먹기"처럼 말해줘!',
          'No reminders yet. Try "/remind 18:30 take medicine"!', '还没有提醒。试试 "/remind 18:30 吃药"！');
    }
    final lines = [
      for (var i = 0; i < list.length; i++)
        '${i + 1}. ${list[i].daily ? Lang.t('매일', 'every day', '每天') : dayWord(list[i].at, now)} '
            '${clock(list[i].at)} - ${list[i].text}',
    ];
    return '⏰ ${Lang.t('예정된 알림', 'Reminders', '提醒事项')}\n${lines.join('\n')}';
  }

  /// One line for the AI context (null when nothing is scheduled).
  String? promptLine(DateTime now) {
    final list = upcoming.take(5).toList();
    if (list.isEmpty) return null;
    return 'Upcoming reminders: ${list.map((r) => '${dayWord(r.at, now)} ${clock(r.at)} ${r.text}').join(', ')}';
  }

  /// Removes and returns reminders that are due; daily ones are moved to
  /// their next occurrence instead of removed.
  List<Reminder> takeDue(DateTime now) {
    final due = items.where((r) => !r.at.isAfter(now)).toList();
    final fired = <Reminder>[];
    for (final r in due) {
      // Report the time it was due, not the rolled-forward one.
      fired.add(Reminder(id: r.id, at: r.at, text: r.text, daily: r.daily));
      if (r.daily) {
        // Same wall-clock time on a later day (adding 24 h would drift by an
        // hour across a daylight-saving change).
        var next = r.at;
        final skip = now.difference(next).inDays;
        if (skip > 0) next = _addDays(next, skip);
        while (!next.isAfter(now)) {
          next = _addDays(next, 1);
        }
        r.at = next;
      } else {
        items.remove(r);
      }
    }
    return fired;
  }

  // ---------- parsing ----------

  static final _relative = RegExp(
      r'(?:(\d+)\s*시간\s*(반)?\s*)?(?:(\d+)\s*분\s*)?(?:(\d+)\s*초\s*)?(?:뒤|후|있다가)');

  static final _absolute = RegExp(
      r'(?:(오늘|내일|모레)\s*)?(?:(오전|오후|아침|낮|저녁|밤|새벽)\s*)?'
      r'(?:(\d{1,2}):(\d{2})|(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분|\s*(반))?|(\d{1,2})(?=\s*(?:am|pm)))'
      r'\s*(am|pm)?',
      caseSensitive: false);

  static DateTime _addDays(DateTime t, int n) =>
      DateTime(t.year, t.month, t.day + n, t.hour, t.minute, t.second);

  /// Reads a time and the reminder text out of [s]. Null if no time.
  static ParsedReminder? parse(String s, DateTime now) {
    s = normalizeZh(normalizeEn(s));
    if (_unsupportedDate.hasMatch(s)) return null;
    var daily = false;
    if (RegExp(r'매일').hasMatch(s)) {
      daily = true;
      s = s.replaceFirst(RegExp(r'매일\s*'), '');
    }
    // "5분 타이머": the duration without 뒤
    if (RegExp(r'타이머|\btimer\b|计时', caseSensitive: false).hasMatch(s)) {
      s = s.replaceAllMapped(RegExp(r'(\d+)\s*(시간|분|초)(?!\s*(?:뒤|후|있다가))'), (m) => '${m[1]}${m[2]} 뒤');
    }
    // "3일 뒤": whole days ahead
    var dayOffset = 0;
    final dm = RegExp(r'(\d{1,4})\s*일\s*(?:뒤|후)').firstMatch(s);
    if (dm != null) {
      dayOffset = int.parse(dm.group(1)!);
      s = s.replaceRange(dm.start, dm.end, ' ');
    }
    // 오늘 / 내일 / 모레 may come before or after the time
    var plus = dayOffset;
    final dw = RegExp(r'오늘|내일|모레').firstMatch(s);
    if (dw != null) {
      plus += dw.group(0) == '내일' ? 1 : (dw.group(0) == '모레' ? 2 : 0);
      s = s.replaceRange(dw.start, dw.end, ' ');
    }

    DateTime? at;
    Match? used;
    for (final m in _relative.allMatches(s)) {
      final h = int.tryParse(m.group(1) ?? '');
      final half = m.group(2) != null;
      final min = int.tryParse(m.group(3) ?? '');
      final sec = int.tryParse(m.group(4) ?? '');
      if (h == null && min == null && sec == null) continue; // e.g. 오후
      if ((h ?? 0) > 10000 || (min ?? 0) > 600000 || (sec ?? 0) > 36000000) return null;
      at = now.add(Duration(
          hours: h ?? 0, minutes: (min ?? 0) + (half ? 30 : 0), seconds: sec ?? 0));
      if (dayOffset > 0) at = _addDays(at, dayOffset);
      used = m;
      daily = false; // "매일 10분 뒤" makes no sense; treat as one-off
      break;
    }

    if (at == null) {
      final m = _absolute.firstMatch(s);
      if (m == null) {
        if (dayOffset == 0) return null;
        at = _addDays(now, dayOffset); // "3일 뒤에 알려줘": same time of day
      } else {
        final colon = m.group(3);
        var h = int.parse(colon ?? m.group(5) ?? m.group(8)!);
        final min = m.group(4) != null
            ? int.parse(m.group(4)!)
            : (m.group(6) != null ? int.parse(m.group(6)!) : (m.group(7) != null ? 30 : 0));
        if (h > 23 || min > 59) return null;
        final period = m.group(2);
        final ampm = m.group(9)?.toLowerCase();
        var pm = ampm == 'pm' || const ['오후', '저녁'].contains(period);
        var am = ampm == 'am' || const ['오전', '아침', '새벽'].contains(period);
        var explicit = false;
        if (period == '밤') {
          // 밤 12시 is midnight, 밤 1~5시 is after midnight, 밤 6~11시 is evening
          if (h == 12) {
            h = 0;
          } else if (h >= 6 && h <= 11) {
            h += 12;
          }
          explicit = true;
        } else if (period == '낮') {
          if (h >= 1 && h <= 6) h += 12;
          explicit = true;
        }
        // "07:30" with a leading zero is a 24-hour clock time
        if (colon != null && colon.length == 2 && colon.startsWith('0')) explicit = true;
        if (pm && h < 12) h += 12;
        if (am && h == 12) h = 0;
        explicit = explicit || pm || am || h >= 13 || h == 0;
        DateTime on(int hour) =>
            DateTime(now.year, now.month, now.day + plus, hour, min);
        if (explicit) {
          at = on(h);
        } else if (daily) {
          // A daily "9시" means the usual time of day, whenever it was typed:
          // 6-11 morning, 12 noon, 1-5 afternoon (owner decision 2026-10-11).
          at = on(h >= 1 && h <= 5 ? h + 12 : h);
        } else {
          // "3시" with no 오전/오후: whichever of 3:00 / 15:00 comes next.
          at = on(h);
          if (plus == 0 && !at.isAfter(now) && h < 12) at = on(h + 12);
          if (h == 12) at = on(12);
        }
        if (plus == 0 && !at.isAfter(now)) at = _addDays(at, 1);
        used = m;
      }
    }
    if (at.difference(now) > const Duration(days: 366)) return null;

    var text = used == null ? s : s.replaceRange(used.start, used.end, ' ⏱ ');
    text = _cleanText(text);
    return ParsedReminder(at, text.isEmpty ? Lang.t('알람', 'Alarm', '闹钟') : text, daily);
  }

  static String _cleanText(String t) {
    t = t
        // English: drop the command words and the little words that were
        // glued to the time we cut out ("at ⏱", "for ⏱").
        .replaceAll(RegExp(r'\b(at|in|on|for|by|around)\s*⏱', caseSensitive: false), ' ')
        .replaceAll('⏱', ' ')
        .replaceAll(RegExp(r'^\s*/(remind|alarm)\b', caseSensitive: false), ' ')
        .replaceAll(_triggerEn, ' ')
        .replaceAll(_triggerZh, ' ')
        .replaceAll(RegExp(r'\bplease\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'^\s*(can|could|would|will)\s+you\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^(to|about|for|that)\s+', caseSensitive: false), '');
    t = t
        .replaceAll(RegExp(r'^/(알림|알람|리마인드|remind|alarm)', caseSensitive: false), '')
        // "약 먹으라고 알려줘" -> "약 먹기", "회의 있다고 알려줘" -> "회의 있다"
        .replaceAll(RegExp(r'으?라고(?=\s*(꼭|좀)?\s*' + _trigger.pattern + r')'), '기')
        .replaceAll(RegExp(r'다고(?=\s*(꼭|좀)?\s*' + _trigger.pattern + r')'), '다')
        .replaceAll(RegExp(r'(꼭|좀)?\s*' + _trigger.pattern + r'(\s*해\s*줘)?'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = t
        .replaceFirst(RegExp(r'^(에는|에|쯤에?|정각에?|까지)\s*'), '')
        .replaceFirst(RegExp(r'\s*(에|쯤)$'), '')
        .replaceFirst(RegExp(r'[\s.!?~,]+$'), '')
        .trim();
    return t;
  }

  // ---------- formatting ----------

  static String clock(DateTime t) {
    final pm = t.hour >= 12;
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return Lang.ko ? '${pm ? '오후' : '오전'} $h12:$mm' : '$h12:$mm ${pm ? 'PM' : 'AM'}';
  }

  static String dayWord(DateTime t, DateTime now) {
    final d = DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (d == 0) return Lang.t('오늘', 'today', '今天');
    if (d == 1) return Lang.t('내일', 'tomorrow', '明天');
    if (d == 2) return Lang.t('모레', 'in 2 days', '后天');
    return '${t.month}/${t.day}';
  }

  static String untilText(DateTime t, DateTime now) {
    final secs = t.difference(now).inSeconds;
    if (secs < 60) return Lang.t('$secs초 뒤', 'in $secs sec', '$secs秒后');
    final mins = (secs / 60).round();
    if (mins < 60) return Lang.t('$mins분 뒤', 'in $mins min', '$mins分钟后');
    final h = mins ~/ 60, m = mins % 60;
    return m == 0
        ? Lang.t('$h시간 뒤', 'in $h h', '$h小时后')
        : Lang.t('$h시간 $m분 뒤', 'in $h h $m min', '$h小时$m分钟后');
  }

  // ---------- persistence ----------

  List<Map<String, dynamic>> toJson() => [for (final r in items) r.toJson()];

  void loadJson(List list) {
    items
      ..clear()
      ..addAll(list.whereType<Map>().map(Reminder.fromJson).whereType<Reminder>());
    _nextId = items.fold(0, (m, r) => r.id > m ? r.id : m) + 1;
  }

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/reminders.json');
  }

  Future<void> save() async {
    try {
      await (await _file()).writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) loadJson(j);
    } catch (_) {}
  }
}
