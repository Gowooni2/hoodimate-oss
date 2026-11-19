import 'dart:math';

import '../services/market_service.dart';
import '../services/weather_service.dart';
import 'profile.dart';

/// What the pet says and does when the weather or the owner's portfolio
/// does something notable. Pure functions, so they are unit-tested.
///
/// Actions name one-shot clips `assets/anim/act_<action>_NNNN.png`
/// (rendered by tools/comfy_clip.py). A missing clip is skipped quietly,
/// so lines work before the animation is installed.
class Reactions {
  // ---------- weather ----------

  /// {t} = current °F, {f} = feels-like °F, {lo}/{hi} = today's range.
  /// A getter so the language is picked at call time.
  static Map<String, List<String>> get weatherLines => {
        'thunder': [
          Lang.t('꺄! 천둥 쳤어… 무서워…', 'Eek! Thunder… I\'m scared…', '呀！打雷了…好害怕…'),
          Lang.t('우르릉… 주인님 옆에 있을래', 'Rumble rumble… I\'ll stay right next to you', '轰隆隆…我要待在主人身边'),
        ],
        'snow': [
          Lang.t('우와, 눈이다! ❄️ 지금 {t}°F야, 따뜻하게 입어!',
              'Wow, snow! ❄️ It\'s {t}°F, bundle up!', '哇，下雪啦！❄️ 现在 {t}°F，要穿暖和点！'),
          Lang.t('눈 온다! 미끄러우니까 조심해~', 'It\'s snowing! Careful, it\'s slippery~', '下雪啦！路滑，小心点~'),
        ],
        'rain': [
          Lang.t('비 온다! 우산 꼭 챙겨!', 'It\'s raining! Don\'t forget your umbrella!', '下雨啦！记得带伞哦！'),
          Lang.t('톡톡… 빗소리 좋다아~', 'Pitter patter… I love the sound of rain~', '滴答滴答…好喜欢雨声呀~'),
          Lang.t('으, 축축해… {t}°F인데 비까지 와',
              'Ugh, so damp… {t}°F and raining too', '呜，湿漉漉的…{t}°F 还下着雨'),
          // a rainy day can feel gloomy, or fun (owner, 2026-10-12)
          Lang.t('비 와서 하늘이 우중충하네… 오늘은 꿀꿀해',
              'Rainy and gloomy out there… a little meh today', '下雨天阴沉沉的…今天有点闷闷的'),
          Lang.t('와, 비다! 오랜만이라 신난다~ 첨벙첨벙!',
              'Ooh, rain! Haven\'t seen it in a while, splish splash~', '哇，下雨啦！好久没下了，好开心~啪嗒啪嗒！'),
          Lang.t('외출할 때 우산 잊지 마! 나는 노란 우산 챙겼어',
              'Going out? Don\'t forget your umbrella! I\'ve got my yellow one', '出门别忘了带伞！我带好我的小黄伞啦'),
        ],
        'drizzle': [
          Lang.t('보슬비가 와. 우산 챙겨 가!', 'A little drizzle. Take an umbrella!', '下小雨啦，带把伞去吧！'),
        ],
        'hot': [
          Lang.t('헥헥… 지금 {t}°F래! 녹겠다아…', 'Phew… it\'s {t}°F! I\'m melting…', '呼哧呼哧…现在 {t}°F！我要融化了…'),
          Lang.t('땀 뻘뻘… 체감 {f}°F야. 주인님도 물 많이 마셔!',
              'So sweaty… feels like {f}°F. Drink lots of water!', '汗流浃背…体感 {f}°F。主人也要多喝水！'),
          Lang.t('부채질 좀 해줘~ {t}°F는 너무해', 'Fan me, please~ {t}°F is too much', '快给我扇扇风~{t}°F 也太热了吧'),
          Lang.t('오늘 최고 {hi}°F까지 올라간대… 에어컨 켜자!',
              'It\'ll reach {hi}°F today… let\'s turn on the AC!', '今天最高会到 {hi}°F…开空调吧！'),
        ],
        'cold': [
          Lang.t('으슬으슬… {t}°F야, 따뜻하게 입어~', 'Brrr… it\'s {t}°F, bundle up~', '哆嗦哆嗦…{t}°F，穿暖和点~'),
          Lang.t('손 시려… {t}°F래. 핫초코 마시고 싶다',
              'My paws are freezing… {t}°F. I want hot cocoa', '爪爪都冻僵了…{t}°F。好想喝热可可'),
          Lang.t('덜덜… 체감 {f}°F야. 감기 조심해!',
              'Shiver… feels like {f}°F. Don\'t catch a cold!', '瑟瑟发抖…体感 {f}°F。小心别感冒！'),
        ],
        'windy': [
          Lang.t('바람 엄청 분다! 날아갈 것 같아~', 'So windy! I might blow away~', '风好大呀！我要被吹跑啦~'),
        ],
        'lovely': [
          Lang.t('{t}°F, 날씨 진짜 좋다! 잠깐 산책 어때?',
              '{t}°F, such nice weather! How about a short walk?', '{t}°F，天气真好！出去散散步怎么样？'),
          Lang.t('햇살 따뜻해~ {t}°F 딱 좋아!', 'The sun feels warm~ {t}°F is perfect!', '阳光暖洋洋~{t}°F 刚刚好！'),
        ],
        'fog': [
          Lang.t('안개 꼈어. 운전 조심해!', 'It\'s foggy. Drive safe!', '起雾了，开车小心！'),
        ],
      };

