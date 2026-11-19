import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../edition.dart';
import '../models/pet_state.dart';
import '../models/character.dart';
import '../models/emotion_fx.dart';
import '../models/manual.dart';
import '../models/panel_theme.dart';
import '../models/profile.dart';
import '../services/chat_ai.dart';
import '../services/links.dart';
import '../services/pet_brain.dart';
import '../services/sfx.dart';
import '../services/speech_out.dart';
import 'pet_window.dart';

/// Settings tab: owner profile (language, location, about, watched stock),
/// which AI answers (provider, key, model) and the voice switches.
/// Keys and the profile are stored only on this Mac.
class SettingsPanel extends StatefulWidget {
  final PetBrain brain;

  /// Switches the panel to the chat tab (after opening the manual room).
  final VoidCallback? onShowChat;
  const SettingsPanel({super.key, required this.brain, this.onShowChat});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final _key = TextEditingController();
  final _url = TextEditingController();
  final _model = TextEditingController();
  List<String> _models = [];
  String _status = '';
  bool _busy = false;

  // owner profile fields
  final _place = TextEditingController();
  final _about = TextEditingController();
  final _symbol = TextEditingController();
  final _stockName = TextEditingController();
  final _birthday = TextEditingController();
  final _zip = TextEditingController();
  final _brave = TextEditingController();
  final _elevenKey = TextEditingController();
  final _elevenVoice = TextEditingController();
  String _profileStatus = '';

  ChatAi get ai => widget.brain.ai;

  @override
  void initState() {
    super.initState();
    _fill();
    final p = widget.brain.profile;
    _place.text = p.placeName;
    _about.text = p.about;
    _symbol.text = p.stockSymbol;
    _stockName.text = p.stockName;
    _birthday.text = p.birthday;
    _zip.text = p.zip;
    _brave.text = ai.braveKey;
    _elevenKey.text = widget.brain.voice.eleven.config.apiKey;
    _elevenVoice.text = widget.brain.voice.eleven.config.voiceId;
  }

  /// City name -> coordinates (Open-Meteo geocoding, no key). Only the
  /// typed place name is sent, once, when the owner presses Find.
  Future<void> _findPlace() async {
    final q = _place.text.trim();
    if (q.isEmpty || !Ed.noncommercialApis) return;
    setState(() => _profileStatus = Lang.t('찾는 중...', 'Searching...', '搜索中...'));
    try {
      final r = await http
          .get(Uri.parse('https://geocoding-api.open-meteo.com/v1/search'
              '?name=${Uri.encodeQueryComponent(q)}&count=1'
              '&language=${Lang.ko ? 'ko' : 'en'}'))
          .timeout(const Duration(seconds: 10));
      final res = (jsonDecode(r.body)['results'] as List?) ?? [];
      if (res.isEmpty) {
        setState(() => _profileStatus = Lang.t('못 찾았어요. 도시 이름을 영어로 넣어 보세요.',
            'Not found. Try a city name in English.', '没找到。试试用英文输入城市名。'));
        return;
      }
      final g = res.first as Map;
      final name = '${g['name']}${g['admin1'] != null ? ', ${g['admin1']}' : ''}';
      await widget.brain.updateProfile((p) {
        p.placeName = g['name'].toString();
        p.lat = (g['latitude'] as num).toDouble();
        p.lon = (g['longitude'] as num).toDouble();
        p.region = '${g['admin1'] ?? ''}';
        if (g['country_code'] != null) p.country = '${g['country_code']}'.toUpperCase();
      });
      if (mounted) {
        setState(() => _profileStatus = Lang.t('날씨 위치: $name', 'Weather location: $name', '天气位置：$name'));
      }
    } catch (e) {
      if (mounted) setState(() => _profileStatus = Lang.t('실패: $e', 'Failed: $e', '失败：$e'));
    }
  }

