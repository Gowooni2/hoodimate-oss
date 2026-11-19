part of 'pet_brain.dart';

/// Care, touch, idle life.
extension PetBrainCare on PetBrain {
  // ---------- touch (mouse) reactions ----------

  bool _cool(PetReaction r, Duration d) {
    final last = _reactedAt[r];
    final now = DateTime.now();
    if (last != null && now.difference(last) < d) return false;
    _reactedAt[r] = now;
    return true;
  }

  void _react(PetReaction r) {
    reaction = r;
    reactionSignal++;
    _notify();
  }

  /// Cursor touched the body (no click). Small wiggle; a sick pet is
  /// comforted and says thanks.
  void onTouched() {
    if (alarmText != null) return; // ringing: only a click (catch) counts
    if (sleeping && _wakeForOwner()) return;
    if (sleeping || thinking || listening) return;
    if (health < 30) {
      if (!_cool(PetReaction.thanks, const Duration(seconds: 30))) return;
      health = (health + 3).clamp(0, 100);
      happiness = (happiness + 4).clamp(0, 100);
      _act('thanks');
      _react(PetReaction.thanks);
      _say(Lang.t('고마워... 조금 나아졌어', 'Thanks... I feel a bit better', '谢谢…我好一点了'),
          mood: PetMood.sick);
      cues.play('thanks', force: true);
      _save();
      return;
    }
    if (_cool(PetReaction.boop, const Duration(seconds: 4))) {
      _react(PetReaction.boop);
    }
  }

  /// Cursor rubbed back and forth over the head.
  void onPetted() {
    if (alarmText != null) return;
    if (sleeping) {
      if (_cool(PetReaction.pet, const Duration(seconds: 20))) {
        _react(PetReaction.pet);
        _say(Lang.t('으음... 쿨...', 'Mmm... zzz...', '嗯…呼…'), mood: PetMood.sleepy);
      }
      return;
    }
    if (health < 30) return onTouched();
    if (!_cool(PetReaction.pet, const Duration(seconds: 12))) return;
    happiness = (happiness + 6).clamp(0, 100);
    _act('pet');
    _react(PetReaction.pet);
    _say(
        [
          Lang.t('헤헤, 좋아~', 'Hehe, nice~', '嘿嘿，好舒服~'),
          Lang.t('더 쓰다듬어 줘!', 'More pets, please!', '再多摸摸嘛！'),
          Lang.t('기분 최고야~', 'Best feeling ever~', '心情最棒啦~'),
        ][Random().nextInt(3)],
        mood: PetMood.happy);
    bubbleSticker = 'love'; // bubble only: petting is too frequent for the chat log
    cues.play('pet', force: true);
    _save();
  }

  /// Fast wiggling over the belly.
  void onTickled() {
    if (alarmText != null) return;
    if (sleeping || health < 30) return onTouched();
    if (!_cool(PetReaction.tickle, const Duration(seconds: 10))) return;
    happiness = (happiness + 4).clamp(0, 100);
    energy = (energy - 2).clamp(0, 100);
    _act('tickle');
    _react(PetReaction.tickle);
    // Keep the current pose (no arm-spread sprite); the wiggle comes from
    // the tickle reaction or the act_tickle clip once installed.
    _sayKeepPose([
      Lang.t('히히, 간지러워!', 'Hehe, that tickles!', '嘿嘿，好痒！'),
      Lang.t('꺄하하! 그만~', 'Ahaha! Stoooop~', '哈哈哈！别闹啦~'),
      Lang.t('거기 간지러워!', 'That spot tickles!', '那里好痒！'),
    ][Random().nextInt(3)]);
    cues.play('tickle', force: true);
    _save();
  }

  // ---------- care actions ----------

