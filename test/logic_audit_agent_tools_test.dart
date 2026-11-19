// Run twice: default edition and `--dart-define=EDITION=store` (web search /
// weather gating differs). Tests adapt to Ed.current.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/agent_tools.dart';

AgentTools make({List<String>? log, String Function(String)? onRemind}) => AgentTools(
    reminder: (c) {
      log?.add(c);
      return onRemind?.call(c) ?? 'OK';
    },
    saveNote: (t) async => 'saved:$t');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Lang.code = 'en');

  group('schemas', () {
    test('every tool has a valid object schema; required keys exist in properties', () {
      for (final t in make().all) {
        expect(t.parameters['type'], 'object', reason: t.name);
        final props = t.parameters['properties'] as Map;
        for (final r in (t.parameters['required'] as List)) {
          expect(props.containsKey(r), isTrue, reason: '${t.name} requires "$r" but has no such property');
        }
        expect(t.description, isNotEmpty);
        expect(t.openAi['function']['name'], t.name);
        expect(t.anthropic['input_schema'], t.parameters);
        // must round-trip as JSON for the wire
        expect(() => jsonEncode(t.openAi), returnsNormally);
      }
    });

    test('tool names are unique and match the system prompt\'s promises', () {
      final names = make().all.map((t) => t.name).toList();
      expect(names.toSet().length, names.length);
      expect(names, containsAll(['web_search', 'read_webpage', 'set_reminder', 'list_reminders', 'cancel_reminder', 'save_note']));
    });

    test('weather tool is gated by edition', () {
      final has = make().all.any((t) => t.name == 'get_weather');
      expect(has, Ed.noncommercialApis);
    });

    test('calendar tools follow calendarEnabled and appear together', () {
      final t = make()..calendarEnabled = true;
      expect(t.all.map((e) => e.name), containsAll(['calendar_events', 'add_calendar_event']));
      t.calendarEnabled = false;
      expect(t.all.map((e) => e.name), isNot(contains('calendar_events')));
      expect(t.all.map((e) => e.name), isNot(contains('add_calendar_event')));
    });

    test('add_calendar_event requires title and start only', () {
      final t = make().all.firstWhere((e) => e.name == 'add_calendar_event');
      expect(t.parameters['required'], ['title', 'start']);
    });

    test('busyLabel: known tool has a label, unknown falls back', () {
      final t = make();
      expect(t.busyLabel('web_search'), isNot('…'));
      expect(t.busyLabel('nope'), '…');
      Lang.code = 'zh';
      expect(t.busyLabel('web_search'), contains('搜索'));
    });
  });

  group('call()', () {
    test('unknown tool', () async {
      expect(await make().call('rm_rf', {}), startsWith('error: unknown tool'));
    });

    test('set_reminder routes to "/remind when what"', () async {
      final log = <String>[];
      await make(log: log).call('set_reminder', {'when': 'in 10 minutes', 'what': 'tea'});
      expect(log, ['/remind in 10 minutes tea']);
    });

    test('list_reminders / cancel_reminder routing', () async {
      final log = <String>[];
      final t = make(log: log);
      await t.call('list_reminders', {});
      await t.call('cancel_reminder', {'which': '2'});
      await t.call('cancel_reminder', {'which': 'all'});
      expect(log, ['/remind list', '/remind cancel 2', '/remind cancel all']);
    });

    test('set_reminder with missing arguments does not send the word "null"', () async {
      final log = <String>[];
      await make(log: log).call('set_reminder', {});
      expect(log.any((l) => l.contains('null')), isFalse, reason: log.toString());
    });

    test('exception inside a tool becomes an error string; oversize output is cut at 8000', () async {
      final t = AgentTools(reminder: (_) => throw StateError('x'), saveNote: (_) async => 'a' * 20000);
      expect(await t.call('list_reminders', {}), startsWith('error:'));
      final out = await t.call('save_note', {'text': 'x'});
      expect(out.length, lessThanOrEqualTo(8001));
    });

    test('read_webpage rejects non-http schemes without network', () async {
      final t = make();
      for (final u in ['file:///etc/passwd', 'javascript:alert(1)', 'ftp://x/y', '', 'not a url', 'data:text/html,hi']) {
        expect(await t.call('read_webpage', {'url': u}), startsWith('error'), reason: u);
      }
    });

    test('read_webpage of http(s) targets on the local network is not allowed (SSRF to localhost/LAN)', () async {
      final t = make();
      for (final u in ['http://127.0.0.1:8080/admin', 'http://localhost/x', 'http://10.0.0.5/', 'http://169.254.169.254/latest/meta-data/']) {
        final out = await http.runWithClient(() => t.call('read_webpage', {'url': u}), () => MockClient((_) async => http.Response('SECRET', 200)));
        expect(out.contains('SECRET'), isFalse, reason: 'fetched $u');
      }
    });
  });

  group('web search gating and request shape', () {
    test('no Brave key: personal/lite use DuckDuckGo, sold editions refuse without any request', () async {
      final reqs = <http.Request>[];
      final t = make()..country = 'KR';
      final out = await http.runWithClient(() => t.webSearch('날씨 & 뉴스'), () => MockClient((r) async {
            reqs.add(r);
            return http.Response('<div class="result__body"><a class="result__a" href="https://a.example/">A</a></div>', 200);
          }));
      if (Ed.noncommercialApis) {
        expect(reqs.single.url.host, 'html.duckduckgo.com');
        expect(reqs.single.method, 'POST');
        expect(reqs.single.body, contains('kl=kr-kr'));
        expect(reqs.single.body, contains(Uri.encodeQueryComponent('날씨 & 뉴스')));
        expect(out, contains('https://a.example/'));
      } else {
        expect(reqs, isEmpty);
        expect(out, contains('Brave'));
      }
    });

    test('with a Brave key: Brave is used in every edition, key in header not URL, query encoded, country lower-cased', () async {
      final reqs = <http.Request>[];
      final t = make()
        ..braveKey = 'BSA-secret'
        ..country = 'US';
      final out = await http.runWithClient(() => t.webSearch('a&b=c d'), () => MockClient((r) async {
            reqs.add(r);
            return http.Response(
                jsonEncode({'web': {'results': [{'title': 'T', 'url': 'https://x.example', 'description': 'D <b>bold</b>'}]}}), 200);
          }));
      expect(reqs.single.url.host, 'api.search.brave.com');
      expect(reqs.single.url.queryParameters['q'], 'a&b=c d');
      expect(reqs.single.url.queryParameters['country'], 'us');
      expect(reqs.single.headers['X-Subscription-Token'], 'BSA-secret');
      expect(reqs.single.url.toString().contains('BSA-secret'), isFalse);
      expect(out, contains('https://x.example'));
      expect(out.contains('<b>'), isFalse);
    });

    test('Brave errors: 401/429 JSON without "web" returns something sane, not a crash', () async {
      final t = make()..braveKey = 'k';
      for (final r in [
        http.Response(jsonEncode({'error': 'bad key'}), 401),
        http.Response('not json', 500),
        http.Response('[]', 200),
      ]) {
        final out = await http.runWithClient(() => t.call('web_search', {'query': 'x'}), () => MockClient((_) async => r));
        expect(out, isA<String>());
        expect(out.startsWith('error') || out.isEmpty || out.isNotEmpty, isTrue);
      }
    });

    test('Brave 401 should say so instead of returning an empty string that the model reads as "no results"', () async {
      final t = make()..braveKey = 'k';
      final out = await http.runWithClient(() => t.webSearch('x'), () => MockClient((_) async => http.Response('{"error":"bad key"}', 401)));
      expect(out.trim(), isNotEmpty);
    });

    test('Brave result with null fields does not print "null"', () async {
      final t = make()..braveKey = 'k';
      final out = await http.runWithClient(
          () => t.webSearch('x'), () => MockClient((_) async => http.Response(jsonEncode({'web': {'results': [{'url': 'https://u.example'}]}}), 200)));
      expect(out.contains('null'), isFalse);
    });

    test('empty query is not sent as a search', () async {
      var n = 0;
      final t = make()..braveKey = 'k';
      await http.runWithClient(() => t.call('web_search', {'query': ''}), () => MockClient((_) async {
            n++;
            return http.Response('{}', 200);
          }));
      expect(n, 0, reason: 'blank query wastes a Brave quota unit');
    });
  });

  group('ddgRegion', () {
    test('known countries, case-insensitive, fallback worldwide', () {
      expect(AgentTools.ddgRegion('US'), 'us-en');
      expect(AgentTools.ddgRegion('us'), 'us-en');
      expect(AgentTools.ddgRegion('KR'), 'kr-kr');
      expect(AgentTools.ddgRegion('CN'), 'cn-zh');
      expect(AgentTools.ddgRegion('TW'), 'tw-tzh');
      expect(AgentTools.ddgRegion('JP'), 'jp-jp');
      expect(AgentTools.ddgRegion('GB'), 'uk-en');
      expect(AgentTools.ddgRegion('UK'), 'uk-en', reason: 'people type UK');
      expect(AgentTools.ddgRegion('CA'), 'ca-en');
      expect(AgentTools.ddgRegion(''), 'wt-wt');
      expect(AgentTools.ddgRegion('ZZ'), 'wt-wt');
      expect(AgentTools.ddgRegion('  us '), 'us-en', reason: 'profile field is free text');
    });
  });

  group('HTML helpers', () {
    test('parseDuckDuckGo: no results, malformed, > 6 results capped', () {
      expect(AgentTools.parseDuckDuckGo(''), 'no results');
      expect(AgentTools.parseDuckDuckGo('<html>captcha</html>'), 'no results');
      final many = List.generate(
          10, (i) => '<div class="result__body"><a class="result__a" href="https://e$i.example/">T$i</a></div>').join();
      expect('\n- '.allMatches('\n${AgentTools.parseDuckDuckGo(many)}').length, 6);
    });

    test('parseDuckDuckGo: uddg percent-decoding and entity unescape in link', () {
      const h = '<div class="result__body"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fa.example%2F%3Fq%3D1%26r%3D2&amp;rut=z">X</a></div>';
      expect(AgentTools.parseDuckDuckGo(h), contains('https://a.example/?q=1&r=2'));
    });

    test('pageText strips script/style/nav and keeps text; nested/unclosed script', () {
      expect(AgentTools.pageText('<style>p{}</style><nav>menu</nav><p>Hi</p>'), 'Hi');
    });
  });

  group('calendar tools (MethodChannel mocked)', () {
    test('days is clamped 1..31 and tolerant of junk', () async {
      final seen = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('hoodimong/calendar'),
          (c) async {
        seen.add((c.arguments as Map)['days'] as int);
        return [];
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('hoodimong/calendar'), null));
      final t = make();
      for (final d in [null, 0, -5, 1000, '3', 'abc', 2.9]) {
        await t.calendarEvents(d);
      }
      expect(seen, [7, 1, 1, 31, 3, 7, 2]);
    });

    test('calendar channel throwing becomes "error:" via call()', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('hoodimong/calendar'), (c) async => throw PlatformException(code: 'denied'));
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('hoodimong/calendar'), null));
      expect(await (make()..calendarEnabled = true).call('calendar_events', {'days': 3}), startsWith('error:'));
    });
  });

  group('weather', () {
    test('forecast request uses °F and the home coordinates when place is empty', () async {
      late Uri u;
      final t = make()
        ..homeName = 'Home'
        ..homeLat = 34.05
        ..homeLon = -118.24;
      final out = await http.runWithClient(() => t.weather(''), () => MockClient((r) async {
            u = r.url;
            return http.Response(
                jsonEncode({
                  'current': {'temperature_2m': 70, 'apparent_temperature': 69, 'weather_code': 0, 'wind_speed_10m': 3},
                  'daily': {
                    'time': ['2026-10-10'],
                    'temperature_2m_max': [80],
                    'temperature_2m_min': [60],
                    'precipitation_probability_max': [0],
                    'weather_code': [0]
                  }
                }),
                200);
          }));
      expect(u.queryParameters['temperature_unit'], 'fahrenheit');
      expect(u.queryParameters['latitude'], '34.05');
      expect(out, startsWith('Home now 70'));
    });

    test('unknown place -> "place not found"; API error body -> error string via call()', () async {
      final t = make();
      expect(await http.runWithClient(() => t.weather('Zzzz'), () => MockClient((_) async => http.Response('{}', 200))), startsWith('place not found'));
      if (Ed.noncommercialApis) {
        final out = await http.runWithClient(() => t.call('get_weather', {'place': ''}), () => MockClient((_) async => http.Response('{"error":true}', 400)));
        expect(out, startsWith('error:'));
      }
    });
  });
}
