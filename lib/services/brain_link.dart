part of 'pet_brain.dart';

/// Meeting Hoodibot on the same Mac (PetLink, interaction protocol v1).
extension PetBrainLink on PetBrain {
  String get _linkState => sleeping ? 'sleep' : (alarmText != null ? 'alarm' : 'idle');

  Future<void> _linkTick() async {
    if (!link.ready || demo) return;
    final feet = await petFeet?.call();
    if (feet == null) return;
    final state = _linkState;
    link.publish(
      character: Character.current.id,
      x: feet.x,
      y: feet.y,
      height: feet.h,
      state: state,
      emotion: currentMood().name,
    );
    final other = link.friendPresence();
    if (other != null) {
      final mine = PetPresence(
          app: PetLink.me, character: Character.current.id, x: feet.x, y: feet.y,
          height: feet.h, state: state, emotion: '', ts: 0);
      if (link.shouldGreet(mine, other)) {
        if (other.state == 'clean') {
          // Hoodibot is busy cleaning: cheer it on instead of a plain hello.
          _cheerCleaning();
        } else {
          _say(Lang.t('후디봇 안녕!', 'Hi, Hoodibot!', '嗨，Hoodibot！'), mood: PetMood.waving, sticker: 'hello');
          link.send('hoodimong/hello');
        }
        _notify();
      }
      if (link.shouldVisit(mine, other)) {
        _say(Lang.t('후디봇네 집에 놀러 왔어! 똑똑~', "Visiting Hoodibot's house! Knock knock~", '来 Hoodibot 家玩啦！咚咚~'),
            mood: PetMood.waving, sticker: 'hello');
        link.send('hoodimong/visit');
        _notify();
      }
      if (alarmText == null && !sleeping && link.shouldJoinAlarm(other)) {
        _say(Lang.t('후디봇 알람이 울려요!', "Hoodibot's alarm is ringing!", 'Hoodibot 的闹钟响了！'),
            mood: PetMood.waving, sticker: 'wakeup');
        _notify();
      }
    }
    final s = link.takeSignal();
    if (s != null) _onFriendSignal(s);
  }

  /// Cheer for Hoodibot's cleaning; its energy refills when the cheer lands.
  void _cheerCleaning() {
    _say(Lang.t('청소 화이팅! 영차영차!', 'Go go, clean team! Heave-ho!', '打扫加油！嘿咻嘿咻！'),
        mood: PetMood.celebrating, sticker: 'best');
    link.send('hoodimong/cheer', data: {'why': 'cleaning'});
  }

  void _onFriendSignal(PetSignal s) {
    if (sleeping && s.type != 'hoodimong/alarm') return; // a sleeping pet only hears alarms
    switch (s.type) {
      case 'hoodimong/hello':
        link.noteHello();
        _say(Lang.t('후디봇이 인사했어! 안녕~♥', 'Hoodibot says hi! Hi~♥', 'Hoodibot 打招呼啦！你好~♥'),
            mood: PetMood.happy, sticker: 'love');
      case 'hoodimong/play':
        _say(Lang.t('후디봇이랑 놀 거야!', "Playing with Hoodibot!", '要和 Hoodibot 一起玩！'),
            mood: PetMood.happy, sticker: 'yay');
      case 'hoodimong/visit':
        _say(Lang.t('후디봇네 집에 놀러 가는 중~', "Visiting Hoodibot's house~", '去 Hoodibot 家玩~'),
            mood: PetMood.waving, sticker: 'hello');
      case 'hoodimong/cheer':
        if (s.data['why'] == 'cleaning') {
          link.noteHello(); // this was its greeting; cheer back once
          _cheerCleaning();
        } else {
          _say(Lang.t('힘내! 최고야!', 'You got this!', '加油！最棒了！'), mood: PetMood.celebrating, sticker: 'best');
        }
      case 'hoodimong/alarm':
        if (alarmText != null) return;
        final t = '${s.data['text'] ?? ''}'.trim();
        _say(t.isEmpty
                ? Lang.t('후디봇 알람이 울려요!', "Hoodibot's alarm is ringing!", 'Hoodibot 的闹钟响了！')
                : Lang.t('후디봇 알람: $t', "Hoodibot's alarm: $t", 'Hoodibot 的闹钟：$t'),
            mood: PetMood.waving, sticker: 'wakeup');
      default:
        return;
    }
    _notify();
  }
}