  void feed() {
    if (feedBlock != null) return;
    _careAt = DateTime.now();
    whine = 0;
    hunger = (hunger + 25).clamp(0, 100);
    happiness = (happiness + 5).clamp(0, 100);
    _act('eat');
    _say(Lang.t('냠냠! 맛있어!', 'Yum yum! Tasty!', '吧唧吧唧！好好吃！'), mood: PetMood.eating);
    _emote('yummy');
    cues.play('eating', force: true);
    _save();
  }

  void play() {
    if (playBlock != null) return;
    _careAt = DateTime.now();
    whine = 0;
    happiness = (happiness + 15).clamp(0, 100);
    energy = (energy - 10).clamp(0, 100);
    hunger = (hunger - 5).clamp(0, 100);
    _act('jump');
    _say(Lang.t('신나!', 'Yay!', '耶！'), mood: PetMood.happy);
    _emote('yay');
    cues.play('happy', force: true);
    _save();
  }

  void medicine() {
    if (medicineBlock != null) return;
    _careAt = DateTime.now();
    whine = 0;
    health = (health + 35).clamp(0, 100);
    _act('medicine');
    happiness = (happiness - 5).clamp(0, 100); // medicine tastes bad
    _say(Lang.t('으, 써... 그래도 나을 거야!', 'Ew, bitter... but I\'ll get better!', '呃，好苦…不过我会好起来的！'),
        mood: PetMood.happy);
    _emote('thanks');
    cues.play('happy', force: true);
    _save();
  }

  // ---------- random idle behaviour (vscode-pets style) ----------



  void setRoam(bool v) {
    roam = v;
    _notify();
    _save();
  }

  /// Button sounds (0..1) and trackpad haptics, see Sfx.
  void setSfxVolume(double v) {
    Sfx.volume = v.clamp(0, 1);
    _notify();
    _save();
  }

  /// Settings: read AI replies aloud (off / Mac voice / ElevenLabs).
  void setSpeechMode(SpeechMode m) {
    voice.mode = m;
    if (m == SpeechMode.off) voice.stop();
    _notify();
    _save();
  }

  void setHaptics(bool v) {
    Sfx.haptics = v;
    _notify();
    _save();
  }

  // ---------- whining and scolding ----------


  String? get scoldBlock {
    if (sleeping) return Lang.t('자는 중', 'Sleeping', '睡觉中');
    if (whine >= 2) return null;
    return Lang.t('찡찡대지 않을 땐 혼낼 일이 없어요', 'Nothing to scold right now', '没有闹脾气的时候，没什么好骂的哦');
  }

  void _whine() {
    whine++;
    final lines = whine == 1
        ? [Lang.t('심심해~', 'I\'m bored~', '好无聊~'), Lang.t('뭐 해? 나 좀 봐줘~', 'What are you doing? Look at me~', '你在做什么？看看我嘛~')]
        : whine == 2
            ? [Lang.t('놀아줘, 놀아줘~ 🥺', 'Play with me, play with me~ 🥺', '陪我玩嘛，陪我玩嘛~ 🥺'), Lang.t('나랑 놀자아~', 'Let\'s plaaay~', '跟我玩啦~')]
            : [Lang.t('놀아줘어어어!! 😭', 'PLAY WITH MEEE!! 😭', '陪我玩啊啊啊！！😭'), Lang.t('흐에엥 아무도 안 놀아줘 😭', 'Waaah, nobody plays with me 😭', '呜哇，都没人陪我玩 😭')];
    _say(lines[Random().nextInt(lines.length)], mood: PetMood.talking);
    _emote('playwithme');
    cues.play('bored', force: true);
    _act(whine >= 2 ? 'whine' : 'sigh');
    if (whine >= 3) hopSignal++;
  }

