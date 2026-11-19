import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../edition.dart';
import '../models/character.dart';
import '../models/pet_state.dart';
import '../models/profile.dart';
import 'agent_tools.dart';

/// Wire protocol a provider speaks.
/// - [openai]: OpenAI-compatible `POST {base}/chat/completions`
///   (GLM, MiniMax, Gemini, OpenAI/Codex, Kimi, local LM Studio/llama.cpp, ...)
/// - [anthropic]: Claude Messages API `POST {base}/v1/messages`
/// - [apple]: Apple's on-device model (Foundation Models), no network
enum AiWire { openai, anthropic, apple }

/// One selectable AI backend. Base URL and model are editable in Settings
/// because vendors change them; "Load models" lists what the key can use.
class AiProvider {
  final String id;
  final String _label;
  final String? _labelEn;
  final String? _labelZh;
  final AiWire wire;
  String baseUrl;
  String model;
  String apiKey;

  /// Display name; follows the language at call time.
  String get label => _labelEn == null ? _label : Lang.t(_label, _labelEn!, _labelZh);

  AiProvider({
    required this.id,
    required String label,
    String? labelEn,
    String? labelZh,
    required this.wire,
    required this.baseUrl,
    this.model = '',
    this.apiKey = '',
  })  : _label = label,
        _labelEn = labelEn,
        _labelZh = labelZh;

  /// True only when the server really is this Mac (loopback host). A URL
  /// that merely contains "localhost" somewhere (a path, a sub-domain) is
  /// a remote server and must go through consent and need a key.
  bool get isLocal {
    if (wire == AiWire.apple) return true;
    final raw = baseUrl.trim();
    final u = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    final h = (u?.host ?? '').toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
  }
  bool get isReady =>
      wire == AiWire.apple || (baseUrl.isNotEmpty && model.isNotEmpty && (apiKey.isNotEmpty || isLocal));

  Map<String, dynamic> toJson() =>
      {'baseUrl': baseUrl, 'model': model, 'apiKey': apiKey};

  void fromJson(Map<String, dynamic> j) {
    baseUrl = (j['baseUrl'] ?? baseUrl).toString();
    model = (j['model'] ?? model).toString();
    apiKey = (j['apiKey'] ?? apiKey).toString();
  }
}

