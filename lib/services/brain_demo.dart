part of 'pet_brain.dart';

/// Demo mode for promo videos.
extension PetBrainDemo on PetBrain {
  // ---------- demo mode (promo video recording) ----------
  //
  // Start: create `demo.flag` in the app's support folder, launch the app.
  // The window becomes a clean 1080x1920 stage (see DemoStage) and the pet
  // walks through its features with captions; the timeline (with the voice
  // files played) is written to demo_timeline.json for the audio mix.


  Future<File> _demoFile(String name) async =>
      File('${(await getApplicationSupportDirectory()).path}/$name');

  Future<bool> _takeDemoFlag() async {
    try {
      final f = await _demoFile('demo.flag');
      if (await f.exists()) {
        // "ko" / "en", optionally followed by the stage's screen x
        // (placed away from the mouse cursor so it isn't recorded).
        final parts = (await f.readAsString()).trim().split(RegExp(r'\s+'));
        if (parts.first == 'film' && parts.length >= 3) {
          // The real app on the desktop, driven through [runFilm].
          startAt = Offset(double.tryParse(parts[1]) ?? 0, double.tryParse(parts[2]) ?? 0);
          film = true;
          await f.delete();
          return false;
        }
        if (parts.first == 'move' && parts.length >= 3) {
          // Not a demo: just start the normal pet at a given screen spot
          // (used to film the real app on a clean part of the desktop).
          startAt = Offset(double.tryParse(parts[1]) ?? 0, double.tryParse(parts[2]) ?? 0);
          return false;
        }
        demoLang = parts.first == 'en' ? 'en' : 'ko';
        if (parts.length > 1) demoX = double.tryParse(parts[1]) ?? demoX;
        await f.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _demoMark(String what, {String? cue}) {
    String? file;
    if (cue != null) {
      cues.lastPlayed = null;
      cues.play(cue, force: true);
      file = cues.lastPlayed;
    }
    _demoLog.add({
      't': DateTime.now().difference(_demoT0).inMilliseconds,
      if (what == 'start') 'epochMs': _demoT0.millisecondsSinceEpoch,
      'what': what,
      if (file != null) 'file': file,
    });
  }

  void _demoScene(String caption) {
    demoCaption = caption;
    _notify();
  }

  /// Store-build tour of the real app for the product page (about 35 s):
  /// hello, feeding, a chat with the AI that's selected, an emoticon, the
  /// alarm chase, the five Hoodies. Marks go to demo_timeline_film.json so
  /// tools/make_film.py can lay the app's own sounds under the recording.
  Future<void> runFilm() async {
    Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));
    sleeping = false;
    bubbleText = null;
    hunger = 28;
    happiness = 74;
    health = 92;
    energy = 82;
    _demoT0 = DateTime.now();
    _demoLog.clear();
    _demoMark('start');
    _notify();
    await wait(1500);

    _demoMark('hello', cue: 'greeting');
    _act('wave');
    _say("Hi! I'm ${Character.current.displayName} 👋", mood: PetMood.waving, sticker: 'hello');
    await wait(3000);

    filmUi?.call('open');
    filmUi?.call('care');
    await wait(1800);
    _demoMark('feed');
    feed();
    await wait(3600);

    filmUi?.call('chat');
    await wait(1200);
    _demoMark('ask');
    unawaited(sendChat('Any fun idea for this afternoon?'));
    for (var i = 0; i < 40 && !thinking; i++) {
      await wait(50);
    }
    for (var i = 0; i < 120 && thinking; i++) {
      await wait(100);
    }
    _demoMark('answer');
    await wait(3600);
    _demoMark('sticker');
    sendSticker('love');
    await wait(3000);

    filmUi?.call('close');
    await wait(1200);
    _demoMark('alarm');
    _startAlarm('Stretch time!', '');
    await wait(4500);
    _demoMark('catch', cue: 'happy');
    catchAlarm();
    await wait(2800);

    // Each Hoodie shows its personality (HOODIES_CHARACTERS.md).
    const turns = [
      ('saebom', 'think', 'The curious one!', 'hmm'),
      ('daljam', 'yawn', 'The night-owl dreamer… yawn', 'sleepy'),
      ('morang', 'cheer', 'The tiny daredevil! Go go!', 'best'),
      ('sobok', 'listen', "The gentle listener. I'm all ears.", 'listening'),
      ('mongsil', 'wave', 'The easygoing one. Snack time?', 'yummy'),
    ];
    for (final (id, act, line, sticker) in turns) {
      _demoMark('char_$id');
      await setCharacter(id);
      _act(act);
      _say(line, mood: PetMood.happy, sticker: sticker);
      await wait(1900);
    }
    _demoMark('outro');
    _say('Hoodimate · a virtual pet for your Mac', mood: PetMood.happy, sticker: 'love');
    await wait(3500);
    _demoMark('end');
    try {
      await (await _demoFile('demo_timeline_film.json'))
          .writeAsString(const JsonEncoder.withIndent(' ').convert(_demoLog));
    } catch (_) {}
  }

  Future<void> runDemo() async {
    Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));
    final en = demoLang == 'en';
    String t(String ko, String e) => en ? e : ko;
    sleeping = false;
    panelOpen = false;
    bubbleText = null;
    hunger = 22; // hungry for the feeding scene
    happiness = 70;
    health = 92;
    energy = 78;
    _demoT0 = DateTime.now();
    _demoLog.clear();
    _demoMark('start');
    await wait(800);

