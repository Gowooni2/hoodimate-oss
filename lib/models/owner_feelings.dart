import 'dart:math';

/// The ten expressions the pet can show for what the owner says.
enum OwnerFeeling { happy, curious, laugh, angry, sulky, sad, surprised, love, thinking, neutral }

/// Result of reading one owner utterance.
class FeelingRead {
  /// Expression that fits the utterance when the pet is not sulking.
  final OwnerFeeling feeling;

  /// 0..1 heuristic (not in the JS source): 0 for neutral, else 0.6 plus
  /// emphasis from "!", repeated ㅋ/ㅠ/ㅎ and long messages.
  final double strength;
  final bool insult, apology, praise;

  /// Raw rule name from emotion.js ('insult_bot', 'sad', 'neutral', ...).
  final String mood;

  /// Owner name for 'tell_name' after the common-noun blacklist, else null.
  final String? name;

  const FeelingRead({
    required this.feeling,
    this.strength = 0,
    this.insult = false,
    this.apology = false,
    this.praise = false,
    this.mood = 'neutral',
    this.name,
  });

  static const neutral = FeelingRead(feeling: OwnerFeeling.neutral);

  @override
  String toString() => 'FeelingRead($mood, $feeling, ${strength.toStringAsFixed(2)})';
}

class _Rule {
  final String mood;
  final List<RegExp> patterns;
  const _Rule(this.mood, this.patterns);
}

/// Korean emotion/intent reader ported from AvatarTalk emotion.js (v2-v4
/// fixes included): negation guard ("안 슬퍼", "바보 아니야"), insult+praise
/// in one sentence cancel to praise, strict name recognition.
/// Korean text uses the ported rules; text without Hangul uses the English
/// rules below (owner, 2026-10-28) with "not / n't / never" as the negation
/// guard; Chinese uses its own rules with 不/没/别 as the guard. Anything else
/// (a lone emoji) reads as neutral.
class OwnerFeelings {
  OwnerFeelings._();

  static final _hangul = RegExp(r'[ㄱ-ㆎ가-힣]');
  static final _praiseRe = RegExp(r'(귀엽|귀여|예뻐|예쁘|최고|멋지|멋있|잘했|잘한다|똑똑|천재|대단|사랑|좋아해)');

