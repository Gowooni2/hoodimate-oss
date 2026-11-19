import 'pet_state.dart';
import 'profile.dart';

/// A KakaoTalk-style animated emoticon: one of the character's clips plus a
/// short caption. Drawn with the current character pack, so the same
/// emoticon is Mongsil, Sobok, ... depending on who the pet is.
class Emoticon {
  final String id;

  /// Clip key in the character pack (act_eat, sleepy, ...).
  final String clip;
  final String ko, en, zh;

  /// Mood whose still sprite stands in when the clip isn't rendered yet.
  final PetMood still;
  const Emoticon(this.id, this.clip, this.ko, this.en, this.zh, [this.still = PetMood.happy]);

  String get caption => Lang.t(ko, en, zh);
}

/// A set of emoticons. The basic pack is free; others are sold directly
/// (license key) later, see [EmoticonShop].
class EmoticonPack {
  final String id;
  final String ko, en, zh;
  final List<Emoticon> items;
  final bool free;
  const EmoticonPack(this.id, this.ko, this.en, this.zh, this.items, {this.free = false});

  String get name => Lang.t(ko, en, zh);
}

class Emoticons {
  static const basic = EmoticonPack('basic', '기본 감정팩', 'Basic feelings', '基础表情包', [
    Emoticon('hello', 'act_wave2', '안녕!', 'Hi!', '你好！', PetMood.waving),
    Emoticon('yummy', 'act_eat', '냠냠!', 'Yum!', '好吃！', PetMood.eating),
    Emoticon('yay', 'act_jump2', '신난다!', 'Yay!', '耶！', PetMood.happy),
    Emoticon('love', 'act_pet', '좋아~♥', 'Love it~♥', '喜欢~♥', PetMood.happy),
    Emoticon('tickle', 'act_tickle', '간지러워!', 'That tickles!', '好痒！', PetMood.happy),
    Emoticon('thanks', 'act_thanks', '고마워', 'Thank you', '谢谢', PetMood.happy),
    Emoticon('sleepy', 'act_yawn', '졸려…', 'Sleepy…', '好困…', PetMood.sleepy),
    Emoticon('night', 'sleepy', '잘 자…💤', 'Good night…💤', '晚安…💤', PetMood.sleepy),
    Emoticon('morning', 'act_stretch', '잘 잤다!', 'Good morning!', '早安！', PetMood.waving),
    Emoticon('hungry', 'act_sigh', '배고파…', 'Hungry…', '饿了…', PetMood.sad),
    Emoticon('playwithme', 'act_whine', '놀아줘~', 'Play with me~', '陪我玩~', PetMood.bored),
    Emoticon('sulky', 'act_scolded', '힝…', 'Hmph…', '哼…', PetMood.sad),
    Emoticon('sad', 'act_gloomy2', '속상해…', 'So sad…', '好难过…', PetMood.sad),
    Emoticon('best', 'act_cheer2', '최고야!', 'The best!', '最棒了！', PetMood.celebrating),
    Emoticon('hot', 'act_fan2', '더워…', 'So hot…', '好热…', PetMood.hot),
    Emoticon('cold', 'act_shiver2', '추워…', 'Brr…', '好冷…', PetMood.sad),
    Emoticon('scared', 'act_scared2', '무서워!', 'Eek!', '好怕！', PetMood.sad),
    Emoticon('hmm', 'act_think', '음…', 'Hmm…', '嗯…', PetMood.thinking),
    Emoticon('listening', 'act_listen', '듣고 있어', 'I\'m listening', '我在听', PetMood.talking),
    Emoticon('working', 'act_work', '일하는 중', 'On it', '工作中', PetMood.thinking),
    Emoticon('done', 'act_done', '완료!', 'Done!', '搞定！', PetMood.happy),
    Emoticon('oops', 'act_failed', '앗 실패…', 'Oops…', '哎呀…', PetMood.sad),
    Emoticon('wakeup', 'act_alarm', '일어나!!', 'Wake up!!', '起床啦！！', PetMood.waving),
    Emoticon('coffee', 'act_coffee', '커피 타임 ☕', 'Coffee time ☕', '咖啡时间 ☕', PetMood.happy),
    Emoticon('umbrella', 'act_umbrella', '우산 챙겨!', 'Umbrella!', '记得带伞！', PetMood.rain),
  ], free: true);

  /// Packs the owner has (the basic pack now; bought packs later).
  static List<EmoticonPack> get owned => const [basic];

