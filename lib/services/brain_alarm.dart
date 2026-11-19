part of 'pet_brain.dart';

/// Alarms & reminders.
extension PetBrainAlarm on PetBrain {
  // ---------- reminders ----------


  void _checkReminders({bool startup = false}) {
    if (demo) return;
    final now = DateTime.now();
    // Let the greeting and weather briefing finish first.
    if (!startup &&
        (_startedAt == null || now.difference(_startedAt!).inSeconds < 20)) {
      return;
    }
    final due = reminders.takeDue(now);
    if (due.isNotEmpty) {
      _pending.addAll(due);
      reminders.save();
    }
    if (_pending.isEmpty || thinking || listening) return;
    // More than 2 min late = the app was closed or busy.
    bool isLate(Reminder r) => now.difference(r.at) > const Duration(minutes: 2);
    final onTime = _pending.where((r) => !isLate(r)).toList();
    final late = _pending.where(isLate).toList();
    _pending.clear();
    if (late.isNotEmpty) {
      _fireReminder(Lang.t('⏰ 아까 알려주려던 거 있었어! ', '⏰ I missed telling you these earlier! ', '⏰ 刚才想告诉你的事还没说呢！ ') +
          late.map((r) => '${Reminders.clock(r.at)} ${r.text}').join(', '));
    }
    if (onTime.isNotEmpty) {
      _startAlarm(onTime.map((r) => r.text).join(', '),
          Reminders.clock(onTime.first.at));
      memory.addMessage(
          memory.active,
          ChatMessage(
              text: Lang.t('⏰ 주인님, 시간 됐어! ${onTime.map((r) => '"${r.text}"').join(', ')}',
                  '⏰ Time\'s up! ${onTime.map((r) => '"${r.text}"').join(', ')}'),
              fromUser: false,
              at: DateTime.now()));
      memory.save();
    }
  }


  void _startAlarm(String text, String time) {
    alarmText = text;
    _noticeAlarm(text);
    link.send('hoodimong/alarm', to: '*', data: {'text': text}); // Hoodibot rings along
    alarmTime = time;
    sleeping = false; // an alarm wakes the pet up
    _act('wave');
    hopSignal++;
    _alarmRing?.cancel();
    _alarmStop?.cancel();
    SystemSound.play(SystemSoundType.alert);
    _act('alarm'); // rendered clip: hugging the clock, panicking
    var ticks = 0;
    _alarmRing = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      SystemSound.play(SystemSoundType.alert);
      hopSignal++;
      if (++ticks % 2 == 0) _act('alarm'); // replay (~2.6 s clip)
      if (demo) _demoMark('ring');
      _notify();
    });
    _alarmStop = Timer(const Duration(minutes: 1), dismissAlarm);
    _bubbleTimer?.cancel();
    bubbleText = Lang.t('⏰ 따르릉! "$text" 시간이야! 나 좀 잡아줘~',
        '⏰ RING RING! Time for "$text"! Catch me~', '⏰ 叮铃铃！"$text"的时间到啦！快来抓我~');
    bubbleSticker = 'wakeup';
    _notify();
  }

  /// Clicked the running pet.
  void catchAlarm() {
    if (alarmText == null) return;
    final text = alarmText!;
    _stopAlarm();
    _act('jump');
    _say(Lang.t('잡았다! 😆 "$text" 잊지 마!', 'Gotcha! 😆 Don\'t forget "$text"!', '抓到啦！😆 别忘了"$text"哦！'),
        mood: PetMood.happy);
  }

  void _stopAlarm() {
    _alarmRing?.cancel();
    _alarmStop?.cancel();
    alarmText = null;
    alarmTime = null;
  }

  void dismissAlarm() {
    if (alarmText == null) return;
    final text = alarmText!;
    _stopAlarm();
    _say(Lang.t('"$text" 잊지 마! 💪', 'Don\'t forget "$text"! 💪', '别忘了"$text"哦！💪'),
        mood: PetMood.happy);
  }

  void _fireReminder(String text) {
    sleeping = false;
    _act('wave');
    SystemSound.play(SystemSoundType.alert);
    _say(text, mood: PetMood.waving, log: true);
    memory.save();
  }
}