  // Checked in order; the first matching rule wins.
  static final List<_Rule> _rules = [
    _Rule('insult_bot', [
      RegExp(r'바보|멍청|병신|등신|저리\s*가|꺼져|최악|한심|시끄러|닥쳐|재수|구제|못생|멋없|빈대|돌머리|하수|쓰레기|재능없|노잼'),
      RegExp(r'(?:(?:너|네가|니가|넌|복실[이아]?|아라야?|모찌야?)\s*(?:진짜|정말|너무|완전)?\s*(?:싫어|별로야))|(?:^(?:싫어|별로야)[.!?~\s]*$)'),
    ]),
    _Rule('apology', [RegExp(r'미안|죄송|잘못했|용서|사과\s*(할게|했다|했어|한다|해줄게)')]),
    _Rule('love', [RegExp(r'사랑해|좋아해|보고\s*싶|뽀뽀|쓰다듬|쓰담|안아(?!파|프|픈|팠|플)|포옹|결혼하자')]),
    _Rule('praise_bot', [RegExp(r'(귀엽|귀여|예뻐|예쁘|최고야|최고다|멋있|멋져|잘한다|똑똑하|천재|대단해|훌륭|완벽해)')]),
    // farewell before greeting so "안녕히 잘 가" is not a greeting
    _Rule('farewell', [
      RegExp(r'잘\s*가|안녕히|가볼게|이따\s*(봐|보자)|잘\s*자|굿나잇|바이|good\s?bye|나\s*가야\s*해|갈게$', caseSensitive: false),
    ]),
    _Rule('greeting', [
      RegExp(r'^(안녕|안녕하세요|안뇽|하이|헬로|여러분|왔어|왔다|반가|반갑|좋은\s*아침|좋은\s*저녁|굿모닝|hello|hi)', caseSensitive: false),
    ]),
    _Rule('thanks', [RegExp(r'고마워|고맙|감사|ㄳ')]),
    // names only in "내/제 이름은 X", "X라고 해", "나는 X야" forms
    _Rule('tell_name', [
      RegExp(r'(?:내|제)\s*이름은\s*([가-힣A-Za-z0-9]{1,8})'),
      RegExp(r'^(?:나는|저는)\s*([가-힣A-Za-z0-9]{1,8}?)\s*(?:이야|야요|입니다|예요|이에요|이라고\s*해|라고\s*해)'),
      RegExp(r'([가-힣A-Za-z0-9]{1,8}?)\s*(?:이라고|라고)\s*해\s*$'),
    ]),
    _Rule('ask_name', [RegExp(r'이름이\s*뭐|너\s*누구|너\s*뭐야|자기\s*소개|소개해|네\s*이름')]),
    _Rule('funny', [RegExp(r'ㅋㅋ|ㅎㅎ|웃기|드립|개그|유머|조크|ㅇㅈ|ㄹㅇ|찢었다|레전드|lol|kk+', caseSensitive: false)]),
    _Rule('sad', [
      RegExp(r'슬퍼|슬프|우울|힘들|지쳤|피곤|외로|눈물|속상|ㅠㅠ|흑흑|울고|스트레스|기분\s*나빠|아파|아프다|아픈데|아프네|심심|지루|따분|하기\s*싫|먹기\s*싫|가기\s*싫'),
    ]),
    _Rule('angry_user', [RegExp(r'화나|화가\s*나|열받|짜증|빡치|빡침|분노|싸우고|싸웠|억울')]),
    _Rule('surprise', [RegExp(r'헉|헐|놀랐|놀라|세상에|ㄷㄷ|소름|깜짝|레알\?')]),
    _Rule('cheerful', [RegExp(r'좋아|좋다|재미있|재밌|즐거|행복|기분\s*좋|신나|설레|두근|굿|nice|great|🎉')]),
    _Rule('weather', [RegExp(r'날씨|덥다|덥네|춥다|춥네|비\s*와|비\s*오|눈\s*와|눈\s*오|미세먼지|더위|추위')]),
    _Rule('food', [
      RegExp(r'맛있|맛없|배고파|배고프|뭐\s*먹|밥\s*먹|사과|치킨|피자|떡볶|커피|아이스크림|초콜릿|과자|라면|김치|빵|떡|고기|디저트|간식|맛집'),
    ]),
    _Rule('question', [
      RegExp(r'\?\s*$'),
      RegExp(r'(?:뭐(?!랄까|든지|든\b|\s*그냥)|무엇)|왜|어떻게|언제|어디|누구|몇\s*(시|분|년|개|명|마리)|해줘|알려|일까|을까|까\?|어때|어떤데|줄래|할래|일해'),
    ]),
  ];

  static final _latin = RegExp(r'[A-Za-z]');
  static RegExp _en(String p) => RegExp(p, caseSensitive: false);
  static final _praiseEn = _en(r"\b(cute|adorable|the best|awesome|amazing|smart|genius|great job|well done|clever|love you)\b");

