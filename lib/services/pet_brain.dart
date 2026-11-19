import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../edition.dart';
import '../models/care_rules.dart';
import '../models/emotion_fx.dart';
import '../models/pet_state.dart';
import '../models/character.dart';
import '../models/emoticons.dart';
import '../widgets/clip_player.dart';
import '../models/manual.dart';
import '../models/onboarding.dart';
import '../models/owner_feelings.dart';
import '../models/profile.dart';
import '../models/reactions.dart';
import 'chat_ai.dart';
import 'market_service.dart';
import 'news_service.dart';
import 'notes.dart';
import 'project_memory.dart';
import 'reminders.dart';
import 'speech_input.dart';
import 'agent_tools.dart';
import 'sfx.dart';
import 'pet_link.dart';
import 'speech_out.dart';
import 'sync_service.dart';
import 'voice_cues.dart';
import 'weather_service.dart';

part 'brain_alarm.dart';
part 'brain_reactions.dart';
part 'brain_demo.dart';
part 'brain_care.dart';
part 'brain_sync.dart';
part 'brain_link.dart';
part 'brain_siri.dart';
part 'brain_native.dart';
part 'brain_feelings.dart';

/// The pet's brain: care stats, mood resolution, care actions,
/// voice input, AI chat (text-only replies) and project memory.
/// A single ChangeNotifier the UI listens to.
///
/// Sound policy: AI replies are shown as text only. The pet makes sound
/// only for situation reactions (feeding, sick, rain, ...) via [cues],
/// which plays pre-recorded MP3s.
class PetBrain extends ChangeNotifier {
  double hunger = 80;
  double happiness = 75;
  double health = 90;
  double energy = 85;

  String? bubbleText;

  /// Emoticon shown next to the bubble text (KakaoTalk style), or null.
  String? bubbleSticker;
  String? _lastReplySticker;

  /// Emoticons on the pet's chat replies; some owners want plain text.
  bool replyStickers = true;

  /// Sold editions walk a new owner through the pet first (character,
  /// care, Hoodibot). Kept per Mac in pet_state.json.
  bool onboardingDone = false;

  /// True while the first-run walkthrough should be on screen.
  bool get needsOnboarding =>
      Onboarding.needed(edition: Ed.current, done: onboardingDone, demo: demo, film: film);

  Future<void> completeOnboarding() async {
    if (onboardingDone) return;
    onboardingDone = true;
    _notify();
    await _save();
  }

  /// Menu bar status item (sold editions); per Mac.
  bool menuBarEnabled = true;
  String _statusSig = '';

  /// Notification Center notices (hungry, alarm, bedtime); off until the
  /// owner turns them on in Settings. Per Mac.
  bool notifyEnabled = false;
  bool notifyDenied = false; // macOS refused the permission just now
  bool _hungryNoticed = false;

  /// Set by the pet window: bring the window to the front / open Talk.
  Future<void> Function()? showPet;
  void Function()? openTalk;

  bool panelOpen = false;
  bool sleeping = false;
  bool thinking = false;
  bool listening = false;

  /// Character size multiplier (Settings slider, 0.6-1.6).
  double petScale = 1.0;

  /// Size of the chat/care/settings panel; the owner drags its corner.
  /// Kept per Mac (not synced).
  static const panelDefault = Size(340, 370);
  static const panelMin = Size(300, 280), panelMax = Size(900, 1000);
  double panelW = panelDefault.width, panelH = panelDefault.height;

  /// Panel color theme id ([PanelTheme]); right-click the panel to change.
  String panelTheme = 'cream';

  final ai = ChatAi();

  /// Set by the chat window: asks before the first chat goes to a cloud AI
  /// (App Store guideline 5.1.2).
  Future<bool> Function(String provider)? askAiConsent;
  final memory = ProjectMemory();
  final cues = VoiceCues();
  final sync = SyncService();

  /// Hoodibot on the same Mac (shared App Group folder).
  final link = PetLink();

  /// Set by the pet window: our pet's feet in screen points (main screen's
  /// bottom-left is 0,0) and its height, for meeting Hoodibot.
  Future<({double x, double y, double h})?> Function()? petFeet;
  late final voice = SpeechOut(cues.mouth); // reads AI replies aloud
  late final tools = AgentTools(
    reminder: (cmd) {
      final r = reminders.handle(cmd, DateTime.now()) ??
          'could not understand the time; ask the owner for a clearer time';
      reminders.save();
      return r;
    },
    saveNote: (text) => _saveNote(memory.active, text),
  );
  final speech = SpeechInput();
  final weather = WeatherService();
  final market = MarketService();
  final reminders = Reminders();
  final notes = Notes();
  final profile = OwnerProfile();
  final news = NewsService();

  final List<Timer> _timers = [];
  Timer? _bubbleTimer;
  /// Sulks after an insult until an apology (brain_feelings.dart).
  final SulkState sulk = SulkState();
  DateTime? _angryUntil;

  PetMood? _overrideMood;
  DateTime? _overrideUntil;
  PetMood? _lastMood;
  int hopSignal = 0;

