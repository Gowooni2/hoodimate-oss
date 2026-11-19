import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/agent_tools.dart';
import 'package:hoodimong/services/chat_ai.dart';

void main() {
  setUp(() => Lang.code = 'en');

  test('DuckDuckGo HTML results are read into title / link / snippet', () {
    const html = '''
<div class="result__body"><h2><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fnews&amp;rut=x">Example <b>News</b></a></h2>
<a class="result__snippet" href="#">Big &amp; <b>fresh</b> story</a></div>''';
    final out = AgentTools.parseDuckDuckGo(html);
    // the live page's class list (2026-10)
    expect(AgentTools.parseDuckDuckGo(html.replaceFirst('class="result__body"', 'class="links_main links_deep result__body"')),
        contains('https://example.com/news'));
    expect(out, contains('Example News'));
    expect(out, contains('https://example.com/news'));
    expect(out, contains('Big & fresh story'));
  });

  test('saved live DuckDuckGo page parses (skipped if absent)', () {
    final f = File('test/fixtures/ddg.html');
    if (!f.existsSync()) return;
    final out = AgentTools.parseDuckDuckGo(f.readAsStringSync());
    expect(out, contains('open-meteo.com'));
  });

  test('page text drops scripts and tags', () {
    final t = AgentTools.pageText('<html><script>x=1</script><p>Hello</p><p>World &amp; more</p></html>');
    expect(t, 'Hello\nWorld & more');
  });

  test('OpenAI-style tool call: model asks for a reminder, then answers', () async {
    var round = 0;
    final calls = <String>[];
    final ai = ChatAi()
      ..activeId = 'gemini'
      ..client = MockClient((req) async {
        round++;
        final body = jsonDecode(req.body) as Map;
        if (round == 1) {
          expect((body['tools'] as List).map((t) => t['function']['name']), contains('set_reminder'));
          return http.Response.bytes(utf8.encode(jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': null, 'tool_calls': [
                {'id': 'c1', 'type': 'function', 'function': {'name': 'set_reminder', 'arguments': '{"when":"in 10 minutes","what":"tea"}'}}
              ]}}
            ]
          })), 200);
        }
        final msgs = body['messages'] as List;
        expect(msgs.last['role'], 'tool');
        expect(msgs.last['content'], 'OK set tea');
        return http.Response.bytes(utf8.encode(jsonEncode({
          'choices': [
            {'message': {'role': 'assistant', 'content': '{"text":"Set! Tea in 10 min ☕","mood":"happy","project":null,"remember":null}'}}
          ]
        })), 200);
      });
    ai.active
      ..apiKey = 'k'
      ..model = 'm';
    final tools = AgentTools(
        reminder: (cmd) {
          calls.add(cmd);
          return 'OK set tea';
        },
        saveNote: (t) async => 'saved');
    final r = await ai.reply([ChatMessage(text: 'remind me about tea in 10', fromUser: true, at: DateTime.now())], '',
        tools: tools, onTool: (n) => calls.add('tool:$n'));
    expect(calls, ['tool:set_reminder', '/remind in 10 minutes tea']);
    expect(r.text, 'Set! Tea in 10 min ☕');
    expect(r.mood, PetMood.happy);
  });

  test('a model that rejects tools gets the question again without them', () async {
    var sawTools = false;
    final ai = ChatAi()
      ..activeId = 'ollama'
      ..client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map;
        if (body.containsKey('tools')) {
          sawTools = true;
          return http.Response('{"error":"tools not supported"}', 400);
        }
        return http.Response.bytes(utf8.encode(jsonEncode({
          'choices': [
            {'message': {'content': '{"text":"Hi!","mood":"waving"}'}}
          ]
        })), 200);
      });
    ai.active.model = 'llama';
    final r = await ai.reply([ChatMessage(text: 'hi', fromUser: true, at: DateTime.now())], '',
        tools: AgentTools(reminder: (_) => '', saveNote: (_) async => ''));
    expect(sawTools, isTrue);
    expect(r.text, 'Hi!');
  });
}