  // English rules, same moods and order as the Korean ones (owner, 2026-10-28).
  static final List<_Rule> _rulesEn = [
    _Rule('insult_bot', [
      _en(r"\b(stupid|dumb|idiot|moron|useless|ugly|loser|trash|shut up|go away|get lost|you suck|i hate you|worst pet)\b"),
      _en(r"\byou(?:'re|\s+are)?\s+(?:so\s+|really\s+|such\s+an?\s+)?(?:annoying|boring|lame|bad|the worst)\b"),
    ]),
    _Rule('apology', [_en(r"\b(sorry|apologi[sz]e|my bad|forgive me|i was wrong)\b")]),
    _Rule('love', [_en(r"\b(i love you|love you|luv u|miss you|i like you|hugs?|kiss(es)?|pat you|marry me)\b")]),
    _Rule('praise_bot', [_en(r"\b(cute|adorable|you(?:'re|\s+are) the best|awesome|amazing|so smart|smart pet|genius|good (?:boy|girl|job)|great job|well done|clever|perfect|so cool)\b")]),
    _Rule('farewell', [_en(r"\b(bye|goodbye|good night|gn|see you|see ya|talk later|gotta go|have to go)\b")]),
    _Rule('greeting', [_en(r"^(hi|hello|hey|yo|howdy|hiya|good morning|good evening|morning|i'?m back)\b")]),
    _Rule('thanks', [_en(r"\b(thanks|thank you|thx|ty|appreciate it)\b")]),
    _Rule('tell_name', [_en(r"\bmy name is\s+([A-Za-z][A-Za-z0-9]{0,11})\b"), _en(r"\bcall me\s+([A-Za-z][A-Za-z0-9]{0,11})\b")]),
    _Rule('ask_name', [_en(r"\b(what'?s your name|what is your name|who are you|introduce yourself)\b")]),
    _Rule('funny', [_en(r"\b(lol|lmao|rofl|ha(ha)+|he(he)+|so funny|that'?s funny|hilarious|joke)\b")]),
    _Rule('sad', [_en(r"\b(sad|depressed|tired|exhausted|lonely|crying|cry|stressed|hurts?|sick|bored|boring|feel(?:ing)? (?:bad|down|low)|upset|miserable)\b")]),
    _Rule('angry_user', [_en(r"\b(angry|mad|furious|pissed|annoyed|frustrated|so unfair)\b")]),
    _Rule('surprise', [_en(r"\b(wow|whoa|omg|oh my god|no way|shocked|surprised|unbelievable)\b")]),
    _Rule('cheerful', [_en(r"\b(happy|great|good|fun|excited|yay|nice|glad|wonderful|fantastic)\b")]),
    _Rule('weather', [_en(r"\b(weather|rain(?:ing|y)?|snow(?:ing)?|hot|cold|sunny|humid|windy)\b")]),
    _Rule('food', [_en(r"\b(hungry|food|eat|eating|lunch|dinner|breakfast|snacks?|pizza|chicken|coffee|ice cream|cake|cookies?|delicious|yummy)\b")]),
    _Rule('question', [_en(r"\?\s*$"), _en(r"^(what|why|how|when|where|who|which|can you|could you|tell me|should i|do you)\b")]),
  ];

  static final _han = RegExp(r'[一-鿿]');
  static final _praiseZh = RegExp(r'可爱|好棒|真棒|厉害|聪明|天才|最棒|好乖|漂亮|爱你');

  // Chinese rules, same moods and order (owner, 2026-10-28). "你好烦" is an
  // insult and "你好棒" praise, so both come before the 你好 greeting.
  static final List<_Rule> _rulesZh = [
    _Rule('insult_bot', [RegExp(r'笨蛋|傻瓜|白痴|蠢|讨厌你|滚开|闭嘴|没用|垃圾|丑八怪|你好烦|烦死了|你真烦|你好笨|你真笨|你很笨')]),
    _Rule('apology', [RegExp(r'对不起|抱歉|不好意思|我错了|原谅我')]),
    _Rule('love', [RegExp(r'我爱你|爱你|喜欢你|想你|抱抱|亲亲|摸摸')]),
    _Rule('praise_bot', [RegExp(r'可爱|好棒|真棒|厉害|聪明|天才|最棒|最好了|好乖|漂亮|好帅')]),
    _Rule('farewell', [RegExp(r'再见|拜拜|晚安|回头见|我走了|先走了')]),
    _Rule('greeting', [RegExp(r'^(你好|您好|嗨|哈喽|早上好|早安|晚上好|我回来了)')]),
    _Rule('thanks', [RegExp(r'谢谢|多谢|感谢|谢啦')]),
    _Rule('tell_name', [RegExp(r'我叫([一-鿿A-Za-z]{1,6})'), RegExp(r'我的名字是([一-鿿A-Za-z]{1,6})')]),
    _Rule('ask_name', [RegExp(r'你叫什么|你是谁|你的名字')]),
    _Rule('funny', [RegExp(r'哈哈|嘿嘿|嘻嘻|好笑|笑死|搞笑|段子')]),
    _Rule('sad', [RegExp(r'难过|伤心|好累|累死|孤单|寂寞|想哭|哭了|压力|不舒服|生病|无聊|郁闷|心情不好')]),
    _Rule('angry_user', [RegExp(r'生气|气死|烦躁|好气|火大|不公平')]),
    _Rule('surprise', [RegExp(r'哇|天哪|天啊|不会吧|真的假的|吓死|震惊|居然')]),
    _Rule('cheerful', [RegExp(r'开心|高兴|快乐|太好了|好玩|兴奋|耶')]),
    _Rule('weather', [RegExp(r'天气|下雨|下雪|好热|好冷|刮风')]),
    _Rule('food', [RegExp(r'饿|好吃|吃饭|午饭|晚饭|早饭|零食|咖啡|蛋糕|饼干|披萨|炸鸡|奶茶')]),
    _Rule('question', [RegExp(r'[?？]\s*$'), RegExp(r'什么|为什么|怎么|哪里|哪儿|谁|几点|能不能|可以帮')]),
  ];
  static final _preNegZh = RegExp(r'(不|没|没有|别|不是|并不)$');
  static const _notNameZh = {'学生', '朋友', '机器人', '主人', '老师', '笨蛋'};

