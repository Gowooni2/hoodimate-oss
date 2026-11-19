import '../edition.dart';
import 'profile.dart';

/// First-run walkthrough of the sold editions (App Review 4.3(a): the
/// pet-care identity has to be obvious on the very first launch).
///
/// Page 0 picks one of the five Hoodies; the next cards say what to do with
/// the pet (feed, play, sleep) and the last one tells about Hoodibot.
/// "Done" is kept per Mac in pet_state.json (`onboardingDone`).
class Onboarding {
  /// Whether the walkthrough should be on screen now.
  static bool needed({
    required Edition edition,
    required bool done,
    bool demo = false,
    bool film = false,
  }) {
    if (demo || film || done) return false;
    return edition == Edition.store || edition == Edition.direct;
  }

  /// The saved flag from pet_state.json. A Mac that already has a state
  /// file from an earlier version (no key yet) is an existing owner: it
  /// isn't walked through again. No file at all means a fresh install.
  static bool savedDone(Map<String, dynamic>? state) {
    if (state == null) return false;
    final v = state['onboardingDone'];
    return v is bool ? v : true;
  }

  static const careCards = ['feed', 'play', 'sleep', 'hoodibot'];

  static String emoji(String card) => switch (card) {
        'feed' => '🍪',
        'play' => '🧸',
        'sleep' => '🌙',
        _ => '🤝',
      };

  static String title(String card) => switch (card) {
        'feed' => Lang.t('밥 주기', 'Feed', '喂食'),
        'play' => Lang.t('놀아 주기', 'Play', '玩耍'),
        'sleep' => Lang.t('재우기', 'Sleep', '睡觉'),
        _ => Lang.t('후디봇 만나기', 'Meet Hoodibot', '见见 Hoodibot'),
      };

  /// One line each (the last one is the Hoodibot card).
  static String line(String card) => switch (card) {
        'feed' => Lang.t('배고파 보이면 밥을 주세요. 배가 차면 기분이 좋아져요.',
            'Feed it when it looks hungry. A full tummy makes it happy.', '看它饿了就喂点吃的，吃饱了心情会变好。'),
        'play' => Lang.t('같이 놀면 신나 해요. 대신 조금 지쳐요.',
            'Playing cheers it up, though it gets a little tired.', '陪它玩它会很开心，不过也会有点累。'),
        'sleep' => Lang.t('졸려 하면 재워 주세요. 밤 10시가 넘으면 알아서 자요.',
            "Put it to bed when it's sleepy. After 10 PM it dozes off on its own.", '它困了就哄它睡觉。晚上 10 点以后它会自己睡着。'),
        _ => Lang.t('같은 맥에 후디봇이 있으면 둘이 만나서 인사하고 서로 놀러 가요.',
            'If Hoodibot lives on this Mac too, the two of them meet, say hi and visit each other.',
            '如果这台 Mac 上也有 Hoodibot，它们会碰面打招呼，还会互相串门。'),
      };

  static String get pickTitle => Lang.t('함께 지낼 친구를 골라 주세요', 'Pick who you will care for', '选一位要照顾的朋友');
  static String get pickHint =>
      Lang.t('나중에 설정에서 언제든 바꿀 수 있어요.', 'You can change this later in Settings.', '之后可以随时在设置里更换。');
  static String get skip => Lang.t('건너뛰기', 'Skip', '跳过');
  static String get next => Lang.t('다음', 'Next', '下一步');
  static String get start => Lang.t('시작하기', "Let's go", '开始吧');
}