  /// Bumped on every touch reaction; [reaction] says which one.
  int reactionSignal = 0;
  PetReaction reaction = PetReaction.none;
  final Map<PetReaction, DateTime> _reactedAt = {};

  /// Bumped when a pre-rendered one-shot action should play
  /// (pet, tickle, thanks, wave, jump, yawn, eat).
  int actionSignal = 0;
  String? action;

  /// State clip looped while busy: listening to the mic, waiting for the
  /// AI. Null at rest.
  String? get busyClip => listening ? 'listen' : (thinking ? 'think' : null);

  void _act(String name) {
    action = name;
    actionSignal++;
  }

  static const version = '0.2.0';

  /// Chat thread of the active project (what the 대화 tab shows).
  List<ChatMessage> get chat => memory.active.chat;

  Future<void> init() async {
    await profile.load();
    await Character.load(profile.character);
    applyProfile();
    await cues.init();
    await voice.init();
    await ai.load();
    await ai.applyDefaultProvider(sold: Ed.isSold);
    if (Ed.market) await market.load();
    await memory.load();
    await reminders.load();
    demo = await _takeDemoFlag();
    await notes.init();
    await news.load();
    await _load();
    await sync.init(await getApplicationSupportDirectory());
    await link.init();
    await _initSiri();
    await _initStatusBar();
    if (!demo) await syncNow();
    _startedAt = DateTime.now();
    await weather.refresh();
    if (Ed.market) await market.refresh();
    _timers.addAll([
      Timer.periodic(const Duration(minutes: 3), (_) => syncNow()),
      Timer.periodic(const Duration(minutes: 1), (_) => _onTick()),
      Timer.periodic(const Duration(seconds: 15), (_) => _checkReminders()),
      Timer.periodic(const Duration(milliseconds: 1500), (_) => _linkTick()),
      Timer.periodic(const Duration(minutes: 45), (_) => _checkNews()),
      Timer.periodic(const Duration(minutes: 15),
          (_) => weather.refresh().then((_) => _onWeather())),
      if (Ed.market)
        Timer.periodic(const Duration(minutes: 15),
            (_) => market.refresh().then((_) => _onMarket())),
    ]);
    _lastMood = currentMood();
    if (demo) {
      // Promo recording: a scripted tour instead of the normal day.
      Timer(const Duration(seconds: 2), runDemo);
      return;
    }
    if (film) {
      Timer(const Duration(seconds: 4), runFilm);
      return;
    }
    _act('wave');
    _say(Lang.t('안녕! ${Character.current.displayName} 왔어!', 'Hi! ${Character.current.displayName}\'s here!', '你好！${Character.current.displayName}来啦！'), mood: PetMood.waving, sticker: 'hello');
    cues.play('greeting', force: true);
    // Weather briefing right after the greeting.
    Timer(const Duration(seconds: 9), () => _onWeather(startup: true));
    // Reminders that came due while the app was closed.
    Timer(const Duration(seconds: 20), () => _checkReminders(startup: true));
    Timer(const Duration(minutes: 2), _checkNews);
  }

  // ---------- mood ----------

  /// The sprite/animation mood to display right now.
  PetMood currentMood() {
    final now = DateTime.now();
    if (alarmText != null) return PetMood.talking; // mouth open: startled
    if (listening) return PetMood.talking;
    if (thinking) return PetMood.thinking;
    if (_overrideMood != null &&
        _overrideUntil != null &&
        now.isBefore(_overrideUntil!)) {
      return _overrideMood!;
    }
    _overrideMood = null;
    return baseMood();
  }

  /// Mood from stats/weather/market only (no temporary overrides).
  CareStats get stats => CareStats(
      hunger: hunger,
      happiness: happiness,
      health: health,
      energy: energy,
      sleeping: sleeping,
      night: CareStats.isNight(DateTime.now()));

  /// Needs first (so the owner can see what to do), then weather, market.
  PetMood baseMood() {
    final need = stats.needMood();
    if (need != null) return need;
    final w = weather.current;
    if (w != null && w.isRain) return PetMood.rain;
    // The hot pose lies down fanning itself, which reads as "asleep" if
    // it stays all day: show it only for a while after a hot-weather remark.
    final said = _weatherSaidAt;
    if (w != null &&
        w.isHot &&
        said != null &&
        DateTime.now().difference(said).inMinutes < 15) {
      return PetMood.hot;
    }
    final m = market.current;
    if (m != null && m.moon) return PetMood.celebrating;
    if (m != null && m.crash) return PetMood.sad;
    return PetMood.idle;
  }

  /// Care tab line. When the pet is fine but the eyes look down or happy
  /// because of the rain, heat or the market, say why (owner, 2026-10-12:
  /// "시세가 낮아서 기분이 안 좋아요 라고 말해야 알지").
  String needText() {
    if (stats.needMood() != null || health < 60) return stats.needText();
    return situationText() ?? stats.needText();
  }