  String _ago(DateTime? t) {
    if (t == null) return Lang.t('아직 없음', 'not yet', '还没有');
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return Lang.t('방금', 'just now', '刚刚');
    if (m < 60) return Lang.t('$m분 전', '$m min ago', '$m分钟前');
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveProfileText() async {
    await widget.brain.updateProfile((p) {
      p.about = _about.text.trim();
      p.stockSymbol = _symbol.text.trim().toUpperCase();
      p.stockName = _stockName.text.trim();
      final b = RegExp(r'^(\d{1,2})\D+(\d{1,2})$').firstMatch(_birthday.text.trim());
      p.birthday = b == null
          ? ''
          : '${b.group(1)!.padLeft(2, '0')}-${b.group(2)!.padLeft(2, '0')}';
      _birthday.text = p.birthday;
      p.zip = _zip.text.trim();
      if (!Ed.noncommercialApis && _place.text.trim().isNotEmpty) p.placeName = _place.text.trim();
    });
    if (mounted) setState(() => _profileStatus = Lang.t('저장했어요', 'Saved', '已保存'));
  }

  void _fill() {
    final p = ai.active;
    _key.text = p.apiKey;
    _url.text = p.baseUrl;
    _model.text = p.model;
    _models = [];
    _status = '';
  }

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    _model.dispose();
    _place.dispose();
    _about.dispose();
    _symbol.dispose();
    _stockName.dispose();
    _birthday.dispose();
    _zip.dispose();
    _brave.dispose();
    _elevenKey.dispose();
    _elevenVoice.dispose();
    super.dispose();
  }

  void _commit() {
    final p = ai.active;
    p.apiKey = _key.text.trim();
    p.baseUrl = _url.text.trim();
    p.model = _model.text.trim();
    ai.save();
  }

  Future<void> _run(String label, Future<String> Function() job) async {
    _commit();
    setState(() {
      _busy = true;
      _status = label;
    });
    try {
      final s = await job();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _status = Lang.t('실패: $e', 'Failed: $e', '失败：$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadModels() => _run(Lang.t('모델 목록 불러오는 중...', 'Loading models...', '正在加载模型...'), () async {
        final list = await ai.listModels(ai.active);
        _models = list;
        return list.isEmpty
            ? Lang.t('목록이 비어 있어요. 모델 ID를 직접 넣어주세요.',
                'The list is empty. Type a model ID yourself.', '列表是空的。请自己输入模型 ID。')
            : Lang.t('${list.length}개 찾음. 눌러서 고르세요.', 'Found ${list.length}. Tap one to pick it.', '找到 ${list.length} 个。点一下来选择。');
      });

  void _test() => _run(Lang.t('연결 테스트 중...', 'Testing connection...', '正在测试连接...'), () async {
        final r = await ai.reply([
          ChatMessage(
              text: Lang.t('연결 테스트야. 한 문장으로 인사해줘.',
                  'This is a connection test. Say hello in one sentence.', '这是连接测试。请用一句话打个招呼。'),
              fromUser: true,
              at: DateTime.now()),
        ], Lang.t('연결 테스트', 'Connection test', '连接测试'));
        return Lang.t('성공: ${r.text}', 'OK: ${r.text}', '成功：${r.text}');
      });

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      );

  static const _bold = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
  static const _small = TextStyle(fontSize: 11, color: Colors.black45);

  /// Native Mac features of the sold editions: menu bar item, notifications.
  List<Widget> _macWidgets(PetBrain brain) => [
        const Divider(height: 22),
        Text(Lang.t('맥 기능', 'Mac features', 'Mac 功能'), style: _bold),
        Row(
          children: [
            Expanded(
                child: Text(Lang.t('메뉴 막대에 후디메이트 표시 (기분·배부름·기운)',
                    'Show Hoodimate in the menu bar (mood, fullness, energy)', '在菜单栏显示 Hoodimate（心情·饱腹·体力）'),
                    style: const TextStyle(fontSize: 12))),
            Switch(key: const Key('menubar-switch'), value: brain.menuBarEnabled, onChanged: brain.setMenuBar),
          ],
        ),
        Row(
          children: [
            Expanded(
                child: Text(Lang.t('알림 센터로 알려 주기 (배고픔·알람·잠잘 시간)',
                    'Notification Center alerts (hungry, alarm, bedtime)', '通过通知中心提醒（饿了·闹钟·睡觉时间）'),
                    style: const TextStyle(fontSize: 12))),
            Switch(
                key: const Key('notify-switch'),
                value: brain.notifyEnabled,
                onChanged: (v) => brain.setNotifications(v)),
          ],
        ),
        if (brain.notifyDenied)
          Text(
              Lang.t('알림이 꺼져 있어요. 시스템 설정 > 알림에서 후디메이트를 허용한 뒤 다시 켜 주세요.',
                  'Notifications are off for Hoodimate. Allow them in System Settings > Notifications, then turn this on again.',
                  '通知被关闭了。请在 系统设置 > 通知 中允许 Hoodimate，然后再打开此开关。'),
              style: _small),
      ];

