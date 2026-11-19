import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/services/chat_ai.dart';
import 'package:hoodimong/models/care_rules.dart';
import 'package:hoodimong/services/project_memory.dart';
import 'package:hoodimong/services/weather_service.dart';
import 'package:hoodimong/services/market_service.dart';
import 'dart:math';

import 'package:hoodimong/models/reactions.dart';
import 'package:hoodimong/services/news_service.dart';
import 'package:hoodimong/services/notes.dart';
import 'package:hoodimong/services/reminders.dart';
import 'package:hoodimong/widgets/clip_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatAi.parseReply', () {
    test('reads the JSON contract', () {
      final r = ChatAi.parseReply(
          '{"text":"안녕!","mood":"happy","project":"주말 텃밭","remember":"STT 추가 결정"}');
      expect(r.text, '안녕!');
      expect(r.mood, PetMood.happy);
      expect(r.project, '주말 텃밭');
      expect(r.remember, 'STT 추가 결정');
    });

    test('handles code fences, think tags and null strings', () {
      final r = ChatAi.parseReply(
          '<think>hmm</think>\n```json\n{"text":"응","mood":"sad","project":"null","remember":null}\n```');
      expect(r.text, '응');
      expect(r.mood, PetMood.sad);
      expect(r.project, isNull);
      expect(r.remember, isNull);
    });

    test('falls back to plain text and talking mood', () {
      final r = ChatAi.parseReply('그냥 글이야');
      expect(r.text, '그냥 글이야');
      expect(r.mood, PetMood.talking);
    });

    test('rejects moods outside the reply set', () {
      final r = ChatAi.parseReply('{"text":"x","mood":"thinking"}');
      expect(r.mood, PetMood.talking);
    });
  });

  group('ProjectMemory', () {
    test('resolve creates once and matches loosely', () {
      final m = ProjectMemory();
      final a = m.resolve('주말 텃밭')!;
      final b = m.resolve('주말텃밭')!;
      expect(identical(a, b), isTrue);
      expect(m.projects.length, 2);
      expect(m.resolve(null), isNull);
      expect(m.resolve('일상'), isNull);
    });

    test('remember dedupes and caps', () {
      final m = ProjectMemory();
      final p = m.active;
      m.remember(p, '같은 말');
      m.remember(p, '같은 말');
      expect(p.notes.length, 1);
      for (var i = 0; i < 60; i++) {
        m.remember(p, 'n$i');
      }
      expect(p.notes.length, ProjectMemory.maxNotes);
    });

    test('round-trips through JSON', () {
      final m = ProjectMemory();
      final p = m.resolve('NAS 정리')!;
      m.addMessage(
          p, ChatMessage(text: 'hi', fromUser: true, at: DateTime(2026)));
      m.remember(p, '집 NAS가 정본');
      final back = ProjectContext.fromJson(p.toJson());
      expect(back.name, 'NAS 정리');
      expect(back.chat.single.text, 'hi');
      expect(back.notes.single, '집 NAS가 정본');
    });
  });

  group('Notes', () {
    test('note commands', () {
      expect(Notes.parseCommand('/노트 우유 사기'), '우유 사기');
      expect(Notes.parseCommand('/노트'), '');
      expect(Notes.parseCommand('이거 노트에 저장해줘'), '');
      expect(Notes.parseCommand('방금 거 노트해줘'), '');
      expect(Notes.parseCommand('우유 사기 메모해줘'), '우유 사기');
      expect(Notes.parseCommand('노트 기능 좋다'), isNull);
      expect(Notes.parseCommand('오늘 날씨 어때?'), isNull);
    });

    test('file name and bullet line', () {
      expect(Notes.fileFor('주말 텃밭'), '${Ed.dataFolder}/주말 텃밭.md');
      expect(Notes.fileFor('a/b:c'), '${Ed.dataFolder}/a_b_c.md');
      expect(Notes.line('첫 줄\n둘째 줄', DateTime(2026, 10, 5, 17, 5)),
          '- 2026-10-05 17:05 · 첫 줄 / 둘째 줄\n');
    });
  });

  group('News', () {
    const xml = """<rss><channel>
<item><title>Acme shares soar to record high on AI chip demand - Reuters</title>
<link>https://news.example/a</link><pubDate>Mon, 05 Oct 2026 20:00:00 GMT</pubDate>
<source url="https://reuters.com">Reuters</source></item>
<item><title>What is Acme? An explainer - Blog</title>
<link>https://news.example/b</link><pubDate>Mon, 05 Oct 2026 21:00:00 GMT</pubDate>
<source url="https://blog">Blog</source></item>
</channel></rss>""";

    test('parses RSS and picks only big, new, recent headlines', () {
      final items = NewsService.parse('Acme', xml);
      expect(items.length, 2);
      expect(items.first.title, 'Acme shares soar to record high on AI chip demand');
      expect(items.first.source, 'Reuters');
      final s = NewsService();
      final now = DateTime.utc(2026, 10, 5, 22, 0);
      final n = s.pickBig(items, now)!;
      expect(n.link, 'https://news.example/a');
      s.markShown(n, now);
      expect(s.pickBig(items, now), isNull); // explainer isn't "big"
      expect(s.pickBig(items, DateTime.utc(2026, 10, 6, 6, 0)), isNull); // old
    });
  });

  group('Language switch by chat', () {
    test('detects Korean, English and Chinese requests', () {
      expect(LanguageSwitch.detect('영어로 대화하자'), 'en');
      expect(LanguageSwitch.detect("let's talk in Korean"), 'ko');
      expect(LanguageSwitch.detect('한국어로 말해줘'), 'ko');
      expect(LanguageSwitch.detect('Can you speak Chinese?'), 'zh');
      expect(LanguageSwitch.detect('我们说中文吧'), 'zh');
      expect(LanguageSwitch.detect('switch to English please'), 'en');
      expect(LanguageSwitch.detect('영어 공부 어떻게 해?'), isNull);
      expect(LanguageSwitch.detect('I like Korean food'), isNull);
    });

    test('Chinese falls back to English where not translated yet', () {
      Lang.code = 'zh';
      expect(Lang.t('안녕', 'Hi'), 'Hi');
      expect(Lang.t('안녕', 'Hi', '你好'), '你好');
      Lang.code = 'en';
    });
  });

  group('Night-only sleep', () {
    test('tired by day looks bored, sleepy only at night', () {
      const day = CareStats(
          hunger: 80, happiness: 80, health: 90, energy: 10, sleeping: false);
      const night = CareStats(
          hunger: 80, happiness: 80, health: 90, energy: 10, sleeping: false,
          night: true);
      expect(day.needMood(), PetMood.bored);
      expect(night.needMood(), PetMood.sleepy);
      expect(CareStats.isNight(DateTime(2026, 10, 5, 21, 59)), isFalse);
      expect(CareStats.isNight(DateTime(2026, 10, 5, 22, 0)), isTrue);
      expect(CareStats.isNight(DateTime(2026, 10, 6, 6, 59)), isTrue);
      expect(CareStats.isNight(DateTime(2026, 10, 6, 7, 0)), isFalse);
    });
  });

  group('Project archive', () {
    test('close to archive, reopen from settings or by talking about it', () {
      final m = ProjectMemory();
      final a = m.create('이사 준비')!;
      expect(m.activeId, a.id);
      expect(m.archive(ProjectMemory.generalId), isFalse); // 일상 stays
      expect(m.archive(a.id), isTrue);
      expect(m.visible.map((p) => p.name), ['일상']);
      expect(m.archivedList.single.name, '이사 준비');
      expect(m.active.id, ProjectMemory.generalId);
      expect(m.promptBlock(), isNot(contains('이사 준비')));
      // kept through save/load
      final copy = ProjectContext.fromJson(a.toJson());
      expect(copy.archived, isTrue);
      m.restore(a.id);
      expect(m.visible.length, 2);
      expect(m.active.id, a.id);
      m.archive(a.id);
      expect(m.resolve('이사준비')!.archived, isFalse); // AI routed back
      expect(m.create('이사 준비')!.id, a.id); // no duplicate
    });
  });

  group('Care rules', () {
    setUp(() => Lang.ko = true);
    tearDown(() => Lang.ko = false);
    CareStats st(
            {double hunger = 50,
            double happiness = 50,
            double health = 90,
            double energy = 50,
            bool sleeping = false}) =>
        CareStats(
            hunger: hunger,
            happiness: happiness,
            health: health,
            energy: energy,
            sleeping: sleeping);

    test('cannot feed when full or asleep, cannot play when tired', () {
      expect(st(hunger: 96).feedBlock, '배불러요');
      expect(st().feedBlock, isNull);
      expect(st(energy: 10).playBlock, '너무 피곤해요');
      expect(st(sleeping: true).feedBlock, '자는 중');
      expect(st(sleeping: true).playBlock, '자는 중');
    });

    test('medicine only when unwell', () {
      expect(st(health: 90).medicineBlock, '건강해요');
      expect(st(health: 40).medicineBlock, isNull);
    });

    test('most urgent need decides mood and status', () {
      expect(st(hunger: 10).needMood(), PetMood.sad);
      expect(st(hunger: 10).needText(), contains('배고파'));
      expect(st(hunger: 10, health: 20).needMood(), PetMood.sick);
      expect(st().needMood(), isNull);
    });
  });

  group('Weather', () {
    setUp(() => Lang.ko = true);
    tearDown(() => Lang.ko = false);
    Map<String, dynamic> om(int code, double t,
            {double feels = 0, double wind = 5}) =>
        {
          'current': {
            'temperature_2m': t,
            'apparent_temperature': feels == 0 ? t : feels,
            'weather_code': code,
            'is_day': 1,
            'wind_speed_10m': wind,
          },
          'daily': {
            'temperature_2m_max': [t + 4],
            'temperature_2m_min': [t - 4],
            'precipitation_probability_max': [70],
          },
        };

    test('classifies sky and temperature', () {
      expect(WeatherService.parse(om(95, 20), '서울').sky, Sky.thunder);
      expect(WeatherService.parse(om(63, 20), '서울').isRain, isTrue);
      expect(WeatherService.parse(om(73, -2), '서울').sky, Sky.snow);
      expect(WeatherService.parse(om(0, 31, feels: 34), '서울').isHot, isTrue);
      expect(WeatherService.parse(om(0, 2), '서울').isCold, isTrue);
      expect(WeatherService.parse(om(1, 21), '서울').isLovely, isTrue);
    });

    test('summary and situation key', () {
      final w = WeatherService.parse(om(61, 18), '서울');
      expect(w.summary, contains('강수확률 70%'));
      expect(w.situation, startsWith('rain|mild'));
    });
  });

  group('Market', () {
    setUp(() => Lang.ko = true);
    tearDown(() => Lang.ko = false);
    test('portfolio total and weighted change', () {
      final a = Holding('bitcoin', 'BTC', 'Bitcoin', 1);
      final b = Holding('dogecoin', 'DOGE', 'Doge', 100);
      final m = MarketInfo([CoinQuote(a, 100, 10), CoinQuote(b, 1, -50)],
          StockQuote('ACME', 195.02, 0.49, false), DateTime(2026));
      expect(m.totalUsd, 200);
      // before: 100/1.1 + 100/0.5 = 290.9 -> now 200 => about -31.25%
      expect(m.totalChangePct, closeTo(-31.25, 0.1));
      expect(m.crash, isTrue);
      expect(m.headline, contains('ACME \$195.02 (+0.5%)'));
      expect(m.report(), contains('투자 조언은 아니야'));
    });
  });

  group('Reminders', () {
    setUp(() => Lang.ko = true);
    tearDown(() => Lang.ko = false);
    // Monday 2026-10-05 15:00 local.
    final now = DateTime(2026, 10, 5, 15, 0);

    test('slash command with 24h clock', () {
      final p = Reminders.parse('18:30 약 먹기', now)!;
      expect(p.at, DateTime(2026, 10, 5, 18, 30));
      expect(p.text, '약 먹기');
    });

    test('past time rolls to tomorrow; 오전/오후 and am/pm', () {
      expect(Reminders.parse('9:00 출근', now)!.at, DateTime(2026, 10, 5, 21, 0));
      expect(Reminders.parse('오전 9시 출근', now)!.at, DateTime(2026, 10, 6, 9, 0));
      expect(Reminders.parse('오후 2시 반 회의', now)!.at, DateTime(2026, 10, 6, 14, 30));
      expect(Reminders.parse('오후 3시 반 회의', now)!.at, DateTime(2026, 10, 5, 15, 30));
      expect(Reminders.parse('6:45pm 저녁', now)!.at, DateTime(2026, 10, 5, 18, 45));
      expect(Reminders.parse('내일 오후 2시 10분 미팅', now)!.at,
          DateTime(2026, 10, 6, 14, 10));
    });

    test('relative times and natural phrasing', () {
      final r = Reminders();
      expect(r.handle('10분 뒤에 빨래 꺼내라고 알려줘', now), contains('빨래 꺼내기'));
      expect(r.items.single.at, DateTime(2026, 10, 5, 15, 10));
      final p = Reminders.parse('1시간 반 후에 알림 산책', now)!;
      expect(p.at, DateTime(2026, 10, 5, 16, 30));
      expect(Reminders.parse('30분 있다가 약 먹으라고 알려줘', now)!.text, '약 먹기');
    });

    test('알람 wording (what the owner actually typed)', () {
      final r = Reminders();
      expect(r.handle('오후 5시에 알람해', now), contains('오후 5:00'));
      expect(r.items.last.at, DateTime(2026, 10, 5, 17, 0));
      expect(r.items.last.text, '알람');
      expect(r.handle('알람 1분뒤 해줘 어떻게 작동하는지 사람들 보여주게', now), isNotNull);
      expect(r.items.last.at, DateTime(2026, 10, 5, 15, 1));
      expect(r.handle('/알람 18:30 약 먹기', now), contains('약 먹기'));
      expect(r.handle('7시에 깨워줘', now), isNotNull);
      expect(r.handle('알람 맞춰줘', now), contains('몇 시에'));
      expect(r.handle('알람 기능 좋다', now), isNull);
    });

    test('plain questions are left for the AI', () {
      final r = Reminders();
      expect(r.handle('10분 뒤에 뭐 하지?', now), isNull);
      expect(r.handle('오후에 날씨 어때?', now), isNull);
      expect(r.items, isEmpty);
    });

    test('list, cancel, due and daily roll-forward', () {
      final r = Reminders();
      r.handle('/알림 18:30 약 먹기', now);
      r.handle('/알림 매일 9시 물 마시기', now);
      expect(r.handle('/알림', now), contains('1. 오늘 오후 6:30 - 약 먹기'));
      // a daily "9시" is 9 AM whenever it is typed (here at 3 PM -> tomorrow 9 AM)
      expect(r.items.where((x) => x.daily).single.at, DateTime(2026, 10, 6, 9, 0));
      expect(r.takeDue(DateTime(2026, 10, 5, 18, 30, 10)).map((x) => x.text), ['약 먹기']);
      final due = r.takeDue(DateTime(2026, 10, 6, 9, 0, 10));
      expect(due.map((x) => x.text), ['물 마시기']);
      expect(due.last.at, DateTime(2026, 10, 6, 9, 0)); // reported as due time
      expect(r.items.single.at, DateTime(2026, 10, 7, 9, 0)); // daily rolled
      expect(r.handle('/알림 취소 1', now), contains('물 마시기'));
      expect(r.items, isEmpty);
      expect(r.handle('/알림 언젠가', now), contains('모르겠어'));
    });

    test('round-trips through JSON', () {
      final r = Reminders()..handle('/알림 18:30 약 먹기', now);
      final copy = Reminders()..loadJson(r.toJson());
      expect(copy.items.single.text, '약 먹기');
      expect(copy.handle('/알림 19:00 산책', now), isNotNull);
      expect(copy.items.map((x) => x.id).toSet().length, 2);
    });
  });

  group('Reactions', () {
    setUp(() => Lang.ko = true);
    tearDown(() => Lang.ko = false);
    WeatherInfo hot() => WeatherService.parse({
          'current': {
            'temperature_2m': 36.0,
            'apparent_temperature': 38.0,
            'weather_code': 0,
            'is_day': 1,
            'wind_speed_10m': 5.0,
          },
          'daily': {
            'temperature_2m_max': [38.0],
            'temperature_2m_min': [25.0],
            'precipitation_probability_max': [1],
          },
        }, 'Los Angeles');

    MarketInfo market(double coin, double stock) => MarketInfo(
        [CoinQuote(Holding('bitcoin', 'BTC', 'Bitcoin', 1), 100, coin)],
        StockQuote('ACME', 195, stock, false),
        DateTime(2026));

    test('weather is told in Fahrenheit', () {
      final w = hot();
      expect(w.tempF, 97);
      expect(w.summary, contains('97°F'));
      expect(w.summary, isNot(contains('°C')));
      for (var i = 0; i < 8; i++) {
        final line = Reactions.weatherLine('hot', w, Random(i));
        expect(line, isNot(contains('{')));
      }
      expect(Reactions.fill('{t}/{f}/{lo}/{hi}', w), '97/100/77/100');
      expect(Reactions.weatherAction['hot'], 'fan');
    });

    test('market tier follows the bigger mover', () {
      expect(Reactions.marketTier(market(-6, 0.5)), -2);
      expect(Reactions.marketTier(market(0.5, -3)), -1);
      expect(Reactions.marketTier(market(1, 1)), 0);
      expect(Reactions.marketTier(market(2.5, -1)), 1);
      expect(Reactions.marketTier(market(0, 7)), 2);
      final line = Reactions.marketLine(-2, market(-6, 0), Random(0));
      expect(line, contains('ACME'));
      expect(Reactions.marketAction[-2], 'gloomy');
    });

    test('clip files with underscores in the key are found', () {
      expect(PetClips.fileRe.firstMatch('assets/characters/mongsil/anim/act_pet_0001.png')?.group(2),
          'act_pet');
      expect(PetClips.fileRe.firstMatch('assets/characters/mongsil/anim/idle_0012.png')?.group(2),
          'idle');
      expect(PetClips.fileRe.firstMatch('assets/characters/mongsil/anim/act_jump2_0003.webp')?.group(2),
          'act_jump2');
      expect(PetClips.fileRe.firstMatch('assets/characters/mongsil/anim/act_jump2.json'), isNull);
    });
  });
}