  static final _preNegEn = _en(r"(\bnot|n't|\bnever|\bno)\s+(?:\w+\s+)?$");
  static const _notNameEn = {'robot', 'student', 'friend', 'human', 'person', 'boy', 'girl', 'owner', 'teacher', 'nobody', 'anyone'};

  // Moods that a leading/trailing negation can switch off.
  static const _negatable = {'insult_bot', 'sad', 'cheerful', 'angry_user', 'praise_bot', 'love', 'funny'};

  static final _preNeg1 = RegExp(r'(^|\s)(안|못|별로|전혀|하나도|안니)\s*$');
  static final _preNeg2 = RegExp(r'(아니|않)\s*$');
  static final _trailingNeg = RegExp(r'[.!?~\s]*(아니야|아니에요|아니|않아|않어요|아닌데)\s*[.!?~]*$');

  // Common nouns that are never stored as a name.
  static const _notName = {
    '학생', '사람', '남자', '여자', '친구', '로봇', '아바타', '피곤', '배고파', '고양이', '강아지',
    '별명', '이름', '농담', '장난', '비밀', '거짓말', '천재', '바보', '누구', '아무개', '주인', '선생님',
  };
  static final _nameSuffix = RegExp(r'(이야|이라고|입니다|이에요|예요|이당|라고|임|당|야)$');
  static final _nameJunk = RegExp(r'^(이야|야|임|라고|이라고|입니다)$');

  // "안 슬퍼": a negator right before the match
  static bool _negatedBefore(String t, int idx) {
    final pre = t.substring(max(0, idx - 7), idx);
    return _preNeg1.hasMatch(pre) || _preNeg2.hasMatch(pre);
  }

  static const _feelingOf = {
    'insult_bot': OwnerFeeling.angry,
    'apology': OwnerFeeling.happy,
    'love': OwnerFeeling.love,
    'praise_bot': OwnerFeeling.happy,
    'farewell': OwnerFeeling.sad,
    'greeting': OwnerFeeling.happy,
    'thanks': OwnerFeeling.happy,
    'ask_name': OwnerFeeling.curious,
    'funny': OwnerFeeling.laugh,
    'sad': OwnerFeeling.sad,
    'angry_user': OwnerFeeling.surprised,
    'surprise': OwnerFeeling.surprised,
    'cheerful': OwnerFeeling.happy,
    'weather': OwnerFeeling.curious,
    'food': OwnerFeeling.happy,
    'question': OwnerFeeling.thinking,
  };