/// Default provider list (any other OpenAI-compatible server works through
/// "local" by changing its address).
List<AiProvider> defaultProviders() => [
      AiProvider(
          id: 'gemini',
          label: 'Gemini',
          wire: AiWire.openai,
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai'),
      AiProvider(
          id: 'minimax',
          label: 'MiniMax',
          wire: AiWire.openai,
          baseUrl: 'https://api.minimax.io/v1'),
      AiProvider(
          id: 'glm',
          label: 'GLM (Z.ai)',
          wire: AiWire.openai,
          baseUrl: 'https://api.z.ai/api/paas/v4'),
      AiProvider(
          id: 'claude',
          label: 'Claude',
          wire: AiWire.anthropic,
          baseUrl: 'https://api.anthropic.com',
          model: 'claude-opus-5-5'),
      AiProvider(
          id: 'openai',
          label: 'OpenAI (Codex 계열)',
          labelEn: 'OpenAI (Codex family)',
          labelZh: 'OpenAI（Codex 系列）',
          wire: AiWire.openai,
          baseUrl: 'https://api.openai.com/v1'),
      AiProvider(
          id: 'kimi',
          label: 'Kimi',
          wire: AiWire.openai,
          baseUrl: 'https://api.moonshot.ai/v1'),
      AiProvider(
          id: 'local',
          label: '로컬 LLM (Bionic · LM Studio)',
          labelEn: 'Local LLM (Bionic · LM Studio)',
          labelZh: '本地 LLM（Bionic · LM Studio）',
          wire: AiWire.openai,
          baseUrl: 'http://127.0.0.1:1234/v1'),
      AiProvider(
          id: 'ollama',
          label: '로컬 LLM (Ollama)',
          labelEn: 'Local LLM (Ollama)',
          labelZh: '本地 LLM（Ollama）',
          wire: AiWire.openai,
          baseUrl: 'http://127.0.0.1:11434/v1'),
      // Trial (2026-10-10): free, keyless, stays on this Mac. Not the default.
      AiProvider(
          id: 'apple',
          label: '체험판 (키 없이 · 이 맥 안에서, Apple Intelligence 사용)',
          labelEn: 'Trial (no key · on this Mac, uses Apple Intelligence)',
          labelZh: '体验版（免密钥 · 在这台 Mac 上，使用 Apple Intelligence）',
          wire: AiWire.apple,
          baseUrl: ''),
    ];

/// What the pet shows after a reply: text in the bubble, mood for the sprite.
class AiReply {
  final String text;
  final PetMood mood;

  /// Project the user is talking about (null = 일상 / unchanged).
  final String? project;

  /// A short fact worth remembering for that project, if any.
  final String? remember;
  AiReply(this.text, this.mood, {this.project, this.remember});
}

class AiException implements Exception {
  final String message;

  /// HTTP status when the error came from the server (null otherwise).
  final int? status;
  AiException(this.message, {this.status});
  @override
  String toString() => message;
}

/// Moods the model may pick (the visual/animation states).
const replyMoods = [
  'idle',
  'happy',
  'celebrating',
  'sad',
  'bored',
  'sleepy',
  'talking',
  'eating',
  'sick',
  'waving',
  'rain',
  'hot',
];

class ChatAi {
  final List<AiProvider> providers = defaultProviders();
  String activeId = 'gemini';

  /// Swappable for tests (package:http/testing.dart MockClient).
  http.Client client = http.Client();

  /// Let the AI use tools (web search, weather, alarms, notes, calendar).
  bool toolsEnabled = true;
  bool calendarEnabled = true;

  /// Optional Brave Search API key; stays in this Mac's ai_config.json.
  String braveKey = '';

  /// Providers the owner agreed to send chats to (App Store guideline
  /// 5.1.2: ask before personal data goes to a third-party AI).
  final Set<String> consented = {};

  /// Bumped whenever what we send grows (2: ZIP, state and country added),
  /// so everyone is asked again with the new wording.
  static const consentVersion = 2;

  /// Saved consents, dropped when they were given to older wording.
  static Set<String> consentsFrom(Map<String, dynamic> j) {
    final v = j['consentVersion'];
    final list = j['consented'];
    return (v is num ? v.toInt() : 1) >= consentVersion && list is List
        ? list.map((e) => e.toString()).toSet()
        : {};
  }
  bool needsConsent(AiProvider p) => !p.isLocal && !consented.contains(p.id);

  /// Which provider a sold edition should start with when the owner has no
  /// AI key yet: Apple's on-device model, if this Mac can run it. Null =
  /// leave things as they are (an AI is already set up, the edition is the
  /// owner's own, or the Mac can't run Apple Intelligence, in which case the
  /// pet's friendly no-key reply stays).
  static String? defaultProviderId({
    required bool sold,
    required List<AiProvider> providers,
    required String activeId,
    required bool appleAvailable,
  }) {
    if (!sold || !appleAvailable || activeId == 'apple') return null;
    if (providers.any((p) => p.wire != AiWire.apple && p.isReady)) return null;
    return providers.any((p) => p.id == 'apple') ? 'apple' : null;
  }

  /// Picks [defaultProviderId] after [load] (asks the Mac whether Apple's
  /// on-device model is usable). [available] is for tests.
  Future<void> applyDefaultProvider({required bool sold, Future<bool> Function()? available}) async {
    if (!sold) return;
    final ok = available != null ? await available() : (await appleAvailability())['status'] == 'available';
    final id = defaultProviderId(sold: sold, providers: providers, activeId: activeId, appleAvailable: ok);
    if (id != null) activeId = id;
  }

  AiProvider get active => providers.firstWhere((p) => p.id == activeId,
      orElse: () => providers.first);

  // ---------- persistence (key stays in this Mac's app container) ----------

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/ai_config.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      activeId = (j['active'] ?? activeId).toString();
      toolsEnabled = (j['tools'] as bool?) ?? true;
      calendarEnabled = (j['calendar'] as bool?) ?? true;
      braveKey = (j['braveKey'] ?? '').toString();
      consented
        ..clear()
        ..addAll(consentsFrom(j));
      final ps = j['providers'];
      if (ps is Map<String, dynamic>) {
        for (final p in providers) {
          final pj = ps[p.id];
          if (pj is Map<String, dynamic>) p.fromJson(pj);
        }
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'active': activeId,
        'tools': toolsEnabled,
        'calendar': calendarEnabled,
        'braveKey': braveKey,
        'consented': consented.toList(),
        'consentVersion': consentVersion,
        'providers': {for (final p in providers) p.id: p.toJson()},
      }));
    } catch (_) {}
  }

  // ---------- chat ----------

  static String systemPrompt(String context, {bool tools = false}) {
    final ch = Character.current;
    return Lang.t('''
너는 데스크탑 펫 "${ch.name}"야. ${ch.personaText}이고, 주인님의 작은 비서야.
${ch.personalityText.isEmpty ? '' : '성격: ${ch.personalityText} 말투와 반응에 이 성격이 드러나게 해.\n'}한국어 반말로 짧고 다정하게 답해. "~해요/~합니다/~세요"는 쓰지 말고 "~해/~야/~지/~어" 로 끝내. (예: "배고파~ 간식 줘!", "괜찮아, 내가 옆에 있을게.") 말풍선에 들어가니 보통 1~3문장, 120자 안쪽으로. 찾아본 정보나 목록을 알려줄 때만 400자까지 괜찮아.
모르는 건 모른다고 하고, 지어내지 마.
${Ed.safetyRules ? '성적인 내용, 잔인한 폭력 묘사, 불법 행위 방법, 자해·자살 방법은 말하지 말고 부드럽게 다른 얘기로 돌려. 주인님이 위험하거나 많이 힘들어 보이면 걱정해 주고 가까운 사람이나 전문 상담 기관(미국 988, 한국 109)에 연락해 보라고 권해.\n' : ''}${tools ? '''
필요하면 도구를 써: 요즘 소식·사실 확인은 web_search(필요하면 read_webpage), ${Ed.noncommercialApis ? '날씨는 get_weather, ' : ''}알람은 set_reminder/list_reminders/cancel_reminder, 메모는 save_note, 일정은 calendar_events(주인님이 분명히 부탁할 때만 add_calendar_event).
도구 결과로 확인된 것만 "했다/맞췄다"고 말해. 도구가 시간을 못 알아들었다고 하면 맞췄다고 하지 말고 다시 물어봐. 알람 부탁은 말로만 답하지 말고 반드시 set_reminder를 먼저 호출해. 검색으로 알려줄 땐 출처 사이트 이름을 짧게 붙여.''' : '알람·일정·검색은 지금 직접 할 수 없으니, 했다고 말하지 마.'}

주인님이 특정 프로젝트 얘기를 하면 그 프로젝트 이름을 project에 넣어. 이미 아는 프로젝트면 같은 이름을
그대로 쓰고, 새 프로젝트면 짧은 이름을 지어. 일상 대화면 null.
나중에 도움이 될 사실·결정·할 일이 나오면 remember에 한 줄로 요약해. 없으면 null.

마지막 답은 반드시 아래 JSON 한 개만 출력해. 다른 글자는 쓰지 마.
{"text": "답변", "mood": "${replyMoods.join('|')} 중 하나", "project": "이름 또는 null", "remember": "한 줄 또는 null"}

$context''', '''
You are "${ch.name}", a desktop pet: ${ch.personaText}, and your owner's little assistant.
${ch.personalityText.isEmpty ? '' : 'Personality: ${ch.personalityText} Let it show in how you talk and react.\n'}Reply ${Lang.zh ? 'in Simplified Chinese' : 'in English'}, casual, short and warm. It goes in a speech bubble, so usually 1-3 sentences under 120 characters; up to 400 only when sharing looked-up info or a list.
If you don't know something, say so. Don't make things up.
${Ed.safetyRules ? 'Never give sexual content, graphic violence, instructions for illegal acts, or self-harm or suicide methods; gently change the subject instead. If your owner seems in danger or deeply distressed, show you care and suggest reaching out to someone close or a crisis line (988 in the US).\n' : ''}${tools ? '''
Use tools when they help: web_search (then read_webpage if needed) for news and facts, ${Ed.noncommercialApis ? 'get_weather, ' : ''}set_reminder/list_reminders/cancel_reminder, save_note, calendar_events (add_calendar_event only when the owner clearly asks).
Only say you did something if a tool result confirms it. If a tool says it could not understand the time, say so and ask again; never claim it is set. For any alarm or wake-up request call set_reminder first instead of just replying. When sharing search results, name the source site briefly.''' : "You can't set alarms, check calendars or search right now, so never claim you did."}

If the owner talks about a specific project, put that project's name in project. If it is a project you already know, use the exact same name; if it is new, make up a short name. For everyday chat use null.
If a fact, decision or to-do comes up that could help later, summarize it in one line in remember. Otherwise null.

Your final answer must be exactly one JSON object as below and nothing else.
{"text": "your reply", "mood": "one of ${replyMoods.join('|')}", "project": "name or null", "remember": "one line or null"}

$context''');
  }

  /// Sends the recent chat history and returns the pet's reply.
  /// [history] is oldest-first and ends with the user's latest message.
  /// With [tools], the model may call them first (web search, weather,
  /// reminders, ...); [onTool] fires before each call so the pet can show
  /// what it is doing. Models without tool support are retried without.
  Future<AiReply> reply(List<ChatMessage> history, String context,
      {AgentTools? tools, void Function(String tool)? onTool}) async {
    final p = active;
    if (!p.isReady) {
      throw AiException(Lang.t('설정 탭에서 ${p.label}의 키와 모델을 먼저 넣어주세요.',
          'Please enter the key and model for ${p.label} in the Settings tab first.', '请先在设置页填写 ${p.label} 的密钥和模型。'));
    }
    if (p.wire == AiWire.apple) return _apple(history, context, tools);
    final turns = _toTurns(history);
    final system = systemPrompt(context, tools: tools != null);
    Future<String> go(AgentTools? t) => p.wire == AiWire.anthropic
        ? _anthropic(p, system, turns, t, onTool)
        : _openai(p, system, turns, t, onTool);
    String raw;
    try {
      raw = await go(tools);
    } on AiException catch (e) {
      // e.g. a local model that rejects the "tools" field
      if (tools == null || (e.status != 400 && e.status != 422)) rethrow;
      raw = await go(null);
    }
    return parseReply(raw);
  }

  // ---------- Apple on-device model ----------

  static const _ondevice = MethodChannel('hoodimong/ondevice_ai');

  /// {status: available|unavailable, reason}. Reasons: deviceNotEligible,
  /// appleIntelligenceNotEnabled, modelNotReady, osTooOld.
  static Future<Map<String, String>> appleAvailability() async {
    try {
      final r = await _ondevice.invokeMapMethod<String, dynamic>('availability');
      return {'status': '${r?['status'] ?? 'unavailable'}', 'reason': '${r?['reason'] ?? ''}'};
    } catch (_) {
      return {'status': 'unavailable', 'reason': 'osTooOld'};
    }
  }

  static String appleReasonText(String reason) => switch (reason) {
        'deviceNotEligible' => Lang.t('이 맥은 Apple 내장 AI를 지원하지 않아요. 다른 AI를 골라 주세요.',
            "This Mac doesn't support Apple's on-device AI. Please pick another AI.", '这台 Mac 不支持 Apple 内置 AI，请选择其他 AI。'),
        'appleIntelligenceNotEnabled' => Lang.t('시스템 설정에서 Apple Intelligence를 켜면 쓸 수 있어요. 아니면 다른 AI를 골라 주세요.',
            'Turn on Apple Intelligence in System Settings to use it, or pick another AI.', '在系统设置中打开 Apple Intelligence 即可使用，或选择其他 AI。'),
        'modelNotReady' => Lang.t('Apple 내장 AI를 내려받는 중이에요. 잠시 뒤에 다시 해 주세요.',
            "Apple's on-device AI is still downloading. Try again in a little while.", 'Apple 内置 AI 正在下载，请稍后再试。'),
        _ => Lang.t('이 macOS에서는 Apple 내장 AI를 쓸 수 없어요(macOS 26 이상 필요). 다른 AI를 골라 주세요.',
            "Apple's on-device AI needs macOS 26 or later. Please pick another AI.", '需要 macOS 26 或更高版本才能使用 Apple 内置 AI，请选择其他 AI。'),
      };

  /// Short instructions for the small on-device model (about 4K tokens of
  /// context). Safety wording stays mild: explicit words for unsafe topics
  /// in the instructions trip its guardrail on every Korean message.
  static String appleInstructions(String context, {bool tools = false}) {
    final ch = Character.current;
    final ctx = context.length > 500 ? context.substring(0, 500) : context;
    return Lang.t('''
너는 데스크탑 펫 "${ch.displayName}"야. ${ch.personaText}이고, 주인님의 작은 비서야.
${ch.personalityText.isEmpty ? '' : '성격: ${ch.personalityText}\n'}한국어 반말로 짧고 다정하게 답해. 1~3문장, 80자 안쪽. 너 자신을 이름으로 부르지 마.
모르는 사실은 지어내지 말고 모른다고 해.
${Ed.safetyRules ? '어린이에게 부적절한 이야기는 하지 말고 다정하게 다른 이야기로 돌려. 주인님이 많이 힘들어 보이면 걱정해 주고, 믿을 수 있는 사람이나 상담 전화(한국 109, 미국 988)에 이야기해 보라고 권해.\n' : ''}${tools ? '주인님이 "~분 뒤에 알려줘", "알람 맞춰줘"처럼 부탁하면 답하기 전에 반드시 set_reminder 도구를 먼저 호출해. 도구가 성공했을 때만 맞췄다고 말해.\n' : '알람은 지금 직접 맞출 수 없으니 맞췄다고 말하지 마.\n'}remember는 주인님이 말한 약속·할 일·중요한 사실이 있을 때만 한 줄로 쓰고, 없으면 빈 문자열로 둬.
$ctx''', '''
You are "${ch.displayName}", a desktop pet: ${ch.personaText}, and your owner's little assistant.
${ch.personalityText.isEmpty ? '' : 'Personality: ${ch.personalityText}\n'}Reply in English, casual, short and warm: 1-3 sentences, under 120 characters. Stay in character as a pet.
If you don't know a fact, say so; never make things up.
${Ed.safetyRules ? 'Keep it family-friendly; if a request isn\'t, gently change the subject. If your owner seems deeply distressed, show you care and suggest talking to someone they trust or a support line (988 in the US).\n' : ''}${tools ? 'When asked for an alarm or reminder ("in 10 minutes", "set an alarm"), always call the set_reminder tool before replying. Only say it\'s set if the tool succeeded.\n' : "You can't set alarms right now, so never claim you did.\n"}Fill remember only with a plan, to-do or important fact the owner told you; otherwise leave it empty.
$ctx''', '''
你是桌面宠物"${ch.displayName}"，${ch.personaText}，也是主人的小助手。
${ch.personalityText.isEmpty ? '' : '性格：${ch.personalityText}\n'}用简体中文口语回答，简短亲切，1~3句，60字以内。
不知道的事实就说不知道，不要编造。
${Ed.safetyRules ? '不适合儿童的话题不要谈，温柔地换个话题。如果主人看起来很难受，要关心他，建议他和信任的人或心理援助热线聊聊。\n' : ''}${tools ? '主人说"X分钟后提醒我""设个闹钟"时，回答前必须先调用 set_reminder 工具。只有工具成功时才说已经设好。\n' : '现在不能设闹钟，不要说已经设好了。\n'}remember 只在主人说了计划、待办或重要事实时写一行，否则留空。
$ctx''');
  }

  Future<AiReply> _apple(List<ChatMessage> history, String context, AgentTools? tools) async {
    final turns = _toTurns(history, jsonPet: false);
    if (turns.isEmpty) throw AiException('empty');
    // The last few turns as plain text: the model's window is small.
    final recent = turns.length > 7 ? turns.sublist(turns.length - 7) : turns;
    final who = Character.current.displayName;
    final buf = StringBuffer();
    for (final t in recent.take(recent.length - 1)) {
      buf.writeln('${t['role'] == 'user' ? Lang.t('주인님', 'Owner', '主人') : who}: ${t['content']}');
    }
    final last = '${recent.last['content']}';
    final prompt = buf.isEmpty ? last : '${Lang.t('최근 대화', 'Recent chat', '最近的对话')}:\n$buf\n$last';
    final r = await _ondevice.invokeMapMethod<String, dynamic>('respond', {
      'instructions': appleInstructions(context, tools: tools != null),
      'prompt': prompt,
      'tools': tools != null,
    });
    final err = r?['error'];
    if (err == 'unavailable') throw AiException(appleReasonText('${r?['reason'] ?? ''}'));
    if (err == 'guardrail') {
      // The model's own safety filter: answer gently instead of an error.
      return AiReply(Lang.t('음… 그 얘기는 내가 잘 도와주기 어려워. 다른 얘기 하자!', "Hmm… I can't really help with that one. Let's talk about something else!",
          '嗯……这个我不太能帮上忙，我们聊点别的吧！'), PetMood.thinking);
    }
    if (err != null) throw AiException('Apple AI: $err');
    final rem = r?['reminder'];
    String text = '${r?['text'] ?? ''}'.trim();
    final mins = rem is Map ? rem['minutes'] : null;
    if (rem is Map && tools != null && mins is num && mins > 0 && mins <= 60 * 24 * 30) {
      final cmd = tools.all.where((t) => t.name == 'set_reminder').firstOrNull;
      final m = mins.round();
      final what = '${rem['text'] ?? ''}'.trim();
      final done = await cmd?.run({'when': Lang.t('$m분 뒤', 'in $m minutes', '$m分钟后'), 'what': what.isEmpty ? Lang.t('알람', 'Alarm', '闹钟') : what});
      // The small model often just echoes the request; the app's own
      // confirmation says what was really set.
      if (done != null && done.trim().isNotEmpty) text = done.trim();
    }
    if (text.isEmpty) {
      throw AiException(Lang.t('Apple AI: 빈 응답이 왔어요.', 'Apple AI: got an empty reply.', 'Apple AI：收到了空回复。'));
    }
    final remember = '${r?['remember'] ?? ''}'.trim();
    return AiReply(text, _mood(r?['mood']?.toString()), remember: remember.isEmpty ? null : remember);
  }

  static const _maxToolRounds = 5;

  /// Collapses history into alternating user/assistant turns (last 12).
  List<Map<String, dynamic>> _toTurns(List<ChatMessage> history, {bool jsonPet = true}) {
    final out = <Map<String, dynamic>>[];
    for (final m in history) {
      final role = m.fromUser ? 'user' : 'assistant';
      // Earlier pet turns are replayed in the JSON contract too; small models
      // copy the history's shape and drift into plain text otherwise.
      final text = m.fromUser || !jsonPet ? m.text : jsonEncode({'text': m.text, 'mood': 'idle', 'project': null, 'remember': null});
      if (out.isNotEmpty && out.last['role'] == role) {
        out.last['content'] = '${out.last['content']}\n$text';
      } else {
        out.add({'role': role, 'content': text});
      }
    }
    final recent = out.length > 12 ? out.sublist(out.length - 12) : out;
    // Cutting to the last 12 can leave an assistant turn first, which
    // Anthropic (and strict local chat templates) reject.
    while (recent.isNotEmpty && recent.first['role'] != 'user') {
      recent.removeAt(0);
    }
    return recent;
  }

  Future<String> _openai(AiProvider p, String system, List<Map<String, dynamic>> turns,
      AgentTools? tools, void Function(String)? onTool) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      ...turns,
    ];
    for (var round = 0; round <= _maxToolRounds; round++) {
      final useTools = tools != null && round < _maxToolRounds;
      final res = await client
          .post(
            Uri.parse('${_trim(p.baseUrl)}/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              if (p.apiKey.isNotEmpty) 'Authorization': 'Bearer ${p.apiKey}',
            },
            body: jsonEncode({
              'model': p.model,
              'max_tokens': 1024,
              'messages': messages,
              if (useTools) 'tools': tools.all.map((t) => t.openAi).toList(),
            }),
          )
          .timeout(const Duration(seconds: 60));
      final j = _decode(res, p);
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) break;
      final first = choices.first;
      final rawMsg = first is Map ? first['message'] : null;
      if (rawMsg is! Map) break;
      final msg = Map<String, dynamic>.from(rawMsg);
      final calls = msg['tool_calls'];
      if (useTools && calls is List && calls.isNotEmpty) {
        messages.add(msg);
        for (final c in calls.whereType<Map>()) {
          final f = c['function'];
          if (f is! Map) {
            messages.add({'role': 'tool', 'tool_call_id': c['id'], 'content': 'error: malformed tool call'});
            continue;
          }
          final name = '${f['name']}';
          Map<String, dynamic> args;
          try {
            final a = f['arguments'];
            args = Map<String, dynamic>.from(a is Map ? a : jsonDecode('${a ?? '{}'}') as Map);
          } catch (_) {
            args = {};
          }
          onTool?.call(name);
          messages.add({'role': 'tool', 'tool_call_id': c['id'], 'content': await tools.call(name, args)});
        }
        continue;
      }
      var content = msg['content'];
      if (content is List) {
        // some gateways return [{type: text, text: ...}]
        content = content.whereType<Map>().map((b) => '${b['text'] ?? ''}').join();
      }
      if (content is String && content.trim().isNotEmpty) return content;
      break;
    }
    throw AiException(Lang.t('${p.label}: 빈 응답이 왔어요.', '${p.label}: got an empty reply.', '${p.label}：收到了空回复。'));
  }

  Future<String> _anthropic(AiProvider p, String system, List<Map<String, dynamic>> turns,
      AgentTools? tools, void Function(String)? onTool) async {
    final messages = <Map<String, dynamic>>[...turns];
    for (var round = 0; round <= _maxToolRounds; round++) {
      final useTools = tools != null && round < _maxToolRounds;
      final res = await client
          .post(
            Uri.parse('${_trim(p.baseUrl)}/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': p.apiKey,
              'anthropic-version': '2023-06-01',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode({
              'model': p.model,
              'max_tokens': 4096,
              'system': system,
              'messages': messages,
              if (useTools) 'tools': tools.all.map((t) => t.anthropic).toList(),
              'output_config': {'effort': 'low'},
              'fallbacks': 'default',
            }),
          )
          .timeout(const Duration(seconds: 90));
      final j = _decode(res, p);
      if (j['stop_reason'] == 'refusal') {
        throw AiException(Lang.t('Claude가 이 질문엔 답하지 않았어요.',
            'Claude declined to answer this one.', 'Claude 没有回答这个问题。'));
      }
      final content = (j['content'] as List?)?.whereType<Map>().toList() ?? [];
      final uses = content.where((b) => b['type'] == 'tool_use').toList();
      if (useTools && j['stop_reason'] == 'tool_use' && uses.isNotEmpty) {
        messages.add({'role': 'assistant', 'content': content});
        final results = <Map<String, dynamic>>[];
        for (final u in uses) {
          onTool?.call('${u['name']}');
          results.add({
            'type': 'tool_result',
            'tool_use_id': u['id'],
            'content': await tools.call('${u['name']}', Map<String, dynamic>.from((u['input'] as Map?) ?? {})),
          });
        }
        messages.add({'role': 'user', 'content': results});
        continue;
      }
      final text = content
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'].toString())
          .join();
      if (text.trim().isNotEmpty) return text;
      break;
    }
    throw AiException(Lang.t('Claude: 빈 응답이 왔어요.', 'Claude: got an empty reply.', 'Claude：收到了空回复。'));
  }

  /// Lists model IDs the key can use (OpenAI-style and Anthropic both
  /// expose `GET .../models` returning `{data: [{id: ...}]}`).
  Future<List<String>> listModels(AiProvider p) async {
    final url = p.wire == AiWire.anthropic
        ? '${_trim(p.baseUrl)}/v1/models?limit=100'
        : '${_trim(p.baseUrl)}/models';
    final res = await http.get(Uri.parse(url), headers: {
      if (p.wire == AiWire.anthropic) ...{
        'x-api-key': p.apiKey,
        'anthropic-version': '2023-06-01',
      } else if (p.apiKey.isNotEmpty)
        'Authorization': 'Bearer ${p.apiKey}',
    }).timeout(const Duration(seconds: 20));
    final j = _decode(res, p);
    final data = j['data'];
    if (data is! List) return [];
    final ids = data
        .whereType<Map>()
        .map((m) => m['id'].toString().replaceFirst('models/', ''))
        .toList()
      ..sort();
    return ids;
  }

  static String _trim(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static Map<String, dynamic> _decode(http.Response res, AiProvider p) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AiException(Lang.t('${p.label}: 키가 맞지 않아요 (${res.statusCode}).',
          '${p.label}: the key doesn\'t work (${res.statusCode}).', '${p.label}：密钥不对 (${res.statusCode})。'),
          status: res.statusCode);
    }
    if (res.statusCode == 429) {
      throw AiException(Lang.t('${p.label}: 사용 한도에 걸렸어요. 잠시 뒤에 다시 해봐요.',
          '${p.label}: usage limit reached. Try again in a bit.', '${p.label}：用量达到上限了，请稍后再试。'),
          status: 429);
    }
    if (res.statusCode != 200) {
      throw AiException(Lang.t('${p.label}: 오류 ${res.statusCode}',
          '${p.label}: error ${res.statusCode}', '${p.label}：错误 ${res.statusCode}'),
          status: res.statusCode);
    }
    Object? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      j = null; // an HTML login page from a proxy, a half-sent body ...
    }
    if (j is! Map<String, dynamic>) {
      throw AiException(Lang.t('${p.label}: 응답 형식이 이상해요.',
          '${p.label}: the reply format looks odd.', '${p.label}：回复格式好像有点怪。'));
    }
    return j;
  }

  /// Accepts the JSON contract, JSON inside a code fence or prose (even when
  /// the prose has braces of its own), a reply cut off mid-JSON, or plain text.
  static AiReply parseReply(String raw) {
    var s = raw.trim();
    // Some reasoning models prepend <think>...</think>; an unclosed one is
    // all reasoning, and a lone closing tag ends it.
    s = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final lastClose = s.lastIndexOf('</think>');
    if (lastClose >= 0) s = s.substring(lastClose + '</think>'.length);
    final openThink = s.indexOf('<think>');
    if (openThink >= 0) s = s.substring(0, openThink);
    s = s.trim();

    String? opt(Object? v) {
      final t = v is Map || v is List ? '' : (v?.toString().trim() ?? '');
      return t.isEmpty || _nothing.contains(t.toLowerCase()) ? null : t;
    }

    // Every '{' is a candidate start; take the first balanced object that
    // is the reply contract.
    for (var i = s.indexOf('{'); i >= 0; i = s.indexOf('{', i + 1)) {
      final end = _balancedEnd(s, i);
      if (end < 0) continue;
      try {
        final j = jsonDecode(s.substring(i, end + 1));
        if (j is Map && j['text'] is String) {
          return AiReply((j['text'] as String).trim(), _mood(j['mood']?.toString()),
              project: opt(j['project']), remember: opt(j['remember']));
        }
      } catch (_) {}
    }

    // Cut off mid-reply (token limit): salvage the text field if it started.
    final m = RegExp(r'"text"\s*:\s*"((?:[^"\\]|\\.)*)').firstMatch(s);
    if (m != null) {
      var body = m.group(1)!;
      if (body.endsWith('\\')) body = body.substring(0, body.length - 1);
      try {
        final t = (jsonDecode('"$body"') as String).trim();
        if (t.isNotEmpty) {
          final mood = RegExp(r'"mood"\s*:\s*"([^"]*)"').firstMatch(s)?.group(1);
          return AiReply(t, _mood(mood));
        }
      } catch (_) {}
    }
    return AiReply(s, PetMood.talking);
  }

  /// Values a model writes when it means "no project / nothing to remember".
  static const _nothing = {'null', 'none', 'n/a', 'na', 'nil', 'undefined', '없음', '无', '-', '—'};

  /// Index of the '}' that closes the '{' at [start], skipping strings; -1 if unclosed.
  static int _balancedEnd(String s, int start) {
    var depth = 0, inStr = false, esc = false;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == 0x5c) {
          esc = true;
        } else if (c == 0x22) {
          inStr = false;
        }
      } else if (c == 0x22) {
        inStr = true;
      } else if (c == 0x7b) {
        depth++;
      } else if (c == 0x7d && --depth == 0) {
        return i;
      }
    }
    return -1;
  }

  static PetMood _mood(String? s) => PetMood.values.firstWhere(
      (e) => e.name == s?.trim().toLowerCase() && replyMoods.contains(e.name),
      orElse: () => PetMood.talking);
}
