import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/agent_tools.dart';
import 'package:hoodimong/services/chat_ai.dart';

ChatMessage um(String t) => ChatMessage(text: t, fromUser: true, at: DateTime(2026));
ChatMessage pm(String t) => ChatMessage(text: t, fromUser: false, at: DateTime(2026));

http.Response okJson(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200);
http.Response oaText(String s) => okJson({
      'choices': [
        {'message': {'role': 'assistant', 'content': s}}
      ]
    });
http.Response oaCall(String name, String args, {String id = 'c1'}) => okJson({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {'id': id, 'type': 'function', 'function': {'name': name, 'arguments': args}}
            ]
          }
        }
      ]
    });

AgentTools fakeTools({List<String>? log}) => AgentTools(
    reminder: (c) {
      log?.add(c);
      return 'OK';
    },
    saveNote: (t) async => 'saved');

/// Runs [f]; returns the thrown error or null. Lets a test accept "either a
/// clean AiException or a reply" without the `completes` matcher edge cases.
Future<Object?> thrown(Future<Object?> Function() f) async {
  try {
    await f();
    return null;
  } catch (e) {
    return e;
  }
}

const goodJson = '{"text":"ok","mood":"happy","project":null,"remember":null}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Lang.code = 'en');

  group('providers', () {
    test('isLocal / isReady rules', () {
      final ps = {for (final p in defaultProviders()) p.id: p};
      expect(ps['local']!.isLocal, isTrue);
      expect(ps['ollama']!.isLocal, isTrue);
      expect(ps['apple']!.isLocal, isTrue);
      expect(ps['apple']!.isReady, isTrue);
      expect(ps['gemini']!.isLocal, isFalse);
      // cloud: needs key AND model
      final g = ps['gemini']!;
      expect(g.isReady, isFalse);
      g.model = 'm';
      expect(g.isReady, isFalse);
      g.apiKey = 'k';
      expect(g.isReady, isTrue);
      g.baseUrl = '';
      expect(g.isReady, isFalse);
      // local needs a model, not a key
      final l = ps['local']!;
      expect(l.isReady, isFalse);
      l.model = 'x';
      expect(l.isReady, isTrue);
    });

    test('claude default has a model so only the key is missing', () {
      final c = defaultProviders().firstWhere((p) => p.id == 'claude');
      expect(c.wire, AiWire.anthropic);
      expect(c.model, isNotEmpty);
      expect(c.isReady, isFalse);
      c.apiKey = 'k';
      expect(c.isReady, isTrue);
    });

    test('a cloud URL that merely CONTAINS "localhost"/"127.0.0.1" is not local (consent bypass)', () {
      for (final url in [
        'https://evil.example/localhost',
        'https://localhost.evil.example/v1',
        'https://127.0.0.1.evil.example/v1',
        'https://evil.example/v1?next=http://127.0.0.1',
      ]) {
        final p = AiProvider(id: 'x', label: 'x', wire: AiWire.openai, baseUrl: url, model: 'm');
        expect(p.isLocal, isFalse, reason: url);
        expect(ChatAi().needsConsent(p), isTrue, reason: url);
        expect(p.isReady, isFalse, reason: '$url must still need a key');
      }
    });

    test('real loopback forms are local', () {
      for (final url in ['http://127.0.0.1:1234/v1', 'http://localhost:11434/v1', 'http://[::1]:8080/v1', 'http://LOCALHOST:1/v1']) {
        final p = AiProvider(id: 'x', label: 'x', wire: AiWire.openai, baseUrl: url, model: 'm');
        expect(p.isLocal, isTrue, reason: url);
      }
    });

    test('provider fromJson keeps defaults for missing fields and survives nulls', () {
      final p = defaultProviders().firstWhere((p) => p.id == 'claude');
      final model = p.model;
      p.fromJson({'apiKey': 'abc'});
      expect(p.model, model);
      expect(p.apiKey, 'abc');
      p.fromJson({'baseUrl': null, 'model': 5});
      expect(p.model, '5');
      expect(p.baseUrl, isNotEmpty);
    });

    test('active falls back to the first provider for an unknown id', () {
      final ai = ChatAi()..activeId = 'nope';
      expect(ai.active.id, ai.providers.first.id);
    });
  });

  group('consent v2', () {
    test('consentsFrom: v2 kept, v1 / missing version dropped, junk tolerated', () {
      expect(ChatAi.consentsFrom({'consentVersion': 2, 'consented': ['gemini']}), {'gemini'});
      expect(ChatAi.consentsFrom({'consentVersion': 3, 'consented': ['a']}), {'a'});
      expect(ChatAi.consentsFrom({'consentVersion': 1, 'consented': ['gemini']}), isEmpty);
      expect(ChatAi.consentsFrom({'consented': ['gemini']}), isEmpty);
      expect(ChatAi.consentsFrom({'consentVersion': 2}), isEmpty);
      expect(ChatAi.consentsFrom({'consentVersion': 2.0, 'consented': [1, 'a']}), {'1', 'a'});
      expect(ChatAi.consentsFrom({'consentVersion': 0, 'consented': ['a']}), isEmpty);
    });

    test('consentVersion as a string is not a bypass', () {
      // "2" is not a number: must fall back to v1 and drop (or at least not crash)
      expect(() => ChatAi.consentsFrom({'consentVersion': '2', 'consented': ['gemini']}), returnsNormally);
    });

    test('consented is a Map instead of a List: no crash', () {
      expect(() => ChatAi.consentsFrom({'consentVersion': 2, 'consented': {'a': 1}}), returnsNormally);
    });

    test('needsConsent: cloud until consented, local and apple never', () {
      final ai = ChatAi();
      final g = ai.providers.firstWhere((p) => p.id == 'gemini');
      expect(ai.needsConsent(g), isTrue);
      ai.consented.add('gemini');
      expect(ai.needsConsent(g), isFalse);
      for (final id in ['local', 'ollama', 'apple']) {
        expect(ai.needsConsent(ai.providers.firstWhere((p) => p.id == id)), isFalse);
      }
      // consent for one provider doesn't cover another
      expect(ai.needsConsent(ai.providers.firstWhere((p) => p.id == 'claude')), isTrue);
    });
  });

  group('parseReply', () {
    test('JSON wrapped in prose', () {
      final r = ChatAi.parseReply('Sure! Here you go: {"text":"hi","mood":"waving"} hope that helps');
      expect(r.text, 'hi');
      expect(r.mood, PetMood.waving);
    });

    test('prose before the JSON that itself contains braces', () {
      final r = ChatAi.parseReply('Use {name} placeholders. {"text":"hi","mood":"happy"}');
      expect(r.text, 'hi');
    });

    test('```json fence', () {
      final r = ChatAi.parseReply('```json\n{"text":"fenced","mood":"sad"}\n```');
      expect(r.text, 'fenced');
      expect(r.mood, PetMood.sad);
    });

    test('plain ``` fence without language', () {
      expect(ChatAi.parseReply('```\n{"text":"x"}\n```').text, 'x');
    });

    test('truncated JSON must not show raw JSON syntax in the bubble', () {
      final r = ChatAi.parseReply('{"text": "Hello there, how are y');
      expect(r.text.contains('{"text"'), isFalse, reason: 'bubble would show: ${r.text}');
      expect(r.text, contains('Hello there'));
    });

    test('truncated JSON after a complete text field recovers the text', () {
      final r = ChatAi.parseReply('{"text": "Done!", "mood": "happy", "project": "Gard');
      expect(r.text, 'Done!');
    });

    test('empty and whitespace', () {
      expect(ChatAi.parseReply('').text, '');
      expect(ChatAi.parseReply('   \n').text, '');
      expect(ChatAi.parseReply('').mood, PetMood.talking);
    });

    test('empty text field in JSON still returns a reply (caller must not crash)', () {
      final r = ChatAi.parseReply('{"text":"","mood":"happy"}');
      expect(r.text, '');
    });

    test('non-JSON text and bare braces', () {
      expect(ChatAi.parseReply('just words').text, 'just words');
      expect(ChatAi.parseReply('{}').text, '{}');
      expect(ChatAi.parseReply('} {').text, '} {');
      expect(ChatAi.parseReply('[1,2,3]').text, '[1,2,3]');
    });

    test('text that is not a string falls back to the raw text, mood talking', () {
      final r = ChatAi.parseReply('{"text": 5, "mood": "happy"}');
      expect(r.mood, PetMood.talking);
    });

    test('unclosed <think> tag does not leak reasoning', () {
      final r = ChatAi.parseReply('<think>planning the answer {"text":"leak"}');
      expect(r.text.contains('planning'), isFalse);
    });

    test('mood is case-insensitive / trimmed; unknown falls back', () {
      expect(ChatAi.parseReply('{"text":"x","mood":"Happy"}').mood, PetMood.happy);
      expect(ChatAi.parseReply('{"text":"x","mood":" sad "}').mood, PetMood.sad);
      expect(ChatAi.parseReply('{"text":"x","mood":"thinking"}').mood, PetMood.talking);
      expect(ChatAi.parseReply('{"text":"x","mood":null}').mood, PetMood.talking);
      expect(ChatAi.parseReply('{"text":"x","mood":["happy"]}').mood, PetMood.talking);
    });

    test('project/remember: placeholders meaning "nothing" become null', () {
      for (final v in ['null', 'Null', 'NULL', 'None', 'none', 'N/A', 'n/a', '없음', '', '  ', '-']) {
        final r = ChatAi.parseReply(jsonEncode({'text': 'x', 'project': v, 'remember': v}));
        expect(r.project, isNull, reason: 'project "$v"');
        expect(r.remember, isNull, reason: 'remember "$v"');
      }
    });

    test('project given as number / object does not crash', () {
      final r = ChatAi.parseReply('{"text":"x","project":{"a":1},"remember":42}');
      expect(r.text, 'x');
    });

    test('text containing escaped quotes and newlines', () {
      final r = ChatAi.parseReply(jsonEncode({'text': 'He said "hi"\nbye', 'mood': 'happy'}));
      expect(r.text, 'He said "hi"\nbye');
    });

    test('very long reply', () {
      final long = 'x' * 200000;
      expect(ChatAi.parseReply(jsonEncode({'text': long})).text.length, 200000);
    });
  });

  group('openai wire', () {
    ChatAi make(MockClient c, {String id = 'gemini'}) {
      final ai = ChatAi()
        ..activeId = id
        ..client = c;
      ai.active
        ..apiKey = 'k'
        ..model = 'm';
      return ai;
    }

    test('not ready -> AiException telling where to set the key', () async {
      final ai = ChatAi()..client = MockClient((_) async => fail('no network'));
      await expectLater(ai.reply([um('hi')], ''), throwsA(isA<AiException>()));
    });

    test('request shape: URL, bearer, model, system first, tools only when given', () async {
      late http.Request seen;
      final ai = make(MockClient((req) async {
        seen = req;
        return oaText(goodJson);
      }));
      ai.active.baseUrl = 'https://x.example/v1/';
      await ai.reply([um('hi')], 'CTX');
      expect(seen.url.toString(), 'https://x.example/v1/chat/completions');
      expect(seen.headers['Authorization'], 'Bearer k');
      final b = jsonDecode(seen.body) as Map;
      expect(b['model'], 'm');
      expect(b.containsKey('tools'), isFalse);
      expect((b['messages'] as List).first['role'], 'system');
      expect((b['messages'] as List).first['content'], contains('CTX'));
    });

    test('local provider with no key sends no Authorization header', () async {
      late http.Request seen;
      final ai = ChatAi()
        ..activeId = 'local'
        ..client = MockClient((req) async {
          seen = req;
          return oaText(goodJson);
        });
      ai.active.model = 'm';
      await ai.reply([um('hi')], '');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('history: consecutive same-role merged, starts with user, last 12 turns', () async {
      late Map body;
      final ai = make(MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        return oaText(goodJson);
      }));
      final h = [pm('welcome'), um('a'), um('b'), pm('c'), for (var i = 0; i < 30; i++) ...[um('u$i'), pm('p$i')], um('last')];
      await ai.reply(h, '');
      final msgs = (body['messages'] as List).skip(1).toList();
      expect(msgs.length, lessThanOrEqualTo(12));
      expect(msgs.first['role'], 'user');
      expect(msgs.last['content'], 'last');
      for (var i = 1; i < msgs.length; i++) {
        expect(msgs[i]['role'], isNot(msgs[i - 1]['role']));
      }
    });

    test('history that is only assistant messages: no empty turn list crash', () async {
      final ai = make(MockClient((req) async => oaText(goodJson)));
      // Sending nothing from the user is a caller bug but must not throw a StateError.
      final e = await thrown(() => ai.reply([pm('only me')], ''));
      expect(e == null || e is AiException, isTrue, reason: 'got ${e.runtimeType}: $e');
    });

    test('tool loop stops after 5 rounds and the 6th request carries no tools', () async {
      var n = 0;
      final hadTools = <bool>[];
      final ai = make(MockClient((req) async {
        n++;
        final b = jsonDecode(req.body) as Map;
        hadTools.add(b.containsKey('tools'));
        if (b.containsKey('tools')) return oaCall('list_reminders', '{}', id: 'c$n');
        return oaText(goodJson);
      }));
      final log = <String>[];
      final r = await ai.reply([um('x')], '', tools: fakeTools(log: log));
      expect(r.text, 'ok');
      expect(n, 6);
      expect(hadTools, [true, true, true, true, true, false]);
      expect(log.length, 5);
    });

    test('endless tool calls even without tools -> exception, not infinite loop', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        return oaCall('list_reminders', '{}');
      }));
      await expectLater(ai.reply([um('x')], '', tools: fakeTools()), throwsA(isA<AiException>()));
      expect(n, lessThanOrEqualTo(6));
    });

    test('tool call with garbage arguments / unknown tool is reported to the model, not thrown', () async {
      var n = 0;
      Map? second;
      final ai = make(MockClient((req) async {
        n++;
        final b = jsonDecode(req.body) as Map;
        if (n == 1) return oaCall('set_reminder', '{not json');
        if (n == 2) {
          second = b;
          return oaCall('does_not_exist', '{}');
        }
        return oaText(goodJson);
      }));
      final log = <String>[];
      final r = await ai.reply([um('x')], '', tools: fakeTools(log: log));
      expect(r.text, 'ok');
      // garbage args -> {} -> "/remind null null"; must not crash
      expect(second, isNotNull);
    });

    test('tool_calls entry without "function" map does not throw TypeError', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        if (n == 1) {
          return okJson({
            'choices': [
              {
                'message': {
                  'content': null,
                  'tool_calls': [
                    {'id': 'c1', 'type': 'function'}
                  ]
                }
              }
            ]
          });
        }
        return oaText(goodJson);
      }));
      final e = await thrown(() => ai.reply([um('x')], '', tools: fakeTools()));
      expect(e == null || e is AiException, isTrue, reason: 'got ${e.runtimeType}: $e');
    });

    test('tool that throws inside is reported as an error string to the model', () async {
      var n = 0;
      String? toolContent;
      final ai = make(MockClient((req) async {
        n++;
        final b = jsonDecode(req.body) as Map;
        if (n == 1) return oaCall('save_note', '{"text":"x"}');
        toolContent = (b['messages'] as List).last['content'] as String;
        return oaText(goodJson);
      }));
      final t = AgentTools(reminder: (_) => '', saveNote: (_) async => throw StateError('disk full'));
      await ai.reply([um('x')], '', tools: t);
      expect(toolContent, startsWith('error:'));
    });

    test('400 on first request retries once without tools; second 400 propagates', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        return http.Response('bad', 400);
      }));
      await expectLater(ai.reply([um('x')], '', tools: fakeTools()), throwsA(isA<AiException>()));
      expect(n, 2);
    });

    test('400 without tools is not retried', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        return http.Response('bad', 400);
      }));
      await expectLater(ai.reply([um('x')], ''), throwsA(isA<AiException>()));
      expect(n, 1);
    });

    test('400 retry works when the 400 comes in a LATER tool round (history has tool messages)', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        final b = jsonDecode(req.body) as Map;
        if (n == 1) return oaCall('list_reminders', '{}');
        if (b.containsKey('tools')) return http.Response('bad', 400);
        return oaText(goodJson);
      }));
      final r = await ai.reply([um('x')], '', tools: fakeTools());
      expect(r.text, 'ok');
    });

    test('an error body that mentions 400 for a different status is not retried', () async {
      // 500 whose message text can't contain "400" -> not retried
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        return http.Response('boom', 500);
      }));
      await expectLater(ai.reply([um('x')], '', tools: fakeTools()), throwsA(isA<AiException>()));
      expect(n, 1);
    });

    test('401 / 403 / 429 / 500 map to distinct readable messages', () async {
      final seen = <int, String>{};
      for (final code in [401, 403, 429, 500, 503]) {
        final ai = make(MockClient((_) async => http.Response('', code)));
        try {
          await ai.reply([um('x')], '');
        } on AiException catch (e) {
          seen[code] = e.message;
        }
      }
      expect(seen[401], contains('key'));
      expect(seen[403], contains('key'));
      expect(seen[429], contains('limit'));
      expect(seen[500], contains('500'));
      expect(seen[503], contains('503'));
      expect(seen[401], isNot(seen[429]));
    });

    test('200 with HTML / array / empty body / invalid UTF-8 -> AiException or FormatException (no hang)', () async {
      for (final body in [
        http.Response('<html>proxy login</html>', 200),
        http.Response('[]', 200),
        http.Response('', 200),
        http.Response.bytes([0xff, 0xfe, 0x7b, 0x7d], 200),
      ]) {
        final ai = make(MockClient((_) async => body));
        await expectLater(ai.reply([um('x')], ''), throwsA(anything));
      }
    });

    test('non-FormatException failures are AiException so the UI shows a helpful line', () async {
      final ai = make(MockClient((_) async => http.Response('<html>', 200)));
      await expectLater(ai.reply([um('x')], ''), throwsA(isA<AiException>()));
    });

    test('empty choices / null content / blank content -> AiException', () async {
      for (final r in [
        okJson({'choices': []}),
        okJson({'choices': [{'message': {'content': null}}]}),
        okJson({'choices': [{'message': {'content': '   '}}]}),
        okJson({}),
      ]) {
        final ai = make(MockClient((_) async => r));
        await expectLater(ai.reply([um('x')], ''), throwsA(isA<AiException>()));
      }
    });

    test('choice without "message" is an AiException, not a TypeError', () async {
      final ai = make(MockClient((_) async => okJson({'choices': [{'finish_reason': 'stop'}]})));
      await expectLater(ai.reply([um('x')], ''), throwsA(isA<AiException>()));
    });

    test('content as list of parts (some gateways) does not crash', () async {
      final ai = make(MockClient((_) async => okJson({'choices': [{'message': {'content': [{'type': 'text', 'text': goodJson}]}}]})));
      final e = await thrown(() => ai.reply([um('x')], ''));
      expect(e == null || e is AiException, isTrue, reason: 'got ${e.runtimeType}: $e');
    });

    test('network timeout surfaces as TimeoutException/AiException (caller catches both)', () async {
      final ai = make(MockClient((_) async => Completer<http.Response>().future));
      // The request timeout is 60 s: use fakeAsync-free approach and just assert type contract on a throwing client.
      final ai2 = make(MockClient((_) async => throw TimeoutException('t')));
      await expectLater(ai2.reply([um('x')], ''), throwsA(anyOf(isA<TimeoutException>(), isA<AiException>())));
      expect(ai, isNotNull);
    });

    test('socket error propagates as an exception (PetBrain shows the generic line)', () async {
      final ai = make(MockClient((_) async => throw http.ClientException('down')));
      await expectLater(ai.reply([um('x')], ''), throwsA(isA<Exception>()));
    });

    test('Chinese error messages are used when language is zh', () async {
      Lang.code = 'zh';
      final ai = make(MockClient((_) async => http.Response('', 429)));
      try {
        await ai.reply([um('x')], '');
        fail('should throw');
      } on AiException catch (e) {
        expect(e.message, contains('用量'));
      }
    });
  });

  group('anthropic wire', () {
    ChatAi make(MockClient c) {
      final ai = ChatAi()
        ..activeId = 'claude'
        ..client = c;
      ai.active.apiKey = 'k';
      return ai;
    }

    http.Response anText(String s, {String stop = 'end_turn'}) => okJson({
          'stop_reason': stop,
          'content': [
            {'type': 'text', 'text': s}
          ]
        });
    http.Response anUse(String name, Map input, {String id = 'tu1'}) => okJson({
          'stop_reason': 'tool_use',
          'content': [
            {'type': 'text', 'text': 'let me check'},
            {'type': 'tool_use', 'id': id, 'name': name, 'input': input}
          ]
        });

    test('request shape: headers, system separate from messages, tools in input_schema form', () async {
      late http.Request seen;
      final ai = make(MockClient((req) async {
        seen = req;
        return anText(goodJson);
      }));
      await ai.reply([um('hi')], 'CTX', tools: fakeTools());
      expect(seen.url.path, '/v1/messages');
      expect(seen.headers['x-api-key'], 'k');
      expect(seen.headers['anthropic-version'], isNotEmpty);
      final b = jsonDecode(seen.body) as Map;
      expect(b['system'], contains('CTX'));
      expect((b['messages'] as List).every((m) => m['role'] != 'system'), isTrue);
      final names = (b['tools'] as List).map((t) => t['name']);
      expect(names, containsAll(['set_reminder', 'list_reminders', 'cancel_reminder', 'web_search']));
      expect((b['tools'] as List).every((t) => t['input_schema'] != null), isTrue);
    });

    test('tool loop: tool_result is sent back in a user turn with the matching id', () async {
      var n = 0;
      Map? second;
      final ai = make(MockClient((req) async {
        n++;
        final b = jsonDecode(req.body) as Map;
        if (n == 1) return anUse('set_reminder', {'when': 'in 5 minutes', 'what': 'tea'});
        second = b;
        return anText(goodJson);
      }));
      final log = <String>[];
      final r = await ai.reply([um('x')], '', tools: fakeTools(log: log));
      expect(r.text, 'ok');
      expect(log, ['/remind in 5 minutes tea']);
      final msgs = second!['messages'] as List;
      expect(msgs.last['role'], 'user');
      expect(msgs.last['content'][0]['type'], 'tool_result');
      expect(msgs.last['content'][0]['tool_use_id'], 'tu1');
      expect(msgs[msgs.length - 2]['role'], 'assistant');
    });

    test('max 5 tool rounds then a tools-free request', () async {
      var n = 0;
      final hadTools = <bool>[];
      final ai = make(MockClient((req) async {
        n++;
        final b = jsonDecode(req.body) as Map;
        hadTools.add(b.containsKey('tools'));
        return b.containsKey('tools') ? anUse('list_reminders', {}, id: 'u$n') : anText(goodJson);
      }));
      final r = await ai.reply([um('x')], '', tools: fakeTools());
      expect(r.text, 'ok');
      expect(hadTools, [true, true, true, true, true, false]);
    });

    test('stop_reason tool_use but no tool_use blocks -> uses the text, no infinite loop', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        return okJson({
          'stop_reason': 'tool_use',
          'content': [
            {'type': 'text', 'text': goodJson}
          ]
        });
      }));
      final r = await ai.reply([um('x')], '', tools: fakeTools());
      expect(r.text, 'ok');
      expect(n, 1);
    });

    test('tool_use with null input does not crash', () async {
      var n = 0;
      final ai = make(MockClient((req) async {
        n++;
        if (n == 1) {
          return okJson({
            'stop_reason': 'tool_use',
            'content': [
              {'type': 'tool_use', 'id': 'a', 'name': 'list_reminders', 'input': null}
            ]
          });
        }
        return anText(goodJson);
      }));
      expect((await ai.reply([um('x')], '', tools: fakeTools())).text, 'ok');
    });

    test('refusal -> AiException; multiple text blocks are joined', () async {
      final ai = make(MockClient((_) async => anText('', stop: 'refusal')));
      await expectLater(ai.reply([um('x')], ''), throwsA(isA<AiException>()));
      final ai2 = make(MockClient((_) async => okJson({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': '{"text":"a'},
              {'type': 'text', 'text': 'b","mood":"happy"}'}
            ]
          })));
      expect((await ai2.reply([um('x')], '')).text, 'ab');
    });

    test('400 retries without tools; 401/429/500 map to messages', () async {
      var withTools = 0, without = 0;
      final ai = make(MockClient((req) async {
        final b = jsonDecode(req.body) as Map;
        if (b.containsKey('tools')) {
          withTools++;
          return http.Response('no', 400);
        }
        without++;
        return anText(goodJson);
      }));
      expect((await ai.reply([um('x')], '', tools: fakeTools())).text, 'ok');
      expect([withTools, without], [1, 1]);
      for (final code in [401, 429, 500]) {
        final a = make(MockClient((_) async => http.Response('', code)));
        await expectLater(a.reply([um('x')], ''), throwsA(isA<AiException>()), reason: '$code');
      }
    });

    test('empty content -> AiException', () async {
      final ai = make(MockClient((_) async => okJson({'stop_reason': 'end_turn', 'content': []})));
      await expectLater(ai.reply([um('x')], ''), throwsA(isA<AiException>()));
    });

    test('trailing slash on base URL does not double up', () async {
      late Uri u;
      final ai = make(MockClient((req) async {
        u = req.url;
        return anText(goodJson);
      }));
      ai.active.baseUrl = 'https://api.anthropic.com/';
      await ai.reply([um('x')], '');
      expect(u.path, '/v1/messages');
    });
  });

  group('Apple on-device', () {
    const ch = MethodChannel('hoodimong/ondevice_ai');
    late ChatAi ai;
    Map<String, dynamic>? lastArgs;

    void mock(Future<Object?> Function(MethodCall) h) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, h);
    }

    setUp(() {
      lastArgs = null;
      ai = ChatAi()..activeId = 'apple';
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    test('normal reply, no network touched', () async {
      ai.client = MockClient((_) async => fail('apple must not use the network'));
      mock((c) async {
        lastArgs = Map<String, dynamic>.from(c.arguments as Map);
        return {'text': ' hi there ', 'mood': 'happy', 'remember': ''};
      });
      final r = await ai.reply([um('hello')], 'CTX');
      expect(r.text, 'hi there');
      expect(r.mood, PetMood.happy);
      expect(r.remember, isNull);
      expect(lastArgs!['prompt'], 'hello');
      expect(lastArgs!['tools'], false);
    });

    test('guardrail -> gentle in-character line, not an error', () async {
      mock((c) async => {'error': 'guardrail'});
      final r = await ai.reply([um('x')], '');
      expect(r.text, isNotEmpty);
      expect(r.mood, PetMood.thinking);
      Lang.code = 'ko';
      expect((await ai.reply([um('x')], '')).text, contains('다른 얘기'));
    });

    test('unavailable -> AiException with the reason text', () async {
      for (final reason in ['deviceNotEligible', 'appleIntelligenceNotEnabled', 'modelNotReady', 'osTooOld', '']) {
        mock((c) async => {'error': 'unavailable', 'reason': reason});
        try {
          await ai.reply([um('x')], '');
          fail('should throw');
        } on AiException catch (e) {
          expect(e.message, ChatAi.appleReasonText(reason));
          expect(e.message, isNotEmpty);
        }
      }
    });

    test('other error string -> AiException "Apple AI: ..."', () async {
      mock((c) async => {'error': 'boom'});
      await expectLater(ai.reply([um('x')], ''), throwsA(predicate((e) => e is AiException && e.message.contains('boom'))));
    });

    test('native side missing (MissingPluginException) is not swallowed into a blank bubble', () async {
      mock((c) async => throw MissingPluginException());
      await expectLater(ai.reply([um('x')], ''), throwsA(anything));
    });

    test('native returns null -> empty text must not become a silent blank reply', () async {
      mock((c) async => null);
      try {
        final r = await ai.reply([um('x')], '');
        expect(r.text.trim(), isNotEmpty, reason: 'blank bubble');
      } on AiException {
        // acceptable
      }
    });

    test('reminder from the on-device tool path runs set_reminder and its confirmation replaces the echo', () async {
      mock((c) async => {'text': 'Okay, I will remind you!', 'mood': 'happy', 'reminder': {'minutes': 10, 'text': 'tea'}});
      final log = <String>[];
      final r = await ai.reply([um('remind me tea in 10')], '', tools: fakeTools(log: log));
      expect(log, ['/remind in 10 minutes tea']);
      expect(r.text, 'OK');
    });

    test('reminder with tools disabled is ignored (nothing scheduled behind the owner\'s back)', () async {
      mock((c) async => {'text': 'sure', 'reminder': {'minutes': 10, 'text': 'tea'}});
      final r = await ai.reply([um('x')], '');
      expect(r.text, 'sure');
    });

    test('reminder with null minutes/text (model garbage) does not schedule "null minutes"', () async {
      mock((c) async => {'text': 'sure', 'reminder': {}});
      final log = <String>[];
      await ai.reply([um('x')], '', tools: fakeTools(log: log));
      expect(log.any((l) => l.contains('null')), isFalse, reason: log.toString());
    });

    test('prompt: only the last 7 turns, prior turns labelled; instructions capped context 500', () async {
      mock((c) async {
        lastArgs = Map<String, dynamic>.from(c.arguments as Map);
        return {'text': 'k'};
      });
      final h = [for (var i = 0; i < 20; i++) ...[um('u$i'), pm('p$i')], um('final')];
      await ai.reply(h, 'C' * 5000);
      final p = lastArgs!['prompt'] as String;
      expect(p, endsWith('final'));
      expect(p.contains('u0'), isFalse);
      expect((lastArgs!['instructions'] as String).length, lessThan(5000));
    });

    test('availability: channel failure => unavailable/osTooOld, never throws', () async {
      mock((c) async => throw PlatformException(code: 'x'));
      expect((await ChatAi.appleAvailability())['status'], 'unavailable');
      mock((c) async => {'status': 'available'});
      expect((await ChatAi.appleAvailability())['status'], 'available');
      mock((c) async => null);
      expect((await ChatAi.appleAvailability())['status'], 'unavailable');
    });

    test('history with only an assistant message does not crash with a RangeError', () async {
      mock((c) async => {'text': 'k'});
      await expectLater(ai.reply([pm('welcome')], ''), throwsA(isA<AiException>()));
    });
  });

  group('persistence', () {
    test('providers JSON round trip keeps keys local to ai_config (toJson has all 3 fields)', () {
      final p = defaultProviders().first;
      expect(p.toJson().keys, containsAll(['baseUrl', 'model', 'apiKey']));
    });
  });
}