  /// Why the mood is what it is when it isn't a care need (null = no reason).
  String? situationText() {
    switch (baseMood()) {
      case PetMood.rain:
        return Lang.t('비가 와서 좀 우중충해요 ☔', 'Rainy day, feeling a bit gloomy ☔', '下雨了，有点闷闷的 ☔');
      case PetMood.hot:
        return Lang.t('더워서 축 처져요 🥵', 'Too hot, I\'m wilting 🥵', '太热了，蔫蔫的 🥵');
      case PetMood.sad:
        final why = _marketWhy(down: true);
        return why == null ? null : Lang.t('시세가 떨어져서 기분이 안 좋아요 📉 ($why)',
            'Prices dropped, so I\'m feeling down 📉 ($why)', '行情跌了，心情不太好 📉（$why）');
      case PetMood.celebrating:
        final why = _marketWhy(down: false);
        return why == null ? null : Lang.t('시세가 올라서 신나요 📈 ($why)',
            'Prices are up, so I\'m excited 📈 ($why)', '行情涨了，好开心 📈（$why）');
      default:
        return null;
    }
  }

  /// "coins -6.9%, SK hynix -5.2%": the parts past the ±5 % mood line.
  String? _marketWhy({required bool down}) {
    final m = market.current;
    if (m == null) return null;
    bool past(double v) => down ? v <= -5 : v >= 5;
    final parts = [
      if (m.coins.isNotEmpty && past(m.totalChangePct))
        '${Lang.t('코인', 'coins', '加密货币')} ${MarketInfo.pct(m.totalChangePct)}',
      if (m.stock != null && past(m.stock!.changePct)) '${m.stock!.name} ${MarketInfo.pct(m.stock!.changePct)}',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
  String? get feedBlock => stats.feedBlock;
  String? get sleepBlock => sleeping
      ? Lang.t('마우스를 흔들면 깨요', 'Shake the mouse to wake', '晃动鼠标来叫醒')
      : null;
  String? get playBlock => stats.playBlock;
  String? get medicineBlock => stats.medicineBlock;

  /// Situation moods that get a voice line when the pet enters them.
  static const _moodCues = {
    PetMood.sick: 'sick',
    PetMood.rain: 'rain',
    PetMood.hot: 'hot',
    PetMood.sad: 'sad',
    PetMood.bored: 'bored',
    PetMood.sleepy: 'sleepy',
    PetMood.celebrating: 'celebrating',
  };

  // ---------- speech bubble (text only, never TTS) ----------

  /// Lettering above the bubble text: the emoticon's, else the mood's for
  /// feelings worth shouting about (plain talk stays plain).
  EmotionFx? get bubbleFx {
    final e = EmotionFx.byEmoticon[bubbleSticker];
    if (e != null) return e;
    const plain = {PetMood.idle, PetMood.talking, PetMood.thinking};
    final m = _overrideMood;
    return m == null || plain.contains(m) ? null : EmotionFx.byMood[m];
  }

  void _say(String text, {required PetMood mood, bool log = false, String? sticker}) {
    bubbleText = text;
    bubbleSticker = sticker;
    _overrideMood = mood;
    _overrideUntil = DateTime.now().add(const Duration(seconds: 8));
    if (log) {
      memory.addMessage(memory.active,
          ChatMessage(text: text, fromUser: false, at: DateTime.now(), sticker: sticker));
    }
    _bubbleTimer?.cancel();
    // Longer replies stay up longer (about 6 chars/sec, 9-30 s).
    final secs = (text.length / 6).clamp(9, 30).round();
    _bubbleTimer = Timer(Duration(seconds: secs), () {
      bubbleText = null;
      bubbleSticker = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// A care/life event as an emoticon: shown in the bubble and posted to
  /// the 일상 chat like a KakaoTalk emoticon.
  void _emote(String id) {
    final e = Emoticons.byId(id);
    if (e == null) return;
    bubbleSticker = id;
    memory.addMessage(memory.projects.first,
        ChatMessage(text: e.caption, fromUser: false, at: DateTime.now(), sticker: id));
    memory.save();
    notifyListeners();
  }

  /// The owner sends an emoticon from the chat picker; the pet reacts and
  /// answers with one of its own.
  void sendSticker(String id) {
    final e = Emoticons.byId(id);
    if (e == null) return;
    final room = memory.active;
    memory.addMessage(room, ChatMessage(text: e.caption, fromUser: true, at: DateTime.now(), sticker: id));
    _ownerAt = DateTime.now();
    if (!sleeping) {
      switch (id) {
        case 'yummy' || 'hungry':
          if (feedBlock == null) return feed();
        case 'yay' || 'playwithme':
          if (playBlock == null) return play();
        case 'love' || 'tickle' || 'thanks':
          happiness = (happiness + 3).clamp(0, 100);
          _act(id == 'tickle' ? 'tickle' : 'pet');
      }
    }
    final reply = Emoticons.byId(sleeping ? 'night' : Emoticons.replyTo(id))!;
    Timer(const Duration(milliseconds: 700), () {
      memory.addMessage(room, ChatMessage(text: reply.caption, fromUser: false, at: DateTime.now(), sticker: reply.id));
      _say(reply.caption, mood: reply.still, sticker: reply.id);
      memory.save();
    });
    memory.save();
    notifyListeners();
  }

  /// Bubble text without changing the displayed pose.
  void _sayKeepPose(String text) {
    bubbleText = text;
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(const Duration(seconds: 6), () {
      bubbleText = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // ---------- owner profile ----------

  /// Pushes profile values into the services (call after editing it).
  void applyProfile() {
    Lang.code = profile.language;
    weather
      ..homeName = profile.placeName
      ..homeLat = profile.lat
      ..homeLon = profile.lon;
    market
      ..stockSymbol = profile.stockSymbol
      ..stockName = profile.stockName;
  }

  /// Settings: switch to another character pack (Hoodies friends).
  Future<void> setCharacter(String id) async {
    await Character.load(id);
    await PetClips.load();
    await updateProfile((p) => p.character = Character.current.id);
    _act('wave');
    _say(
        Lang.t('안녕! 나는 ${Character.current.displayName}이야 👋',
            'Hi! I\'m ${Character.current.displayName} 👋', '你好！我是${Character.current.displayName} 👋'),
        mood: PetMood.waving);
  }

  Future<void> updateProfile(void Function(OwnerProfile p) change) async {
    change(profile);
    applyProfile();
    await profile.save();
    await weather.refresh();
    notifyListeners();
  }

  // ---------- notes (Obsidian folder) ----------

  /// [text] empty = save the pet's last reply in this chat.
  Future<String> _saveNote(ProjectContext p, String text) async {
    if (!notes.ready) {
      return Lang.t('노트 폴더가 아직 없어! 설정 > 노트에서 옵시디언 폴더를 한 번만 골라줘 📁',
          'No notes folder yet! Pick your Obsidian folder once in Settings > Notes 📁', '还没有笔记文件夹！请在 设置 > 笔记 里选一次你的 Obsidian 文件夹 📁');
    }
    var body = text;
    if (body.isEmpty) {
      final last = p.chat.lastWhere((m) => !m.fromUser,
          orElse: () => ChatMessage(text: '', fromUser: false, at: DateTime.now()));
      body = last.text;
    }
    if (body.trim().isEmpty) {
      return Lang.t('저장할 내용이 없어. "/노트 우유 사기"처럼 말해줘!',
          'Nothing to save. Try "/note buy milk"!', '没有要保存的内容。试试 "/note 买牛奶"！');
    }
    final ok = await notes.append(p.name, body);
    return ok
        ? Lang.t('📝 노트에 적어 뒀어! (${Notes.fileFor(p.name)})',
            '📝 Saved to your notes! (${Notes.fileFor(p.name)})', '📝 已存到笔记里啦！(${Notes.fileFor(p.name)})')
        : Lang.t('앗, 노트 폴더에 쓰지 못했어. NAS가 연결돼 있는지 확인해 줘!',
            'Oops, I couldn\'t write to the notes folder. Is the drive connected?', '哎呀，笔记文件夹写不进去。硬盘连接好了吗？');
  }

  Future<String?> pickNotesFolder() async {
    final p = await notes.pick();
    notifyListeners();
    return p;
  }

  // ---------- AI chat ----------

  String _context() {
    final w = weather.current;
    return [
      switch (profile.language) {
        'ko' => '대답은 한국어로 해.',
        'zh' => 'Always reply in Simplified Chinese (简体中文).',
        _ => 'Always reply in English.',
      },
      if (profile.about.trim().isNotEmpty) 'Owner: ${profile.about.trim()}',
      if (profile.homeLine.isNotEmpty)
        'Owner lives in ${profile.homeLine}. For local, weather or news questions use this place '
            'and this country (search in its language, e.g. US news in English), even when chatting in '
            'another language, unless the owner names another place.',
      'Now: ${DateTime.now().toIso8601String().substring(0, 16)} (local time)',
      Lang.t(
          '펫 스탯: 포만감 ${hunger.round()}, 행복 ${happiness.round()}, '
              '건강 ${health.round()}, 에너지 ${energy.round()}${sleeping ? ' (자는 중)' : ''}',
          'Pet stats: hunger ${hunger.round()}, happy ${happiness.round()}, '
              'health ${health.round()}, energy ${energy.round()}${sleeping ? ' (sleeping)' : ''}'),
      if (w != null) Lang.t('날씨: ${w.summary}', 'Weather: ${w.summary}', '天气：${w.summary}'),
      if (market.current != null) 'Owner portfolio: ${market.current!.headline}',
      if (reminders.promptLine(DateTime.now()) != null)
        reminders.promptLine(DateTime.now())!,
      memory.promptBlock(),
      if (memory.active.id == Manual.roomId)
        'The owner is asking how this app (Hoodimate, a desktop pet) works. '
            'Answer briefly and only from this manual; if it is not covered, say so:\n'
            '${Manual.text}',
    ].join('\n');
  }

  Future<void> sendChat(String text) async {
    text = text.trim();
    if (text.isEmpty || thinking) return;
    if (sleeping) _wakeForOwner();
    final from = memory.active;
    final userMsg = ChatMessage(text: text, fromUser: true, at: DateTime.now());
    // Reminder commands are handled here, without the AI (works offline
    // and without an API key).
    // "Let's talk in English" switches the whole app, no menu needed.
    final lang = LanguageSwitch.detect(text);
    if (lang != null && lang != profile.language) {
      memory.addMessage(from, userMsg);
      await updateProfile((p) => p.language = lang);
      _say(LanguageSwitch.confirm(lang), mood: PetMood.happy, log: true);
      await memory.save();
      return;
    }
    final note = Notes.parseCommand(text);
    if (note != null) {
      memory.addMessage(from, userMsg);
      _act('work'); // typing it up on the laptop
      _say(await _saveNote(from, note), mood: PetMood.happy, log: true);
      await memory.save();
      return;
    }
    final reminderReply = reminders.handle(text, DateTime.now());
    if (reminderReply != null) {
      memory.addMessage(from, userMsg);
      _act('done'); // thumbs up, it's set
      _say(reminderReply, mood: PetMood.happy, log: true);
      await reminders.save();
      await memory.save();
      return;
    }
    final provider = ai.active;
    // React to what was said right away, without any AI (1.1). While
    // sulking, or with no AI set up, the pet answers by itself.
    final feel = _feelOwner(text);
    if (sulk.sulking || !provider.isReady) {
      final line = _ownLine(sulk.sulking && feel.isEmpty ? const [OwnerFeeling.sulky] : feel);
      if (line != null) {
        memory.addMessage(from, userMsg);
        if (feel.length > 1) await Future.delayed(PetBrainFeelings._step * (feel.length - 1));
        _say(line.$1, mood: line.$2, log: true, sticker: replyStickers ? line.$3 : null);
        await memory.save();
        return;
      }
    }
    if (!provider.isReady && Ed.current != Edition.personal) {
      // Sold builds: no AI picked yet is a normal first run, not an error.
      memory.addMessage(from, userMsg);
      _say(
          Lang.t('아직 제대로 대화할 수 없어. 괜찮을 때 설정에서 AI를 골라 줘. 그때까지는 밥 주고, 놀아 주고, 알람을 맞춰 봐!',
              'I can\'t chat properly yet — pick an AI in Settings when you like. Until then, feed me, play with me, or set an alarm!',
              '我现在还不能好好聊天——想用时可以在设置里选一个 AI。在那之前，可以喂我、陪我玩，或者设个闹钟！'),
          mood: PetMood.happy,
          log: true);
      await memory.save();
      return;
    }
    if (provider.isReady && ai.needsConsent(provider)) {
      final ok = await askAiConsent?.call(provider.label) ?? false;
      if (!ok) {
        _say(Lang.t('알겠어! AI 대화는 안 보낼게. 돌보기·알람·노트는 그대로 쓸 수 있어.',
            'Okay! I won\'t send chats to an AI. Care, alarms and notes still work.',
            '好的！不会把聊天发给 AI。照顾、闹钟和笔记照常可用。'), mood: PetMood.happy);
        return;
      }
      ai.consented.add(provider.id);
      await ai.save();
    }
    memory.addMessage(from, userMsg);
    thinking = true;
    bubbleText = Lang.t('음... 생각 중', 'Hmm... thinking', '嗯…思考中');
    _bubbleTimer?.cancel();
    notifyListeners();
    try {
      final useTools = ai.toolsEnabled && Ed.agentTools;
      tools
        ..braveKey = ai.braveKey
        ..calendarEnabled = ai.calendarEnabled
        ..homeName = profile.placeName
        ..country = profile.country
        ..homeLat = profile.lat
        ..homeLon = profile.lon;
      final r = await ai.reply(from.chat, _context(),
          tools: useTools ? tools : null, onTool: (name) {
        // show what the pet is doing: laptop pose + a short bubble
        bubbleText = tools.busyLabel(name);
        _act('work');
        notifyListeners();
      });
      if (r.text.trim().isEmpty) {
        throw AiException(Lang.t('${ai.active.label}: 빈 응답이 왔어요.',
            '${ai.active.label}: got an empty reply.', '${ai.active.label}：收到了空回复。'));
      }
      // The AI routes the conversation into a project context.
      final target = from.id == Manual.roomId
          ? from // manual Q&A stays in the manual room
          : (memory.resolve(r.project) ?? from);
      if (target != from) {
        from.chat.remove(userMsg);
        memory.addMessage(target, userMsg);
        memory.activeId = target.id;
      }
      // Manual Q&A is not project work: nothing to remember or file away.
      if (target.id != Manual.roomId) {
        memory.remember(target, r.remember);
        final rem = r.remember?.trim() ?? '';
        if (rem.isNotEmpty) notes.append(target.name, '🧠 $rem');
      }
      thinking = false;
      // Emoticon that fits the talk, not always the mood's one (owner, 2026-10-12).
      _lastReplySticker = replyStickers
          ? Emoticons.forReply(r.text, r.mood, question: text, last: _lastReplySticker)
          : null;
      _say(r.text, mood: r.mood, log: true, sticker: _lastReplySticker);
      voice.speak(r.text);
    } on AiException catch (e) {
      thinking = false;
      _act('failed');
      _say('⚠️ ${e.message}', mood: PetMood.sad, log: true, sticker: 'oops');
    } catch (_) {
      thinking = false;
      _act('failed');
      _say(
          Lang.t('⚠️ 연결이 잘 안 돼. 인터넷이나 설정을 확인해줘.',
              '⚠️ Can\'t connect. Please check your internet or settings.', '⚠️ 连不上，请检查网络或设置。'),
          sticker: 'oops',
          mood: PetMood.sad,
          log: true);
    }
    await memory.save();
  }

  void createProject(String name) {
    final p = memory.create(name);
    if (p == null) return;
    memory.save();
    notifyListeners();
  }

  void archiveProject(String id) {
    final name = memory.projects.firstWhere((p) => p.id == id).label;
    if (!memory.archive(id)) return;
    memory.save();
    _sayKeepPose(Lang.t('"$name" 대화방은 보관함에 넣었어. 설정에서 다시 꺼낼 수 있어!',
        'I put the "$name" chat in the archive. You can bring it back in Settings!', '我把"$name"聊天室放进归档了。可以在设置里再拿出来哦！'));
  }

  void restoreProject(String id) {
    memory.restore(id);
    memory.save();
    notifyListeners();
  }

  /// Settings > Manual: opens the manual chat room (questions asked
  /// there are answered from the manual).
  void openManual() {
    memory.openManual();
    memory.save();
    notifyListeners();
  }

  void switchProject(String id) {
    memory.activeId = id;
    memory.save();
    notifyListeners();
  }

  // ---------- voice input ----------

  Future<void> startListening() async {
    if (listening || thinking) return;
    listening = true;
    bubbleText = Lang.t('듣고 있어...', 'Listening...', '正在听...');
    _bubbleTimer?.cancel();
    notifyListeners();
    final ok = await speech.start(
      onPartial: (t) {
        if (t.isNotEmpty) bubbleText = t;
        notifyListeners();
      },
      onFinal: (t) {
        listening = false;
        notifyListeners();
        if (t.trim().isNotEmpty) {
          sendChat(t);
        } else {
          _say(Lang.t('잘 못 들었어. 다시 말해줄래?', 'I didn\'t catch that. Say it again?', '没听清，能再说一遍吗？'),
              mood: PetMood.talking);
        }
      },
    );
    if (!ok) {
      listening = false;
      _say(
          Lang.t('마이크를 쓸 수 없어. 시스템 설정 > 개인정보 보호에서 마이크·음성 인식을 허용해줘.',
              'I can\'t use the mic. Allow Microphone and Speech Recognition in System Settings > Privacy.', '我用不了麦克风。请在 系统设置 > 隐私与安全性 中允许麦克风和语音识别。'),
          mood: PetMood.sad);
    }
  }

  Future<void> stopListening() async {
    if (!listening) return;
    await speech.stop(); // the final transcript arrives via onFinal
  }

  // ---------- background loop ----------

  /// One minute of life. Paced for a desktop day: a full belly lasts
  /// about 8 hours, a full nap takes about 1.5 hours.
  void _decay() {
    hunger = (hunger - 0.18).clamp(0, 100);
    happiness = (happiness - 0.12).clamp(0, 100);
    if (sleeping) {
      energy = (energy + 1.2).clamp(0, 100);
    } else {
      energy = (energy - 0.06).clamp(0, 100); // ~20 h awake from full
    }
    // Weather affects the pet a little.
    final w = weather.current;
    if (w != null && !sleeping) {
      if (w.isHot) {
        energy = (energy - 0.02).clamp(0, 100); // tires a bit faster
        hunger = (hunger - 0.03).clamp(0, 100); // thirsty
      }
      if (w.isCold) happiness = (happiness - 0.04).clamp(0, 100);
      if (w.sky == Sky.thunder) happiness = (happiness - 0.05).clamp(0, 100);
      if (w.isLovely) happiness = (happiness + 0.04).clamp(0, 100);
    }
    if (hunger < 15) {
      health = (health - 0.4).clamp(0, 100);
    } else if (hunger > 40 && health < 90) {
      health = (health + 0.05).clamp(0, 100);
    }
  }

  /// Bedtime 22:00 (unless the owner is still around: 15 min without
  /// interaction), up at 07:00.
  void _bedtime() {
    final now = DateTime.now();
    final night = CareStats.isNight(now);
    if (night &&
        !sleeping &&
        !thinking &&
        !listening &&
        alarmText == null &&
        energy < 90 && // a rested pet would wake right away again
        hunger >= 20 &&
        now.difference(_ownerAt).inMinutes >= 15) {
      sleeping = true;
      _noticeBedtime();
      _act('yawn');
      _say(Lang.t('밤 10시 넘었다… 졸려. 잘 자, 주인님 💤', 'Past 10 PM… so sleepy. Good night! 💤', '已经过晚上 10 点了…好困。晚安，主人 💤'),
          mood: PetMood.sleepy);
      _save();
    }
  }

  void _onTick() {
    if (demo) return;
    final wasSleeping = sleeping;
    _bedtime();
    _decay();
    _noticeHunger();
    _maybeMarketBrief();
    // Waking up: only when rested (energy full) or hungry (or a shaken
    // mouse, see wakeByShake). Not by clicks or the clock.
    if (wasSleeping && sleeping) {
      if (energy >= 99.5) {
        wakeUp('rested');
      } else if (hunger < 20) {
        wakeUp('hungry');
      }
    }

    // Voice line when the pet enters a new situation (rain, sick, ...).
    final mood = baseMood();
    if (mood != _lastMood) {
      final cue = _moodCues[mood];
      if (cue != null && !thinking && !listening) cues.play(cue);
      // The market changed the mood: say so once (rain and heat already
      // get their own weather lines).
      final why = (mood == PetMood.sad || mood == PetMood.celebrating) ? situationText() : null;
      if (why != null && !thinking && !listening && !sleeping) {
        _say(why, mood: mood, sticker: mood == PetMood.sad ? 'sad' : 'best');
      }
      _lastMood = mood;
    }

    _maybeWeatherNag();
    _idleBehaviour();

    // Idle chatter: bubble only, not logged into the AI conversation.
    if (bubbleText == null &&
        !thinking &&
        !listening &&
        !sleeping &&
        Random().nextDouble() < 0.06) {
      final w = weather.current;
      final lines = hunger < 30
          ? [
              Lang.t('배고파... 쿠키 줘!', 'Hungry... gimme a cookie!', '好饿...给我饼干！'),
              Lang.t('배에서 꼬르륵 소리가 나', 'My tummy is rumbling', '肚子咕咕叫了'),
            ]
          : [
              Lang.t('심심해, 놀아줘!', 'I\'m bored, play with me!', '好无聊，陪我玩嘛！'),
              Lang.t('오늘 뭐 하고 있어?', 'What are you up to today?', '你今天在做什么呀？'),
              Lang.t('필요하면 나 불러!', 'Call me if you need me!', '需要我的话就叫我哦！'),
              if (w != null) Reactions.tempSmallTalk(w, Random()),
            ];
      _say(lines[Random().nextInt(lines.length)], mood: PetMood.talking);
    }
    if (!sleeping && Random().nextDouble() < 0.15) hopSignal++;
    _save();
    notifyListeners();
  }

  // ---------- persistence ----------

  Future<File> _stateFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/pet_state.json');
  }

  Future<void> _save() async {
    if (demo) return; // the scripted tour never touches the real pet state
    try {
      final f = await _stateFile();
      await f.writeAsString(jsonEncode({
        'hunger': hunger,
        'happiness': happiness,
        'health': health,
        'energy': energy,
        'sleeping': sleeping,
        'lastSeen': DateTime.now().toIso8601String(),
        'careAt': _careAt.toIso8601String(),
        'cuesEnabled': cues.enabled,
        'macFallback': cues.macFallback,
        'roam': roam,
        'sfxVolume': Sfx.volume,
        'speechMode': voice.mode.name,
        'haptics': Sfx.haptics,
        'petScale': petScale,
        'panelW': panelW,
        'panelH': panelH,
        'panelTheme': panelTheme,
        'chatFont': CuteFont.cute ? 'cute' : 'system',
        'chatFontScale': CuteFont.scale,
        'replyStickers': replyStickers,
        'onboardingDone': onboardingDone,
        'menuBarEnabled': menuBarEnabled,
        'notifyEnabled': notifyEnabled,
        'sulk': sulk.toJson(),
        'briefedOn': _briefedOn,
        'marketBriefed': _briefed,
      }));
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final f = await _stateFile();
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return;
      final j = Map<String, dynamic>.from(decoded);
      // A wrong-typed field (junk from a synced file) keeps its default; it
      // must not throw away the fields after it.
      double d(String k, double def) {
        final v = j[k];
        return v is num && v.isFinite ? v.toDouble() : def;
      }

      bool bl(String k, bool def) => j[k] is bool ? j[k] as bool : def;
      hunger = d('hunger', hunger).clamp(0, 100);
      happiness = d('happiness', happiness).clamp(0, 100);
      health = d('health', health).clamp(0, 100);
      energy = d('energy', energy).clamp(0, 100);
      sleeping = bl('sleeping', false);
      _careAt = DateTime.tryParse(j['careAt']?.toString() ?? '') ?? _careAt;
      // Time keeps passing while the app is closed (capped at 12 h so a
      // long weekend doesn't leave the pet sick on return).
      final seen = DateTime.tryParse(j['lastSeen']?.toString() ?? '');
      if (seen != null) {
        final mins = DateTime.now().difference(seen).inMinutes.clamp(0, 720);
        final healthBefore = health;
        for (var i = 0; i < mins; i++) {
          _decay();
        }
        // Hungry and a bit worn out is fine; starving to 0 health while the
        // app was simply closed is not (12 h of replay would do exactly that).
        final floor = min(healthBefore, 40.0);
        if (health < floor) health = floor;
      }
      cues.enabled = bl('cuesEnabled', true);
      cues.macFallback = bl('macFallback', true);
      roam = bl('roam', true);
      Sfx.volume = d('sfxVolume', 0.6).clamp(0, 1);
      Sfx.haptics = bl('haptics', true);
      voice.mode = SpeechMode.values
          .firstWhere((m) => m.name == j['speechMode'], orElse: () => SpeechMode.off);
      _briefedOn = j['briefedOn'] is String ? j['briefedOn'] as String : null;
      final mb = j['marketBriefed'];
      if (mb is Map) {
        _briefed.addAll(mb.map((k, v) => MapEntry(k.toString(), v.toString())));
      }
      petScale = d('petScale', 1.0).clamp(0.6, 1.6);
      panelW = d('panelW', panelDefault.width).clamp(panelMin.width, panelMax.width);
      panelH = d('panelH', panelDefault.height).clamp(panelMin.height, panelMax.height);
      panelTheme = (j['panelTheme'] ?? 'cream').toString();
      CuteFont.cute = j['chatFont'] != 'system';
      CuteFont.scale = d('chatFontScale', 1.0).clamp(0.85, 1.5);
      replyStickers = bl('replyStickers', true);
      onboardingDone = Onboarding.savedDone(j);
      menuBarEnabled = bl('menuBarEnabled', true);
      notifyEnabled = bl('notifyEnabled', false);
      final sk = j['sulk'];
      if (sk is Map) {
        final s0 = SulkState.fromJson(Map<String, dynamic>.from(sk));
        sulk
          ..sulking = s0.sulking
          ..niceCount = s0.niceCount;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _bubbleTimer?.cancel();
    _alarmRing?.cancel();
    _alarmStop?.cancel();
    super.dispose();
  }

  // ---------- state used by the part files (brain_*.dart) ----------

  /// notifyListeners for the extensions in the part files.
  void _notify() => notifyListeners();

  // Test seams for the private care loop (see test/logic_audit_care_test.dart).
  @visibleForTesting
  void debugTick() => _onTick();
  @visibleForTesting
  void debugDecay() => _decay();
  @visibleForTesting
  void debugBedtime() => _bedtime();
  @visibleForTesting
  void debugStartAlarm(String text, String time) => _startAlarm(text, time);
  @visibleForTesting
  Future<void> debugLoad() => _load();
  @visibleForTesting
  Future<void> debugSave() => _save();

  Offset? startAt; // one-off launch position (filming)

  /// Due reminders not shown yet (held while thinking/listening).
  final List<Reminder> _pending = [];
  DateTime? _startedAt;
  /// Ringing alarm: the pet grabs a big clock and runs around the screen
  /// until caught with a click; stops by itself after a minute.
  String? alarmText;
  String? alarmTime;
  Timer? _alarmRing;
  Timer? _alarmStop;
  String? _lastSituation;
  String? _briefedOn; // yyyy-mm-dd of the last daily briefing
  static const briefHours = [10, 17];
  final Map<String, String> _briefed = {}; // '10' -> yyyy-mm-dd
  DateTime? _weatherSaidAt;
  String? _marketDay; // yyyy-mm-dd of [_marketShown]
  int _marketShown = 0; // strongest tier already reacted to today
  bool demo = false;

  /// Filming the real app on the desktop (demo.flag "film x y"): the normal
  /// window, driven through a short tour by [runFilm]. [filmUi] is set by the
  /// pet window: open | close | care | chat.
  bool film = false;
  void Function(String action)? filmUi;
  String demoCaption = '';
  bool demoGaze = false; // eyes follow a scripted "cursor"
  bool demoFace = false; // chat close-up scene
  bool demoPointer = false; // hand cursor about to catch the pet
  List<String> demoChat = []; // 'U:..' / 'P:..'
  final List<Map<String, Object>> _demoLog = [];
  DateTime _demoT0 = DateTime.now();
  /// 'ko' or 'en' (from the demo.flag contents).
  String demoLang = 'ko';
  double demoX = 240; // stage window left edge on screen
  bool demoStats = false; // show the care stat bars
  /// Settings switch: little walks and gestures when nobody is around.
  bool roam = true;
  /// Bumped when the pet should take a few steps; [wanderDx] = pixels.
  int wanderSignal = 0;
  double wanderDx = 0;
  /// Rises while the pet is ignored (each whine). At 2+ the 혼내기 button
  /// in the care panel works; any care or scolding resets it.
  int whine = 0;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  /// Once-a-day moments: the owner's birthday, Halloween, weekday 6 PM
  /// "off work". True when one played.
  final Map<String, String> _moments = {};
  bool syncing = false;
  /// Last care action (feed, play, medicine, sleep, scold): sync prefers
  /// the Mac where the pet was actually cared for.
  DateTime _careAt = DateTime.fromMillisecondsSinceEpoch(0);
  /// Owner interaction wakes a napping pet once it has some energy back.
  DateTime _ownerAt = DateTime.now();
}
