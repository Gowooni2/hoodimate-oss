import 'pet_state.dart';
import 'profile.dart';

/// Pure care rules, separate from PetBrain so they are easy to test.
class CareStats {
  final double hunger, happiness, health, energy;
  final bool sleeping;

  /// 22:00-07:00. Sleepy poses only show at night; by day a tired pet
  /// just looks bored (the owner asked for no daytime sleeping).
  final bool night;
  const CareStats(
      {required this.hunger,
      required this.happiness,
      required this.health,
      required this.energy,
      required this.sleeping,
      this.night = false});

  static bool isNight(DateTime t) => t.hour >= 22 || t.hour < 7;

  /// Needs first (so the owner can see what to do); null = no urgent need,
  /// the caller then falls back to weather/market moods.
  PetMood? needMood() {
    if (health < 30) return PetMood.sick;
    if (sleeping) return PetMood.sleepy;
    if (hunger < 25) return PetMood.sad;
    if (energy < 20) return night ? PetMood.sleepy : PetMood.bored;
    if (happiness < 30) return PetMood.bored;
    return null;
  }

  /// One-line status for the care tab: the most urgent need.
  String needText() {
    if (health < 30) {
      return Lang.t('아파요. 약이 필요해요 💊', 'I feel sick. I need medicine 💊', '我不舒服，需要吃药 💊');
    }
    if (sleeping) return Lang.t('쿨쿨 자는 중이에요 💤', 'Zzz… sleeping 💤', '呼呼…睡觉中 💤');
    if (hunger < 25) {
      return Lang.t('배고파요. 밥 주세요 🍪', 'I\'m hungry. Feed me, please 🍪', '我饿了，快喂我吧 🍪');
    }
    if (energy < 20) {
      return night
          ? Lang.t('졸려요. 재워 주세요 💤', 'So sleepy. Put me to bed 💤', '好困呀，让我睡觉吧 💤')
          : Lang.t('지쳤어요. 잠깐 쉬게 해 주세요', 'I\'m tired. Let me rest a bit', '我累了，让我休息一会儿');
    }
    if (happiness < 30) {
      return Lang.t('심심해요. 놀아 주세요 🎮', 'I\'m bored. Play with me 🎮', '好无聊，陪我玩嘛 🎮');
    }
    if (health < 60) {
      return Lang.t('조금 아파요. 약을 줘도 돼요', 'I feel a little sick. Medicine would help', '我有点不舒服，吃点药会好些');
    }
    return Lang.t('기분 좋아요! ✨', 'Feeling great! ✨', '心情超棒！✨');
  }

  // Why a care button is unavailable right now (null = available).
  String? get feedBlock => sleeping
      ? Lang.t('자는 중', 'Sleeping', '睡觉中')
      : (hunger >= 95 ? Lang.t('배불러요', 'Full', '吃饱啦') : null);
  String? get playBlock => sleeping
      ? Lang.t('자는 중', 'Sleeping', '睡觉中')
      : (energy < 15
          ? Lang.t('너무 피곤해요', 'Too tired', '太累了')
          : (hunger < 10 ? Lang.t('배고파서 못 놀아요', 'Too hungry to play', '饿得没力气玩') : null));
  String? get medicineBlock =>
      health >= 60 ? Lang.t('건강해요', 'Healthy', '很健康') : null;
}
