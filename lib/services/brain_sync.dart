part of 'pet_brain.dart';

/// Sync between Macs.
extension PetBrainSync on PetBrain {
  // ---------- sync between Macs ----------


  /// Settings: pick the shared folder, then sync right away.
  Future<void> pickSyncFolder() async {
    if (await sync.pick() != null) await syncNow();
    _notify();
  }

  /// Saves everything, merges with the shared folder and reloads whatever
  /// the other Mac changed. Skipped mid-conversation or mid-alarm.
  Future<void> syncNow() async {
    if (!sync.ready || syncing || demo || thinking || listening || alarmText != null) return;
    syncing = true;
    _notify();
    try {
      // Profile, reminders and coins save themselves when edited; saving
      // them here would make them look newer than the other Mac's edit.
      await memory.save();
      await _save();
      final changed = await sync.run(await getApplicationSupportDirectory());
      if (changed) {
        await memory.load();
        await profile.load();
        applyProfile();
        await reminders.load();
        await market.load();
        await _load();
      }
    } finally {
      syncing = false;
      _notify();
    }
  }



  /// Owner interaction (click, panel, chat). It no longer wakes a sleeping
  /// pet: only full energy, hunger or a shaken mouse do (see [wakeUp]).
  bool _wakeForOwner() {
    _ownerAt = DateTime.now();
    whine = 0; // attention is all it wanted
    return false;
  }

  /// Wakes the pet. [why]: 'rested' (energy full), 'hungry', 'shake'.
  void wakeUp(String why) {
    if (!sleeping) return;
    sleeping = false;
    _ownerAt = DateTime.now();
    _act(why == 'shake' ? 'scared' : 'stretch');
    _say(
        switch (why) {
          'hungry' => Lang.t('배고파서 깼어… 밥 줘 🍪', 'Woke up hungry… food please 🍪', '饿醒了…给我吃饭 🍪'),
          'menu' => Lang.t('일어났어~ 🌤️', 'Up and about~ 🌤️', '起床啦~ 🌤️'),
          'shake' => Lang.t('으앗? 뭐야 뭐야! 깼잖아 👀', 'Huh?! What, what? You woke me 👀', '哎？怎么了怎么了！我醒了 👀'),
          _ => Lang.t('푹 잤다! 기운이 꽉 찼어 ☀️', 'Slept well! Fully charged ☀️', '睡饱啦！精力满满 ☀️'),
        },
        mood: why == 'hungry' ? PetMood.sad : PetMood.waving);
    _emote(switch (why) { 'hungry' => 'hungry', 'shake' => 'scared', _ => 'morning' });
    cues.play(why == 'hungry' ? 'eating' : 'greeting', force: true);
    _save();
    _notify();
  }

  /// The mouse was shaken near the sleeping pet.
  void wakeByShake() => wakeUp('shake');

  /// Sleep button: goes to sleep any time of day. Waking up is not a
  /// button: full energy, hunger or a shaken mouse wake it (owner's rule).
  void toggleSleep() {
    if (sleeping) return;
    _careAt = DateTime.now();
    sleeping = true;
    _act('yawn');
    _say(Lang.t('잘게... 💤', 'Going to sleep... 💤', '我去睡觉了... 💤'), mood: PetMood.sleepy);
    _emote('night');
    cues.play('sleepy', force: true);
    _notify();
    _save();
  }

  void togglePanel() {
    _wakeForOwner();
    panelOpen = !panelOpen;
    _notify();
  }

  /// Resize the panel; [save] once the drag ends.
  void setPanelSize(double w, double h, {bool save = false}) {
    panelW = w.clamp(PetBrain.panelMin.width, PetBrain.panelMax.width);
    panelH = h.clamp(PetBrain.panelMin.height, PetBrain.panelMax.height);
    _notify();
    if (save) _save();
  }

  void setPanelTheme(String id) {
    panelTheme = id;
    _notify();
    _save();
  }

  /// Chat text: cute font or the system one, and its size.
  void setChatFont({bool? cute, double? scale}) {
    if (cute != null) CuteFont.cute = cute;
    if (scale != null) CuteFont.scale = scale.clamp(0.85, 1.5);
    _notify();
    _save();
  }

  void setReplyStickers(bool on) {
    replyStickers = on;
    _notify();
    _save();
  }

  void setPetScale(double v) {
    petScale = v.clamp(0.6, 1.6);
    _notify();
    _save();
  }

  void setCuesEnabled(bool v) {
    cues.enabled = v;
    if (!v) cues.stop();
    _notify();
    _save();
  }

  void setMacFallback(bool v) {
    cues.macFallback = v;
    _notify();
    _save();
  }
}