    // 1. Hook: the alarm chase.
    _demoScene(t('알람이 울리면 ${Character.current.displayName}가 도망쳐요!\n잡아야 꺼져요 ⏰',
        'When the alarm rings, ${Character.current.displayName} runs!\nCatch it to stop it ⏰'));
    _startAlarm(t('일어날 시간', 'Wake up'), '7:00');
    bubbleText = t('⏰ 따르릉! 일어날 시간이야! 나 잡아봐~', '⏰ RING RING! Time to wake up! Catch me~');
    _demoMark('alarm');
    await wait(4200);
    _stopAlarm();
    bubbleText = null;

    // 2. What it is.
    _demoScene(t('키우는 펫 + AI 비서\n= 후디메이트 🐣🤖',
        'Virtual pet + AI agent\n= Hoodimate 🐣🤖'));
    _act('wave');
    _say(t('안녕! 나는 ${Character.current.displayName}야 👋', "Hi! I'm ${Character.current.displayName} 👋"), mood: PetMood.waving);
    _demoMark('intro', cue: 'greeting');
    await wait(4000);

    // 3. Pet care.
    _demoScene(t('배고프면 밥을 줘요 🍪\n돌봐 주며 키워요',
        "Feed it when it's hungry 🍪\nTake care of it and watch it grow"));
    demoStats = true;
    _notify();
    await wait(1200);
    hunger = 88;
    happiness = 84;
    _act('eat');
    _say(t('냠냠! 맛있다 🍪', 'Yum yum! 🍪'), mood: PetMood.eating);
    _demoMark('eat', cue: 'eating');
    await wait(3800);
    demoStats = false;

    // 4. Eyes.
    _demoScene(t('마우스를 따라\n눈을 맞춰요 👀', 'Its eyes follow\nyour cursor 👀'));
    bubbleText = null;
    _overrideMood = null;
    demoGaze = true;
    _demoMark('eyes');
    _notify();
    await wait(4200);
    demoGaze = false;

    // 5-8. Agent: weather, market, news.
    _demoScene(t('AI 비서: 날씨에 반응해요 ☀️\nLA 지금 97°F!',
        'AI agent: reacts to the weather ☀️\n97°F in LA right now!'));
    _act('fan');
    _say(t('헥헥… 지금 97°F래! 녹겠다아…', "Phew… it's 97°F! I'm melting…"), mood: PetMood.hot);
    _demoMark('hot', cue: 'hot');
    await wait(4600);