  /// Reads one utterance. Empty or Hangul-free text gives [FeelingRead.neutral].
  static FeelingRead read(String text) {
    final t = text.trim();
    if (t.isEmpty) return FeelingRead.neutral;
    if (!_hangul.hasMatch(t)) {
      if (_han.hasMatch(t)) return _readZh(t);
      return _latin.hasMatch(t) ? _readEn(t) : FeelingRead.neutral;
    }

    for (final rule in _rules) {
      for (final p in rule.patterns) {
        final m = p.firstMatch(t);
        if (m == null) continue;
        if (_negatedBefore(t, m.start)) continue; // "안 슬퍼" skips this rule
        if (_negatable.contains(rule.mood) && _trailingNeg.hasMatch(t)) continue; // "바보 아니야"
        var mood = rule.mood;
        // insult + praise in one sentence ("바보 같이 귀여워") reads as praise
        if (mood == 'insult_bot' && _praiseRe.hasMatch(t)) mood = 'praise_bot';
        return _build(mood, m, t);
      }
    }
    return FeelingRead.neutral;
  }

  static FeelingRead _readZh(String t) {
    for (final rule in _rulesZh) {
      for (final p in rule.patterns) {
        final m = p.firstMatch(t);
        if (m == null) continue;
        // "我不难过", "你不笨", "我没生气"
        if (_negatable.contains(rule.mood) && _preNegZh.hasMatch(t.substring(max(0, m.start - 2), m.start))) continue;
        var mood = rule.mood;
        if (mood == 'insult_bot' && _praiseZh.hasMatch(t)) mood = 'praise_bot'; // "笨笨的好可爱"
        if (mood == 'tell_name') {
          final nm = m.group(1);
          final ok = nm != null && !_notNameZh.contains(nm);
          return FeelingRead(
              feeling: ok ? OwnerFeeling.love : OwnerFeeling.curious, strength: _strength(t), mood: mood, name: ok ? nm : null);
        }
        return _build(mood, m, t);
      }
    }
    return FeelingRead.neutral;
  }

  static FeelingRead _readEn(String t) {
    for (final rule in _rulesEn) {
      for (final p in rule.patterns) {
        final m = p.firstMatch(t);
        if (m == null) continue;
        // "you're not stupid", "I'm not sad", "don't cry"
        if (_negatable.contains(rule.mood) && _preNegEn.hasMatch(t.substring(max(0, m.start - 16), m.start))) continue;
        var mood = rule.mood;
        if (mood == 'insult_bot' && _praiseEn.hasMatch(t)) mood = 'praise_bot'; // "stupid but cute"
        if (mood == 'tell_name') {
          final nm = m.group(1);
          final ok = nm != null && !_notNameEn.contains(nm.toLowerCase());
          return FeelingRead(
              feeling: ok ? OwnerFeeling.love : OwnerFeeling.curious, strength: _strength(t), mood: mood, name: ok ? nm : null);
        }
        return _build(mood, m, t);
      }
    }
    return FeelingRead.neutral;
  }

  static FeelingRead _build(String mood, Match m, String t) {
    String? name;
    var feeling = _feelingOf[mood] ?? OwnerFeeling.neutral;
    if (mood == 'tell_name') {
      var nm = m.group(1);
      if (nm != null) nm = nm.replaceFirst(_nameSuffix, '');
      if (nm != null && nm.isNotEmpty && nm.length <= 8 && !_nameJunk.hasMatch(nm) && !_notName.contains(nm)) {
        name = nm;
        feeling = OwnerFeeling.love;
      } else {
        feeling = OwnerFeeling.curious;
      }
    }
    return FeelingRead(
      feeling: feeling,
      strength: _strength(t),
      insult: mood == 'insult_bot',
      apology: mood == 'apology',
      praise: mood == 'praise_bot',
      mood: mood,
      name: name,
    );
  }

  static double _strength(String t) {
    var s = 0.6;
    final bangs = '!'.allMatches(t).length;
    s += 0.1 * min(2, bangs);
    if (RegExp(r'(ㅋ{3,}|ㅠ{2,}|ㅎ{3,})').hasMatch(t)) s += 0.1;
    if (t.length >= 20) s += 0.1;
    return min(1.0, s);
  }