  /// Clip played with a weather comment (null = no special clip).
  /// Clip names; PetClips.resolveAction prefers a newer `<name>2` render.
  static const weatherAction = {
    'hot': 'fan', // fanning itself with a paper fan, sweating
    'cold': 'shiver', // red scarf, teeth chattering
    'thunder': 'scared', // paws over the eyes
    'rain': 'umbrella', // yellow umbrella, splashy little steps
    'drizzle': 'umbrella',
    'lovely': 'sunny', // sunglasses grin (falls back to jump)
  };

  static String fill(String line, WeatherInfo w) => line
      .replaceAll('{t}', '${w.tempF}')
      .replaceAll('{f}', '${w.feelsF}')
      .replaceAll('{lo}', '${w.minF}')
      .replaceAll('{hi}', '${w.maxF}');

  static String weatherLine(String key, WeatherInfo w, Random r) {
    final lines = weatherLines[key]!;
    return fill(lines[r.nextInt(lines.length)], w);
  }

  /// Small talk that slips the temperature in (idle chatter).
  static String tempSmallTalk(WeatherInfo w, Random r) {
    final lines = [
      Lang.t('지금 밖은 {t}°F야~', 'It\'s {t}°F outside~', '现在外面 {t}°F 哦~'),
      Lang.t('오늘 {lo}~{hi}°F래. 옷 잘 챙겨 입어!',
          'Today\'s {lo}~{hi}°F. Dress warm!', '今天 {lo}~{hi}°F，记得穿好衣服！'),
      Lang.t('창밖 봤어? 지금 {t}°F, ${w.skyKo}!',
          'Seen outside? {t}°F right now, ${w.skyKo}!', '看窗外了吗？现在 {t}°F，${w.skyKo}！'),
    ];
    return fill(lines[r.nextInt(lines.length)], w);
  }

  // ---------- market ----------

  /// -2 crash, -1 down, 0 flat, 1 up, 2 moon. Uses the coin portfolio's
  /// 24 h change and the watched stock's day change, whichever moved more.
  static int marketTier(MarketInfo m) {
    final coin = m.totalChangePct;
    final stock = m.stock?.changePct ?? 0;
    final move = coin.abs() >= stock.abs() ? coin : stock;
    if (move <= -5) return -2;
    if (move <= -2) return -1;
    if (move >= 5) return 2;
    if (move >= 2) return 1;
    return 0;
  }

  /// Feelings only: the pet never gives investment advice.
  static Map<int, List<String>> get marketLines => {
        -2: [
          Lang.t('오늘 주인님 주식이 바닥이네요… 제 마음도 좋지 못해요 😢',
              'The market hit the floor today… I\'m feeling low too 😢', '今天主人的股票跌到谷底了…我的心情也不好 😢'),
          Lang.t('흑… 시장이 너무해. 나 오늘 우울해…',
              'Sniff… the market is so mean. I\'m gloomy today…', '呜…市场太过分了，我今天好郁闷…'),
          Lang.t('많이 빠졌어… 그래도 주인님 곁에 있을게',
              'It dropped a lot… but I\'ll stay by your side', '跌了好多…不过我会陪在主人身边'),
        ],
        -1: [
          Lang.t('살짝 빠졌네… 나 조금 시무룩해', 'A little dip… I\'m a bit down', '稍微跌了一点…我有点闷闷不乐'),
          Lang.t('오늘은 쉬어가는 날인가 봐. 힘내자!',
              'Maybe it\'s a rest day. Cheer up!', '也许今天是休息日吧，加油！'),
        ],
        1: [
          Lang.t('오! 올랐다~ 기분 좋아!', 'Oh! It\'s up~ I feel great!', '哦！涨啦~心情真好！'),
          Lang.t('주인님 코인이 웃고 있어 😊', 'Your coins are smiling 😊', '主人的币在笑呢 😊'),
        ],
        2: [
          Lang.t('우와아! 오늘 대박이야! 🎉 나 춤출래!',
              'Woooow! Huge day! 🎉 I\'m gonna dance!', '哇啊啊！今天大赚！🎉 我要跳舞啦！'),
          Lang.t('쭉쭉 올랐어! 기분 최고!', 'Up, up, up! Best mood ever!', '一路上涨！心情最棒！'),
        ],
      };

  static const marketAction = {-2: 'gloomy', -1: 'sigh', 1: 'jump', 2: 'cheer'};

  static String marketLine(int tier, MarketInfo m, Random r) {
    final lines = marketLines[tier]!;
    return '${lines[r.nextInt(lines.length)]}\n(${m.headline})';
  }
}