  static Emoticon? byId(String? id) {
    if (id == null) return null;
    for (final p in owned) {
      for (final e in p.items) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  /// Emoticon for an AI reply's mood (null = plain text reply).
  static String? forMood(PetMood m) => switch (m) {
        PetMood.happy => 'yay',
        PetMood.celebrating => 'best',
        PetMood.sad => 'sad',
        PetMood.sleepy => 'sleepy',
        PetMood.eating => 'yummy',
        PetMood.waving => 'hello',
        PetMood.hot => 'hot',
        PetMood.rain => 'umbrella',
        PetMood.bored => 'playwithme',
        _ => null,
      };

  static RegExp _re(String s) => RegExp(s, caseSensitive: false);

  /// Topic words (ko / en / zh) in the reply or the owner's question that
  /// call for a particular emoticon. First match wins. English words keep
  /// \b so "great" isn't "eat" and "display" isn't "play".
  static final _topics = <(RegExp, String)>[
    (_re(r'고마|감사|\bthank|谢'), 'thanks'),
    (_re(r'미안|죄송|실패|못 찾|\bsorry\b|\boops\b|\bcouldn.t\b|\bcan.t\b|抱歉|对不起|失败'), 'oops'),
    (_re(r'알람|알림|맞춰 ?놨|맞췄|완료|다 됐|\breminder|\balarm|\bdone\b|\ball set\b|提醒|闹钟|搞定|完成'), 'done'),
    // "준비가/준비와" must not count as rain: 비 only after a non-Hangul char.
    (_re(r'우산|(?<![가-힣])비(가|\s?와|\s?온|\s?오)|빗소리|빗방울|장마|소나기|\brain(y|ing|s)?\b|\bumbrella|\bdrizzl|下雨|雨伞|带伞|雨天'), 'umbrella'),
    (_re(r'우중충|축축|꿀꿀|\bgloomy\b|\bdamp\b|\bdreary\b|阴沉|湿漉漉'), 'sulky'),
    (_re(r'커피|라떼|\bcoffee\b|\blatte\b|咖啡'), 'coffee'),
    (_re(r'잘 ?자|\bgood ?night\b|晚安'), 'night'),
    (_re(r'좋은 아침|굿모닝|\bgood morning\b|早安|早上好'), 'morning'),
    (_re(r'배고|먹|간식|밥|맛있|\bsnacks?\b|\bfood\b|\beat(ing)?\b|\bhungry\b|\byum|\blunch\b|\bdinner\b|吃|饿|零食'), 'yummy'),
    (_re(r'졸려|졸리|피곤|낮잠|\bnaps?\b|\bsleep|\btired\b|困|睡'), 'sleepy'),
    (_re(r'더워|덥|\bhot\b|\bheat\b|热'), 'hot'),
    (_re(r'추워|춥|\bcold\b|\bchilly\b|\bfreezing\b|冷'), 'cold'),
    (_re(r'무서|\bscar(y|ed)\b|\bafraid\b|怕'), 'scared'),
    (_re(r'슬퍼|속상|우울|힘들|\bsad\b|\bupset\b|\blonely\b|难过|伤心'), 'sad'),
    (_re(r'놀자|놀아|게임|\bplay(ing)?\b|\bgames?\b|玩'), 'playwithme'),
    (_re(r'최고|대단|축하|멋져|\bawesome\b|\bamazing\b|\bcongrat|\bgreat job\b|\bwell done\b|最棒|厉害|恭喜'), 'best'),
    (_re(r'사랑|좋아해|\blove\b|♥|❤|爱|喜欢'), 'love'),
    (_re(r'안녕|반가|\bhello\b|^hi\b|你好|嗨'), 'hello'),
    (_re(r'글쎄|생각해|고민|\bhmm+\b|\blet me think\b|嗯|想想'), 'hmm'),
    (_re(r'찾아볼|검색|알아볼|\blooking (it )?up\b|\bsearching\b|查一下|搜索'), 'working'),
  ];

  /// Several emoticons that suit each mood, so replies don't all look alike.
  static const _moodPool = <PetMood, List<String>>{
    PetMood.happy: ['yay', 'love', 'best', 'tickle', 'hello'],
    PetMood.celebrating: ['best', 'yay', 'done'],
    PetMood.sad: ['sad', 'sulky', 'oops'],
    PetMood.sleepy: ['sleepy', 'night'],
    PetMood.eating: ['yummy', 'hungry'],
    PetMood.waving: ['hello', 'morning'],
    PetMood.hot: ['hot'],
    PetMood.rain: ['umbrella', 'sulky', 'yay'],
    PetMood.bored: ['playwithme', 'sulky'],
    PetMood.thinking: ['hmm', 'working'],
    PetMood.talking: ['listening', 'hmm', 'yay'],
  };

  /// Emoticon for an AI reply: one that fits what was said (the reply
  /// first, then the owner's question), else one of the mood's set that
  /// differs from the [last] one shown. [pick] chooses an index (tests pass
  /// a fixed one).
  static String? forReply(String reply, PetMood mood,
      {String question = '', String? last, int Function(int n)? pick}) {
    for (final text in [reply, question]) {
      for (final (re, id) in _topics) {
        if (re.hasMatch(text)) return id;
      }
    }
    final pool = _moodPool[mood];
    if (pool == null) return forMood(mood);
    final fresh = pool.where((id) => id != last).toList();
    final from = fresh.isEmpty ? pool : fresh;
    return from[(pick ?? _rnd)(from.length)];
  }

  static int _rnd(int n) => DateTime.now().microsecond % n;

  /// What the pet sends back when the owner sends [id].
  static String replyTo(String id) => switch (id) {
        'hello' || 'morning' => 'hello',
        'love' || 'thanks' || 'sad' || 'sulky' || 'oops' => 'love',
        'tickle' => 'tickle',
        'sleepy' || 'night' => 'night',
        'hot' => 'hot',
        'cold' || 'scared' => 'scared',
        'best' || 'done' || 'yay' => 'best',
        'hungry' || 'yummy' => 'yummy',
        'coffee' => 'coffee',
        'wakeup' => 'scared',
        _ => 'yay',
      };
}
