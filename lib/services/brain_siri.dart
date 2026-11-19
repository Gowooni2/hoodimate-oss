part of 'pet_brain.dart';

/// Siri / Shortcuts (owner, 2026-10-28): macos/Runner/SiriIntents.swift
/// hands "Ask Hoodimate", "Hoodimate reminder" and "Feed Hoodimate" over
/// here. They go through the same paths as typing, so consent, the chosen
/// AI and the offline reminder parser behave exactly the same.
extension PetBrainSiri on PetBrain {
  static const _siri = MethodChannel('hoodimong/siri');

  Future<void> _initSiri() async {
    _siri.setMethodCallHandler((call) async {
      final a = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : const <String, dynamic>{};
      return switch (call.method) {
        'ask' => siriAsk('${a['text'] ?? ''}'),
        'remind' => siriRemind(a['minutes'] is num ? (a['minutes'] as num).round() : 0, '${a['text'] ?? ''}'),
        'feed' => siriFeed(),
        'feeling' => siriFeeling(),
        _ => throw MissingPluginException(call.method),
      };
    });
    try {
      await _siri.invokeMethod('ready');
    } catch (_) {} // tests and older hosts have no Siri side
  }

  String get _busy => Lang.t('지금 생각하는 중이야. 조금 있다가 다시 물어봐!', "I'm still thinking. Ask me again in a moment!", '我还在想呢，等一下再问我吧！');

  /// What the pet said last, for Siri to read out.
  String _lastPetLine() {
    final chat = memory.active.chat;
    for (var i = chat.length - 1; i >= 0; i--) {
      if (!chat[i].fromUser && chat[i].text.trim().isNotEmpty) return chat[i].text.trim();
    }
    return bubbleText?.trim() ?? '';
  }

  Future<String> siriAsk(String text) async {
    text = text.trim();
    if (text.isEmpty) return Lang.t('뭐라고 했는지 못 들었어. 다시 말해 줄래?', "I didn't catch that. Say it again?", '没听清，再说一遍好吗？');
    if (thinking) return _busy;
    // Siri and Shortcuts can't show the consent dialog (App Review 5.1.2(i)):
    // nothing goes to a cloud AI until the owner agreed in the app.
    // (The pet still answers by itself while sulking or with no AI set up.)
    final p = ai.active;
    if (!sulk.sulking && p.isReady && ai.needsConsent(p)) return siriNeedsConsent;
    final before = _lastPetLine();
    final count = memory.active.chat.length;
    await sendChat(text);
    final after = _lastPetLine();
    final said = (memory.active.chat.length == count && after == before) ? (bubbleText?.trim() ?? '') : after;
    // Error lines carry the provider's name and raw messages: Siri reads a
    // plain line instead (the details stay in the app's chat).
    if (said.startsWith('⚠️')) {
      return Lang.t('지금은 대답하기 어려워. 앱에서 확인해 줘.', "I can't answer right now. Please check the app.", '现在没法回答，请到应用里看看。');
    }
    return said;
  }

  static String get siriNeedsConsent => Lang.t(
      '아직 AI로 대화를 보내도 된다는 동의를 받지 않았어. 후디메이트를 열고 대화창에서 한 번 동의해 줘.',
      "I haven't been allowed to send chats to an AI yet. Open Hoodimate and agree once in the chat.",
      '还没有同意把聊天发送给 AI。请打开 Hoodimate，在聊天窗口里同意一次。');

  Future<String> siriRemind(int minutes, String what) async {
    if (minutes <= 0) return Lang.t('몇 분 뒤에 알려 줄까?', 'In how many minutes?', '几分钟后提醒你？');
    what = what.trim().isEmpty ? Lang.t('알람', 'alarm', '闹钟') : what.trim();
    // A sentence the offline reminder parser understands in each language.
    return siriAsk(Lang.t('$minutes분 뒤에 $what 알려줘', 'remind me in $minutes minutes to $what', '$minutes分钟后提醒我$what'));
  }

  String siriFeed() {
    final block = feedBlock;
    if (block != null) return block;
    feed();
    return bubbleText?.trim().isNotEmpty == true ? bubbleText!.trim() : Lang.t('냠냠! 고마워!', 'Yum! Thank you!', '好吃！谢谢！');
  }

  /// "How is Hoodimate feeling?": the pet's own state, spoken. Never goes to
  /// an AI, so it works before (and without) any AI consent.
  String siriFeeling() {
    final n = Character.current.displayName;
    return Lang.t(
        '$n: ${stats.needText()} 배부름 ${hunger.round()}%, 기운 ${energy.round()}%, 기분 ${happiness.round()}%예요.',
        '$n: ${stats.needText()} Fullness ${hunger.round()}%, energy ${energy.round()}%, happiness ${happiness.round()}%.',
        '$n：${stats.needText()} 饱腹 ${hunger.round()}%，体力 ${energy.round()}%，心情 ${happiness.round()}%。');
  }
}