    _demoScene(t('주식이 떨어지면\n같이 우울해요 📉', 'Stocks down?\nIt gets gloomy with you 📉'));
    _act('gloomy');
    _say(t('오늘 주인님 주식이 바닥이네요… 제 마음도 좋지 못해요 😢',
        "Your stocks hit the floor today… I'm sad too 😢"), mood: PetMood.sad);
    _demoMark('down', cue: 'sad');
    await wait(4800);

    _demoScene(t('오르면 같이 신나요 📈', 'Stocks up? It celebrates 📈'));
    _act('cheer');
    _say(t('우와아! 오늘 대박이야! 🎉', "Woohoo! Big day! 🎉"), mood: PetMood.celebrating);
    _demoMark('up', cue: 'celebrating');
    await wait(4200);

    _demoScene(t('큰 뉴스는\n깜짝 알려줘요 📰', 'Big news?\nIt tells you right away 📰'));
    _act('news');
    _say(t('📰 깜짝 뉴스! [SK hynix] 사상 최고가!', '📰 Breaking! [SK hynix] hits a record high!'),
        mood: PetMood.talking);
    _demoMark('news');
    await wait(4200);

    // 9. Chat close-up.
    _demoScene(t('AI 비서와 대화해요 💬\n얼굴을 크게, 눈을 맞추며', 'Chat with your AI agent 💬\nface to face'));
    bubbleText = null;
    demoFace = true;
    demoGaze = true;
    demoChat = [t('U:오늘 LA 날씨 어때?', "U:How's the weather in LA?")];
    thinking = true;
    _demoMark('face');
    _notify();
    await wait(2000);
    thinking = false;
    demoChat = [
      ...demoChat,
      t('P:지금 97°F라 엄청 더워! 물 많이 마시고 시원하게 있어 🥤',
          "P:It's 97°F — super hot! Drink lots of water 🥤"),
    ];
    _notify();
    await wait(4200);
    demoFace = false;
    demoGaze = false;
    demoChat = [];

    // 10. Reminders and notes by voice/text.
    _demoScene(t('"10분 뒤 물 마시기 알람 해줘"\n말로 알람·노트까지 ⏰📝',
        '"Remind me to drink water in 10 min"\nAlarms & notes, just ask ⏰📝'));
    _say(t('알았어! 오후 3:10에 "물 마시기" 알려줄게 ⏰', 'Got it! I\'ll remind you at 3:10 PM ⏰'),
        mood: PetMood.happy);
    _demoMark('remind');
    await wait(3600);

    // 11. Finale: chase and catch.
    _demoScene(t('시간이 되면 시계 들고 도망!\n잡는 재미에 잠이 깨요 🏃', "Time's up — it grabs the clock and runs!\nCatching it wakes you up 🏃"));
    _startAlarm(t('물 마시기', 'Drink water'), '3:10');
    bubbleText = t('⏰ 따르릉! 물 마실 시간! 나 잡아봐~', '⏰ RING! Water time! Catch me~');
    _demoMark('alarm2');
    await wait(5600);
    demoPointer = true;
    _notify();
    await wait(900);
    demoPointer = false;
    _stopAlarm();
    _act('jump');
    _say(t('잡았다! 😆 물 마셔!', 'You got me! 😆 Drink up!'), mood: PetMood.happy);
    _demoMark('catch', cue: 'happy');
    await wait(3200);

    // 12. Outro.
    _demoScene(t('후디메이트\nMac 데스크탑 펫', 'Hoodimate\nA desktop pet for Mac'));
    _act('wave');
    _say(t('또 만나요! 👋', 'See you! 👋'), mood: PetMood.happy);
    _demoMark('outro');
    await wait(3600);
    _demoMark('end');
    try {
      await (await _demoFile('demo_timeline_$demoLang.json'))
          .writeAsString(jsonEncode(_demoLog));
    } catch (_) {}
  }
}