  /// Chat AI + read-aloud settings. The owner's build keeps them in the middle of
  /// the page; sold editions put them below the pet settings.
  List<Widget> _aiWidgets(PetBrain brain) {
    return [
              const Divider(height: 18),
              Text(Lang.t('대화 AI', 'Chat AI', '聊天 AI'), style: _bold),
              DropdownButton<String>(
                value: ai.activeId,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items: [
                  for (final p in ai.providers)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.isReady ? '${p.label}  ✓' : p.label),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  _commit();
                  setState(() {
                    ai.activeId = id;
                    _fill();
                  });
                  ai.save();
                },
              ),
              if (ai.active.wire == AiWire.apple)
                FutureBuilder<Map<String, String>>(
                  future: ChatAi.appleAvailability(),
                  builder: (context, snap) {
                    final st = snap.data;
                    final ok = st?['status'] == 'available';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          st == null
                              ? Lang.t('확인 중...', 'Checking...', '检查中...')
                              : ok
                                  ? Lang.t('✓ AI 키가 없는 분을 위한 체험판이에요. 이 맥 안에서만 돌아가서 키도 비용도 필요 없어요. 가벼운 대화와 알람 정도만 할 수 있으니, 더 똑똑하게 쓰려면 Gemini 같은 AI 키를 넣어 주세요.',
                                      '✓ A free trial for people without an AI key. It runs only on this Mac, so no key or cost. It handles light chat and alarms; for a smarter pet, add a key for Gemini or another AI.',
                                      '✓ 这是给没有 AI 密钥的人准备的体验版。只在这台 Mac 上运行，不需要密钥和费用。只能简单聊天和设闹钟，想要更聪明，请填写 Gemini 等 AI 的密钥。')
                                  : '⚠️ ${ChatAi.appleReasonText(st['reason'] ?? '')}',
                          style: _small),
                    );
                  },
                )
              else ...[
              TextField(
                controller: _key,
                obscureText: true,
                style: const TextStyle(fontSize: 12),
                decoration: _dec('API Key'),
                onChanged: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _url,
                style: const TextStyle(fontSize: 12),
                decoration: _dec('Base URL'),
                onChanged: (_) => _commit(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _model,
                      style: const TextStyle(fontSize: 12),
                      decoration: _dec(Lang.t('모델 ID', 'Model ID', '模型 ID')),
                      onChanged: (_) => _commit(),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _loadModels,
                    child: Text(Lang.t('불러오기', 'Load', '加载'), style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              if (_models.isNotEmpty)
                Container(
                  height: 90,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final m in _models)
                        InkWell(
                          onTap: () {
                            _model.text = m;
                            _commit();
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(m,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: m == _model.text
                                        ? Colors.orange.shade800
                                        : Colors.black87)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _test,
                  child: Text(Lang.t('연결 테스트', 'Test connection', '测试连接'), style: const TextStyle(fontSize: 12)),
                ),
              ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_status, style: _small),
                ),
              const SizedBox(height: 4),
              if (ai.active.wire != AiWire.apple)
              Text(
                  Ed.current == Edition.personal
                      ? Lang.t('키는 이 Mac에만 저장돼요. 채팅 앱 구독이 아니라 각 회사의 API 키가 필요해요.',
                          'Keys stay on this Mac. You need an API key from each provider, not a chat app subscription.', '密钥只保存在这台 Mac 上。需要各家的 API 密钥，而不是聊天应用的订阅。')
                      : Lang.t('AI 키는 선택 사항이에요. 키는 이 Mac에만 저장되고, 키 없이도 돌봄·감정·알람은 쓸 수 있어요.',
                          'An AI key from the provider is optional. Keys stay on this Mac, and care, feelings and alarms work without one.', 'AI 密钥是可选的。密钥只保存在这台 Mac 上，没有密钥也能使用照顾、感情和闹钟。'),
                  style: _small),
              if (Ed.agentTools) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: Text(Lang.t('AI 도구 쓰기 (검색·날씨·알람·노트·일정)', 'Let the AI use tools (search, weather, alarms, notes, calendar)', '允许 AI 使用工具（搜索·天气·闹钟·笔记·日程）'),
                          style: const TextStyle(fontSize: 12))),
                  Switch(
                      value: ai.toolsEnabled,
                      onChanged: (v) => setState(() {
                            ai.toolsEnabled = v;
                            ai.save();
                          })),
                ],
              ),
              if (ai.toolsEnabled) ...[
                Row(
                  children: [
                    Expanded(
                        child: Text(Lang.t('맥 캘린더 보기·추가', 'Read and add Mac calendar events', '读取和添加 Mac 日历'),
                            style: const TextStyle(fontSize: 12))),
                    Switch(
                        value: ai.calendarEnabled,
                        onChanged: (v) => setState(() {
                              ai.calendarEnabled = v;
                              ai.save();
                            })),
                  ],
                ),
                TextField(
                  controller: _brave,
                  obscureText: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: _dec(Lang.t('Brave Search API 키 (선택 · 없으면 DuckDuckGo)', 'Brave Search API key (optional · DuckDuckGo without it)', 'Brave Search API 密钥（可选 · 没有则用 DuckDuckGo）')),
                  onChanged: (v) {
                    ai.braveKey = v.trim();
                    ai.save();
                  },
                ),
                const SizedBox(height: 4),
                Text(
                    Lang.t('예: "내일 LA 날씨 어때?", "애플 신제품 소식 찾아줘", "이번 주 일정 알려줘", "금요일 3시에 치과 일정 넣어줘"',
                        'e.g. "Weather in Seoul tomorrow?", "Find news about Apple", "What\'s on my calendar this week?", "Add dentist Friday 3 PM"', '例如："明天洛杉矶天气怎么样？"、"找找苹果的新闻"、"这周我有什么日程？"、"周五下午 3 点加一个看牙医的日程"'),
                    style: _small),
              ],
              ],
              const Divider(height: 22),
              Text(Lang.t('대답 읽어 주기', 'Read replies aloud', '朗读回答'), style: _bold),
              const SizedBox(height: 6),
              SegmentedButton<SpeechMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: SpeechMode.off, label: Text(Lang.t('끄기', 'Off', '关'), style: const TextStyle(fontSize: 12))),
                  ButtonSegment(value: SpeechMode.mac, label: Text(Lang.t('Mac 목소리', 'Mac voice', 'Mac 语音'), style: const TextStyle(fontSize: 12))),
                  if (Ed.cloudVoice) const ButtonSegment(value: SpeechMode.eleven, label: Text('ElevenLabs', style: TextStyle(fontSize: 12))),
                ],
                selected: {brain.voice.mode},
                onSelectionChanged: (v) => brain.setSpeechMode(v.first),
              ),
              if (brain.voice.mode == SpeechMode.eleven) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _elevenKey,
                  obscureText: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: _dec(Lang.t('ElevenLabs API 키', 'ElevenLabs API key', 'ElevenLabs API 密钥')),
                  onChanged: (v) {
                    brain.voice.eleven.config.apiKey = v.trim();
                    brain.voice.eleven.save();
                  },
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _elevenVoice,
                  style: const TextStyle(fontSize: 12),
                  decoration: _dec(Lang.t('Voice ID (ElevenLabs의 목소리 ID)', 'Voice ID (from ElevenLabs)', 'Voice ID（ElevenLabs 的声音 ID）')),
                  onChanged: (v) {
                    brain.voice.eleven.config.voiceId = v.trim();
                    brain.voice.eleven.save();
                  },
                ),
              ],
              if (brain.voice.mode != SpeechMode.off) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => brain.voice.speak(Lang.t(
                        '안녕! 나는 ${Character.current.name}야. 오늘도 같이 힘내자!',
                        'Hi! I am ${Character.current.name}. Let\'s have a great day together!',
                        '你好！我是${Character.current.name}。今天也一起加油吧！')),
                    child: Text(Lang.t('들어보기', 'Try it', '试听'), style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                  brain.voice.mode == SpeechMode.eleven
                      ? Lang.t('ElevenLabs는 글자 수만큼 요금이 들어요(본인 키). 입 모양이 말에 정확히 맞춰져요. 실패하면 Mac 목소리로 읽어요.',
                          'ElevenLabs bills per character (your key). Mouth shapes follow the speech exactly; falls back to the Mac voice.', 'ElevenLabs 按字数计费（用你自己的密钥）。口型会精确对上说话内容；失败时会改用 Mac 的声音朗读。')
                      : Lang.t('AI 대답을 소리로 읽고 입을 움직여요. Mac 목소리는 무료예요.',
                          'Reads AI replies aloud with a moving mouth. The Mac voice is free.', '朗读 AI 的回复并让嘴巴动起来。Mac 的声音是免费的。'),
                  style: _small),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.brain,
      builder: (context, _) {
        final brain = widget.brain;
        final cues = brain.cues;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: Text(Lang.t('사용 설명서 · 질문하기', 'Manual · ask a question', '说明书 · 提问'),
                      style: const TextStyle(fontSize: 13)),
                  onPressed: () {
                    brain.openManual();
                    widget.onShowChat?.call();
                  },
                ),
              ),
              if (Character.available.length > 1) ...[
                const SizedBox(height: 12),
                Text(Lang.t('캐릭터', 'Character', '角色'), style: _bold),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in Character.available)
                      ChoiceChip(
                        label: Text(c.displayName, style: const TextStyle(fontSize: 12)),
                        avatar: CircleAvatar(
                            backgroundColor: Colors.transparent,
                            backgroundImage: AssetImage(c.sprite('idle'))),
                        selected: c.id == Character.current.id,
                        onSelected: (_) => brain.setCharacter(c.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (!Ed.noncommercialApis) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x14FF9800),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${Lang.t('⚠️ 주의사항', '⚠️ Good to know', '⚠️ 注意事项')}\n${Manual.notice}', style: _small),
                ),
              ],
              Text(Lang.t('내 프로필', 'My profile', '我的资料'), style: _bold),
              const SizedBox(height: 4),
              // Wrap: label + three chips are wider than the 300px minimum panel.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(Lang.t('언어', 'Language', '语言'), style: const TextStyle(fontSize: 12)),
                  ),
                  for (final l in const [('en', 'English'), ('ko', '한국어'), ('zh', '中文')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(l.$2, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        selected: brain.profile.language == l.$1,
                        onSelected: (_) =>
                            brain.updateProfile((p) => p.language = l.$1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _place,
                      style: const TextStyle(fontSize: 12),
                      decoration: _dec(Ed.noncommercialApis
                          ? Lang.t('날씨 위치 (도시 이름)', 'Weather location (city)', '天气位置（城市）')
                          : Lang.t('사는 도시', 'My city', '所在城市')),
                      onSubmitted: (_) => Ed.noncommercialApis ? _findPlace() : _saveProfileText(),
                    ),
                  ),
                  // The city lookup uses a free non-commercial service, so
                  // sold builds just save the typed name.
                  if (Ed.noncommercialApis)
                    TextButton(
                      onPressed: _findPlace,
                      child: Text(Lang.t('찾기', 'Find', '查找'), style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _about,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
                decoration: _dec(Lang.t('나에 대해 (AI가 참고해요, 예: 사는 곳·쓰는 단위)',
                    'About me (the AI reads this, e.g. where you live, units)', '关于我（AI 会参考，例如居住地、单位）')),
              ),
              if (Ed.market) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _symbol,
                      style: const TextStyle(fontSize: 12),
                      decoration: _dec(Lang.t('관심 종목 심볼 (예: AAPL)', 'Stock symbol (e.g. AAPL)', '股票代码（例如 AAPL）')),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _stockName,
                      style: const TextStyle(fontSize: 12),
                      decoration: _dec(Lang.t('종목 이름 (뉴스 검색용)', 'Stock name (for news)', '股票名称（用于搜索新闻）')),
                    ),
                  ),
                ],
              ),
              ],
              const SizedBox(height: 6),
              TextField(
                controller: _zip,
                style: const TextStyle(fontSize: 12),
                decoration: _dec(Lang.t('우편번호 (ZIP) · 동네 소식과 뉴스는 이 위치 기준이에요',
                    'ZIP / postal code · local info and news follow this place', '邮编 · 本地信息和新闻以此为准')),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2),
                child: Text(
                    Lang.t('내 위치: ${widget.brain.profile.homeLine}', 'My place: ${widget.brain.profile.homeLine}',
                        '我的位置：${widget.brain.profile.homeLine}'),
                    style: _small),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _birthday,
                style: const TextStyle(fontSize: 12),
                decoration: _dec(Lang.t('내 생일 (월-일, 예: 03-14) · 그날 축하해 줘요',
                    'My birthday (MM-DD, e.g. 03-14) · we celebrate that day', '我的生日（月-日，例如 03-14）· 当天会为你庆祝')),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _saveProfileText,
                  child: Text(Lang.t('프로필 저장', 'Save profile', '保存资料'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              Text(
                  _profileStatus.isNotEmpty
                      ? _profileStatus
                      : Lang.t('프로필은 이 Mac에만 저장돼요.', 'Your profile stays on this Mac.', '你的资料只保存在这台 Mac 上。'),
                  style: _small),
              // Lite has no stock/news tools: credit only the geocoding it uses.
              if (Ed.isLite) Text(
                  Lang.t('도시 검색: Open-Meteo.com (CC BY 4.0)', 'City search by Open-Meteo.com (CC BY 4.0)', '城市搜索来自 Open-Meteo.com (CC BY 4.0)'),
                  style: _small)
              else if (Ed.noncommercialApis) Text(
                  Lang.t('날씨 데이터: Open-Meteo.com (CC BY 4.0) · 주가: Yahoo Finance 비공식 경로(지연·중단될 수 있음) · 뉴스: Google News',
                      'Weather data by Open-Meteo.com (CC BY 4.0) · Quotes: unofficial Yahoo Finance endpoint (may be delayed or stop) · News: Google News', '天气数据来自 Open-Meteo.com (CC BY 4.0) · 股价：Yahoo Finance 非官方接口（可能延迟或中断）· 新闻：Google News'),
                  style: _small),
              const Divider(height: 18),
              Text(Lang.t('캐릭터 크기', 'Pet size', '宠物大小'), style: _bold),
              Row(
                children: [
                  Text(Lang.t('작게', 'Small', '小'), style: _small),
                  Expanded(
                    child: Slider(
                      value: brain.petScale,
                      min: 0.6,
                      max: 1.6,
                      divisions: 10,
                      label: '${(brain.petScale * 100).round()}%',
                      onChanged: brain.setPetScale,
                      onChangeEnd: (_) => PetLayout.apply(brain),
                    ),
                  ),
                  Text(Lang.t('크게', 'Large', '大'), style: _small),
                ],
              ),
              const Divider(height: 18),
              Text(Lang.t('대화창 모양', 'Chat look', '聊天外观'), style: _bold),
              const SizedBox(height: 2),
              Text(Lang.t('메뉴 창을 우클릭(또는 Control+클릭)해도 바꿀 수 있어요.',
                  'You can also right-click (or Control-click) the menu.', '也可以右键（或按住 Control 点击）菜单来更改。'),
                  style: _small),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in PanelTheme.all)
                    Tooltip(
                      message: t.name,
                      child: InkWell(
                        onTap: () => brain.setPanelTheme(t.id),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: t.userBubble,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: brain.panelTheme == t.id ? t.label : t.border,
                                width: brain.panelTheme == t.id ? 2.5 : 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(Lang.t('귀여운 글꼴', 'Cute font', '可爱字体'),
                        style: TextStyle(fontFamily: CuteFont.family, fontFamilyFallback: CuteFont.fallback, fontSize: 13)),
                    selected: CuteFont.cute,
                    onSelected: (_) {
                      brain.setChatFont(cute: true);
                      PetLayout.apply(brain);
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(Lang.t('기본 글꼴', 'System font', '系统字体'), style: const TextStyle(fontSize: 12)),
                    selected: !CuteFont.cute,
                    onSelected: (_) {
                      brain.setChatFont(cute: false);
                      PetLayout.apply(brain);
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  Text(Lang.t('글자', 'Text', '字号'), style: _small),
                  Expanded(
                    child: Slider(
                      value: CuteFont.scale,
                      min: 0.85,
                      max: 1.5,
                      divisions: 13,
                      label: '${(CuteFont.scale * 100).round()}%',
                      onChanged: (v) => brain.setChatFont(scale: v),
                      onChangeEnd: (_) => PetLayout.apply(brain),
                    ),
                  ),
                  Text('${(CuteFont.scale * 100).round()}%', style: _small),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(Lang.t('답에 이모티콘 붙이기', 'Emoticons on replies', '回复带表情'), style: _small),
                  ),
                  Switch(
                    value: brain.replyStickers,
                    onChanged: brain.setReplyStickers,
                  ),
                ],
              ),
              const Divider(height: 18),
              Text(Lang.t('노트 (옵시디언)', 'Notes (Obsidian)', '笔记 (Obsidian)'), style: _bold),
              const SizedBox(height: 2),
              Text(
                  brain.notes.folder == null
                      ? Lang.t('아직 폴더를 고르지 않았어요. 옵시디언 볼트 안의 폴더를 골라 주세요.',
                          'No folder yet. Pick a folder inside your Obsidian vault.', '还没选文件夹。请选择 Obsidian 库里的一个文件夹。')
                      : Lang.t('저장 위치: ${brain.notes.folder}/${Ed.dataFolder}/', 'Saved to: ${brain.notes.folder}/${Ed.dataFolder}/', '保存位置：${brain.notes.folder}/${Ed.dataFolder}/'),
                  style: _small),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: brain.pickNotesFolder,
                  child: Text(
                      brain.notes.folder == null
                          ? Lang.t('노트 폴더 고르기', 'Pick notes folder', '选择笔记文件夹')
                          : Lang.t('노트 폴더 바꾸기', 'Change notes folder', '更换笔记文件夹'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              Text(
                  Lang.t('"/노트 우유 사기", "이거 노트에 저장해줘"라고 말하면 적어 둬요. 기억한 내용도 자동으로 저장돼요.',
                      'Say "/note buy milk" or "save this to my notes". Things it remembers are saved too.', '说 "/note 买牛奶" 或 "把这个存到笔记里" 就会记下来。记住的内容也会自动保存。'),
                  style: _small),
              if (Ed.sync) ...[
              const Divider(height: 18),
              Text(Lang.t('맥끼리 동기화', 'Sync between Macs', '多台 Mac 同步'), style: _bold),
              const SizedBox(height: 4),
              Text(
                  brain.sync.ready
                      ? Lang.t(
                          '폴더: ${brain.sync.folder}\n마지막 동기화: ${_ago(brain.sync.lastSync)}${brain.sync.lastError != null ? '\n⚠️ ${brain.sync.lastError}' : ''}',
                          'Folder: ${brain.sync.folder}\nLast sync: ${_ago(brain.sync.lastSync)}${brain.sync.lastError != null ? '\n⚠️ ${brain.sync.lastError}' : ''}',
                          '文件夹：${brain.sync.folder}\n上次同步：${_ago(brain.sync.lastSync)}${brain.sync.lastError != null ? '\n⚠️ ${brain.sync.lastError}' : ''}')
                      : Lang.t('두 맥에서 함께 보이는 폴더(iCloud Drive, Dropbox, Google Drive 등)를 고르면 대화·펫 상태·프로필·알람·코인이 같이 맞춰져요.',
                          'Pick a folder both Macs can see (iCloud Drive, Dropbox, Google Drive ...) to share chats, pet stats, profile, alarms and coins.', '选一个两台 Mac 都能看到的文件夹（iCloud Drive、Dropbox、Google Drive 等），聊天、宠物状态、资料、闹钟和币就会同步。'),
                  style: _small),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: brain.pickSyncFolder,
                      child: Text(
                          brain.sync.ready
                              ? Lang.t('폴더 바꾸기', 'Change folder', '更换文件夹')
                              : Lang.t('동기화 폴더 고르기', 'Pick sync folder', '选择同步文件夹'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  if (brain.sync.ready) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: brain.syncing ? null : brain.syncNow,
                        child: Text(
                            brain.syncing
                                ? Lang.t('맞추는 중...', 'Syncing...', '同步中...')
                                : Lang.t('지금 동기화', 'Sync now', '立即同步'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  Lang.t('3분마다 자동으로 맞춰요. AI 키와 크기·음량 설정은 맥마다 따로예요.',
                      'Syncs every 3 minutes. AI keys and size/volume settings stay on each Mac.', '每 3 分钟自动同步一次。AI 密钥和大小/音量设置在每台 Mac 上各自独立。'),
                  style: _small),
              ],
              if (Ed.market) ...[
              const Divider(height: 18),
              Text(Lang.t('투자 브리핑 (매일 10시·17시)', 'Market briefing (10 AM · 5 PM daily)', '市场简报（每天 10 点 · 17 点）'), style: _bold),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      brain.marketBrief(morning: DateTime.now().hour < 12),
                  child: Text(Lang.t('지금 브리핑 보기', 'Show briefing now', '立即查看简报'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              Text(
                  Lang.t('코인 보유량은 이 Mac에만 저장돼요. 정보 안내일 뿐 투자 조언은 아니에요.',
                      'Holdings stay on this Mac. Information only, not investment advice.', '持仓只保存在这台 Mac 上。仅为信息提示，不构成投资建议。'),
                  style: _small),
              ],
              if (!Ed.isSold) ..._aiWidgets(brain),
              const Divider(height: 22),
              Text(Lang.t('상황 음성', 'Reaction sounds', '情境语音'), style: _bold),
              Row(
                children: [
                  Expanded(
                      child: Text(Lang.t('밥·비·아픔 등 반응 소리', 'Sounds for food, rain, sickness...', '吃饭、下雨、不舒服等反应声音'),
                          style: const TextStyle(fontSize: 12))),
                  Switch(value: cues.enabled, onChanged: brain.setCuesEnabled),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: Text(Lang.t('녹음 없을 때 Mac 음성으로 대신', 'Use the Mac voice when no recording', '没有录音时用 Mac 声音代替'),
                          style: const TextStyle(fontSize: 12))),
                  Switch(
                      value: cues.macFallback, onChanged: brain.setMacFallback),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: Text(Lang.t('심심할 때 돌아다니기·혼자 놀기', 'Wander and play when idle', '空闲时四处走动、自己玩'),
                          style: const TextStyle(fontSize: 12))),
                  Switch(value: brain.roam, onChanged: brain.setRoam),
                ],
              ),
              Row(
                children: [
                  Text(Lang.t('버튼 효과음', 'Button sounds', '按钮音效'),
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: Sfx.volume,
                      divisions: 10,
                      label: '${(Sfx.volume * 100).round()}%',
                      onChanged: brain.setSfxVolume,
                      onChangeEnd: (_) => Sfx.play('buzz'),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: Text(Lang.t('트랙패드 진동 (햅틱)', 'Trackpad haptics', '触控板震动（触感反馈）'),
                          style: const TextStyle(fontSize: 12))),
                  Switch(value: Sfx.haptics, onChanged: brain.setHaptics),
                ],
              ),
              Text(
                  Lang.t('녹음된 대사 ${cues.recordedCount}개 · 대화 답변은 소리 없이 글로만 보여줘요.',
                      '${cues.recordedCount} recorded lines · chat replies are shown as text only.', '已录制 ${cues.recordedCount} 句台词 · 聊天回复只显示文字，没有声音。'),
                  style: _small),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => cues.play('greeting', force: true),
                  child: Text(Lang.t('인사 음성 들어보기', 'Play the greeting', '试听问候语'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              if (Ed.isSold) ..._macWidgets(brain),
              if (Ed.isSold) ..._aiWidgets(brain),
              const Divider(height: 22),
              Text(Lang.t('보관된 대화방 (${brain.memory.archivedList.length})',
                      'Archived chats (${brain.memory.archivedList.length})', '已归档的聊天室 (${brain.memory.archivedList.length})'),
                  style: _bold),
              if (brain.memory.archivedList.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      Lang.t('${Ed.isSold ? '말하기' : '대화'} 탭에서 ✕로 닫은 대화방이 여기 보관돼요. 지워지지 않아요.',
                          'Chats you close with ✕ are kept here. Nothing is deleted.', '在聊天页用 ✕ 关闭的聊天室会保存在这里。不会被删除。'),
                      style: _small),
                ),
              for (final p in brain.memory.archivedList)
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 15, color: Colors.black45),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          Lang.t('${p.name} · 대화 ${p.chat.length}개 · 메모 ${p.notes.length}개',
                              '${p.name} · ${p.chat.length} messages · ${p.notes.length} notes', '${p.name} · ${p.chat.length} 条消息 · ${p.notes.length} 条笔记'),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: () => brain.restoreProject(p.id),
                      child: Text(Lang.t('다시 열기', 'Reopen', '重新打开'), style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              const Divider(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: Links.privacy,
                    child: Text(Lang.t('개인정보 처리방침', 'Privacy policy', '隐私政策'),
                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
                  const Text('·', style: TextStyle(color: Colors.black26)),
                  TextButton(
                    onPressed: Links.support,
                    child: Text(Lang.t('지원·문의', 'Support', '支持与联系'),
                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
                ],
              ),
              Center(
                child: TextButton(
                  onPressed: () => exit(0),
                  child: Text(Lang.t('펫 종료하기', 'Quit the pet', '退出宠物'),
                      style: const TextStyle(color: Colors.black45, fontSize: 12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
