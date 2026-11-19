part of 'pet_brain.dart';

/// Native macOS extras of the sold editions (1.2.0): the menu bar status
/// item (macos/Runner/MainFlutterWindow.swift, StatusBarChannel) and Notification
/// Center notices (NotifyChannel). Both are driven from here over MethodChannels.
///   hoodimong/notify   (Notification Center, UNUserNotificationCenter; no entitlement needed)
///     Dart -> Swift  requestAuth -> bool, status -> 'authorized'|'denied'|'notDetermined',
///                    post {id, title, body}
///   hoodimong/statusbar
///     Dart -> Swift  update {enabled, face, header, hunger, energy, feed, feedEnabled,
///                            sleep, alarm, show, quit}
///     Swift -> Dart  action 'feed' | 'sleep' | 'alarm' | 'show'
extension PetBrainNative on PetBrain {
  static const _bar = MethodChannel('hoodimong/statusbar');

  /// The mood as one face for the menu bar.
  static String statusFace(PetMood mood, {bool sleeping = false}) {
    if (sleeping) return '😴';
    return switch (mood) {
      PetMood.idle || PetMood.talking => '🙂',
      PetMood.happy || PetMood.waving => '😊',
      PetMood.celebrating => '🥳',
      PetMood.sad => '😢',
      PetMood.bored => '😑',
      PetMood.sleepy => '😴',
      PetMood.thinking => '🤔',
      PetMood.eating => '😋',
      PetMood.sick => '🤒',
      PetMood.rain => '☔️',
      PetMood.hot => '🥵',
    };
  }

  /// What the menu bar shows and says (also used by tests).
  Map<String, Object> statusBarPayload() {
    final block = feedBlock;
    return {
      'enabled': Ed.isSold && menuBarEnabled,
      'face': statusFace(currentMood(), sleeping: sleeping),
      'header': '${Character.current.displayName} · ${stats.needText()}',
      'hunger': '🍪 ${Lang.t('배부름', 'Fullness', '饱腹')} ${hunger.round()}%',
      'energy': '⚡ ${Lang.t('기운', 'Energy', '体力')} ${energy.round()}%',
      'feed': Lang.t('밥 주기', 'Feed', '喂食'),
      'feedEnabled': block == null,
      // Waking is done by shaking the pet, never by a button, so the item only shows the state while asleep.
      'sleep': sleeping ? Lang.t('자는 중 (흔들면 깨요)', 'Sleeping (shake to wake)', '睡觉中（摇一摇叫醒）') : Lang.t('재우기', 'Put to sleep', '哄睡'),
      'sleepEnabled': !sleeping,
      'alarm': Lang.t('새 알람…', 'New alarm…', '新闹钟…'),
      'show': Lang.t('후디메이트 보이기', 'Show Hoodimate', '显示 Hoodimate'),
      'quit': Lang.t('후디메이트 종료', 'Quit Hoodimate', '退出 Hoodimate'),
    };
  }

  Future<void> _initStatusBar() async {
    if (!Ed.isSold) return;
    _bar.setMethodCallHandler((call) async {
      if (call.method == 'action') statusBarAction('${call.arguments}');
      return null;
    });
    addListener(pushStatusBar);
    pushStatusBar();
  }

  /// Sends the menu bar state when something visible changed.
  void pushStatusBar() {
    if (!Ed.isSold || demo) return;
    final p = statusBarPayload();
    final sig = jsonEncode(p);
    if (sig == _statusSig) return;
    _statusSig = sig;
    _bar.invokeMethod('update', p).catchError((_) {}); // tests and older hosts have no status bar
  }

  /// A menu bar item was chosen.
  void statusBarAction(String action) {
    switch (action) {
      case 'feed':
        final block = feedBlock;
        if (block != null) {
          _say(block, mood: PetMood.idle);
        } else {
          feed();
        }
      case 'sleep':
        if (!sleeping) toggleSleep();
      case 'alarm':
        openTalk?.call();
        _say(
            Lang.t('몇 분 뒤에 알려 줄까? 예: "10분 뒤에 라면 알려줘"', 'Tell me when, e.g. "remind me in 10 minutes to check the oven"',
                '想几分钟后提醒？例如：“10分钟后提醒我看烤箱”'),
            mood: PetMood.thinking);
      case 'show':
        showPet?.call();
    }
    _notify();
  }

  void setMenuBar(bool on) {
    menuBarEnabled = on;
    _notify();
    _save();
    pushStatusBar();
  }

  // ---------- Notification Center (hungry, alarm, bedtime) ----------

  static const _notice = MethodChannel('hoodimong/notify');

  /// Hungry notice: once when the pet drops below the "hungry" line while
  /// awake; re-armed when it has eaten (hunger back above [rearmAt]).
  static const hungryAt = 25.0, rearmAt = 40.0;
  static bool shouldNoticeHungry({required bool alreadyNoticed, required double hunger, required bool sleeping}) =>
      !alreadyNoticed && !sleeping && hunger < hungryAt;

  void _noticeHunger() {
    if (hunger >= rearmAt) _hungryNoticed = false;
    if (!shouldNoticeHungry(alreadyNoticed: _hungryNoticed, hunger: hunger, sleeping: sleeping)) return;
    _hungryNoticed = true;
    final n = Character.current.displayName;
    postNotice('hungry', Lang.t('$n: 배고파요 🍪', '$n is hungry 🍪', '$n 饿了 🍪'),
        Lang.t('밥 먹을 시간이에요. 후디메이트를 열어 밥을 주세요.', 'Time for a snack. Open Hoodimate to feed it.', '该吃东西啦，打开 Hoodimate 喂喂它吧。'));
  }

  void _noticeAlarm(String text) {
    postNotice('alarm', Lang.t('⏰ 알람이에요', '⏰ Alarm', '⏰ 闹钟'), text);
  }

  void _noticeBedtime() {
    final n = Character.current.displayName;
    postNotice('bedtime', Lang.t('$n: 잘 시간이에요 🌙', "$n: it's bedtime 🌙", '$n：该睡觉了 🌙'),
        Lang.t('밤이 깊어서 잠들었어요. 내일 아침에 일어나요.', 'It is late, so it went to sleep. It wakes up in the morning.', '夜深了，它睡着了，明早会醒来。'));
  }

  /// Posts to Notification Center when the owner turned notices on.
  Future<void> postNotice(String id, String title, String body) async {
    if (!notifyEnabled) return;
    try {
      await _notice.invokeMethod('post', {'id': id, 'title': title, 'body': body});
    } catch (_) {} // tests and older hosts have no notification side
  }

  /// Settings switch. Turning it on is the only moment macOS is asked for
  /// permission; if it is refused the switch stays off and [notifyDenied]
  /// tells the panel to point at System Settings.
  Future<void> setNotifications(bool on) async {
    if (on) {
      var ok = false;
      try {
        ok = (await _notice.invokeMethod<bool>('requestAuth')) ?? false;
      } catch (_) {}
      notifyDenied = !ok;
      notifyEnabled = ok;
    } else {
      notifyEnabled = false;
      notifyDenied = false;
    }
    _notify();
    await _save();
  }
}