  /// Expression while the owner is still typing/speaking (app.js preview).
  /// Empty -> neutral; question/weather -> thinking; cheerful kinds -> happy;
  /// shocking kinds -> surprised; anything else -> curious. While sulking the
  /// pet stays sulky.
  static List<OwnerFeeling> listeningPreview(String partialText, {bool sulking = false}) {
    if (sulking) return const [OwnerFeeling.sulky];
    final t = partialText.trim();
    if (t.isEmpty) return const [OwnerFeeling.neutral];
    switch (read(t).mood) {
      case 'question':
      case 'weather':
        return const [OwnerFeeling.thinking];
      case 'funny':
      case 'cheerful':
      case 'greeting':
      case 'praise_bot':
      case 'thanks':
        return const [OwnerFeeling.happy];
      case 'love':
      case 'sad':
      case 'angry_user':
      case 'surprise':
      case 'insult_bot':
        return const [OwnerFeeling.surprised];
      default:
        return const [OwnerFeeling.curious];
    }
  }
}

/// Sulk state machine from brain.js. An insult makes the pet sulk; while
/// sulking it ignores most talk and only an apology (or two loving words)
/// lifts it. Praise, greetings and farewells get a normal reaction but do
/// not lift it.
class SulkState {
  bool sulking;

  /// Loving messages received while sulking (2 lift the sulk).
  int niceCount;
  final Random _rng;

  SulkState({this.sulking = false, this.niceCount = 0, Random? rng}) : _rng = rng ?? Random();

  factory SulkState.fromJson(Map<String, dynamic> j) =>
      SulkState(sulking: j['sulking'] == true, niceCount: (j['niceCount'] as num?)?.toInt() ?? 0);

  Map<String, dynamic> toJson() => {'sulking': sulking, 'niceCount': niceCount};

  static const _passThrough = {'apology', 'love', 'praise_bot', 'greeting', 'farewell'};

  /// Expression sequence to show for [r]; updates the sulk state.
  List<OwnerFeeling> react(FeelingRead r) {
    if (sulking && !_passThrough.contains(r.mood)) return const [OwnerFeeling.sulky];

    switch (r.mood) {
      case 'insult_bot':
        sulking = true;
        niceCount = 0;
        return const [OwnerFeeling.angry, OwnerFeeling.sulky];
      case 'apology':
        if (sulking) {
          sulking = false;
          niceCount = 0;
          return const [OwnerFeeling.thinking, OwnerFeeling.happy];
        }
        return const [OwnerFeeling.curious, OwnerFeeling.happy];
      case 'love':
        if (sulking) {
          niceCount++;
          if (niceCount >= 2) {
            sulking = false;
            niceCount = 0;
            return const [OwnerFeeling.sulky, OwnerFeeling.surprised, OwnerFeeling.love];
          }
          return const [OwnerFeeling.sulky];
        }
        return const [OwnerFeeling.surprised, OwnerFeeling.love];
      case 'praise_bot':
        return [OwnerFeeling.surprised, _rng.nextBool() ? OwnerFeeling.happy : OwnerFeeling.love];
      case 'greeting':
        return const [OwnerFeeling.happy];
      case 'ask_name':
        return const [OwnerFeeling.curious];
      case 'tell_name':
        return r.name != null
            ? const [OwnerFeeling.surprised, OwnerFeeling.happy, OwnerFeeling.love]
            : const [OwnerFeeling.thinking, OwnerFeeling.curious];
      case 'funny':
        return const [OwnerFeeling.happy, OwnerFeeling.laugh];
      case 'cheerful':
        return const [OwnerFeeling.curious, OwnerFeeling.happy];
      case 'sad':
        return const [OwnerFeeling.surprised, OwnerFeeling.sad];
      case 'angry_user':
        return const [OwnerFeeling.surprised, OwnerFeeling.sad, OwnerFeeling.curious];
      case 'surprise':
        return const [OwnerFeeling.surprised, OwnerFeeling.curious];
      case 'thanks':
        return const [OwnerFeeling.happy, OwnerFeeling.love];
      case 'farewell':
        return const [OwnerFeeling.sad, OwnerFeeling.love];
      case 'weather':
        return const [OwnerFeeling.thinking, OwnerFeeling.curious];
      case 'food':
        return const [OwnerFeeling.surprised, OwnerFeeling.happy, OwnerFeeling.love];
      case 'question':
        return const [OwnerFeeling.thinking, OwnerFeeling.curious];
      default:
        return const [OwnerFeeling.curious];
    }
  }
}