  bool _dailyMoment(DateTime now) {
    final today = now.toIso8601String().substring(0, 10);
    bool once(String k) {
      if (_moments[k] == today) return false;
      _moments[k] = today;
      return true;
    }

    if (profile.isBirthday(now) && once('birthday')) {
      _act('birthday');
      cues.play('celebrating', force: true);
      _say(Lang.t('🎂 생일 축하해!! 오늘은 최고의 날이야 🎉', '🎂 Happy birthday!! Best day ever 🎉', '🎂 生日快乐！！今天是最棒的一天 🎉'),
          mood: PetMood.celebrating);
      return true;
    }
    if (now.month == 10 && now.day == 31 && once('halloween')) {
      _act('halloween');
      _say(Lang.t('🎃 해피 할로윈! 트릭 오어 트릿~', '🎃 Happy Halloween! Trick or treat~', '🎃 万圣节快乐！不给糖就捣蛋~'),
          mood: PetMood.happy);
      return true;
    }
    if (now.weekday <= 5 && now.hour == 18 && once('offwork')) {
      _act('offwork');
      _say(Lang.t('퇴근 시간이다! 오늘도 수고했어 🎒', 'Time to clock out! Great work today 🎒', '下班时间到啦！今天也辛苦了 🎒'),
          mood: PetMood.waving);
      return true;
    }
    return false;
  }

  void scold() {
    if (scoldBlock != null) return;
    _careAt = DateTime.now();
    whine = 0;
    _quietUntil = DateTime.now().add(const Duration(minutes: 30));
    happiness = (happiness - 3).clamp(0, 100);
    _ownerAt = DateTime.now();
    _act('scolded');
    cues.play('sad', force: true);
    _say(Lang.t('힝… 알았어. 조용히 있을게… 😢', 'Aww… okay. I\'ll be quiet… 😢', '唔…好吧，我会安静的… 😢'),
        mood: PetMood.sad);
    _emote('sulky');
    _save();
  }

  /// About every few minutes of quiet: wander a bit, jump, wave or
  /// stretch so the pet never looks frozen.
  void _idleBehaviour() {
    if (!roam || sleeping || thinking || listening || panelOpen) return;
    if (alarmText != null || bubbleText != null) return;
    if (DateTime.now().difference(_ownerAt).inMinutes < 2) return;
    final r = Random();
    final now = DateTime.now();
    if (_dailyMoment(now)) return;
    if (r.nextDouble() > 0.3) return;
    final ignored = now.difference(_ownerAt).inMinutes;
    // Ignored for a while: whine to play, more and more insistent.
    if (now.isAfter(_quietUntil) &&
        ignored >= 10 + whine * 5 &&
        (happiness < 80 || r.nextDouble() < 0.4)) {
      _whine();
      return;
    }
    switch (r.nextInt(12)) {
      case 8: // morning coffee, otherwise water (more often when hot)
        final hot = weather.current?.isHot ?? false;
        if (now.hour >= 7 && now.hour < 10) {
          _act('coffee');
          _say(Lang.t('모닝 커피 한 잔 ☕', 'Morning coffee ☕', '早晨咖啡一杯 ☕'), mood: PetMood.happy);
        } else {
          _act('water');
          if (hot) {
            _say(Lang.t('더울 땐 물 많이! 주인님도 마셔 💧', 'Stay hydrated! You too 💧', '天热要多喝水！主人也要喝哦 💧'),
                mood: PetMood.happy);
          }
        }
        return;
      case 9:
        _act('music');
        return;
      case 10:
        _act('reading');
        return;
      case 11:
        _act('stretch');
        return;
      case 5: // reading a comic book by itself
        _act('comic');
        _say(Lang.t('헤헤, 만화책 재밌다 📖', 'Hehe, this comic is fun 📖', '嘿嘿，这本漫画真好看 📖'),
            mood: PetMood.happy);
        return;
      case 6:
      case 7:
        _act('yawn');
        if (energy < 50) cues.play('sleepy');
        return;
      case 0:
      case 1:
        wanderDx = (r.nextBool() ? 1 : -1) * (60 + r.nextInt(120)).toDouble();
        wanderSignal++;
        hopSignal++;
      case 2:
        _act('jump');
      case 3:
        _act('wave');
      default:
        hopSignal++;
    }
  }
}
