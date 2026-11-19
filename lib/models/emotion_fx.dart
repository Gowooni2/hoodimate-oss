import 'package:flutter/material.dart';

import 'pet_state.dart';
import 'profile.dart';

/// KakaoTalk-emoticon style lettering: a short, loud sound-word drawn big
/// and outlined on top of a sticker ("냠냠쩝쩝!!", "흥칫뿡!"), in the
/// owner's language. Color and tilt give each feeling its own look.
class EmotionFx {
  final String ko, en, zh;
  final Color color;

  /// Rotation in degrees (handwritten feel).
  final double tilt;

  /// Bounces with the sticker (excited feelings) or sits still (calm ones).
  final bool bouncy;
  const EmotionFx(this.ko, this.en, this.zh, this.color, {this.tilt = -6, this.bouncy = true});

  String get text => Lang.t(ko, en, zh);

  static const _pink = Color(0xFFFF5C8A);
  static const _orange = Color(0xFFFF8A1F);
  static const _yellow = Color(0xFFFFC21A);
  static const _green = Color(0xFF2FBF71);
  static const _blue = Color(0xFF3B8BFF);
  static const _navy = Color(0xFF5A63C8);
  static const _purple = Color(0xFF9B5CFF);
  static const _gray = Color(0xFF8C8C9A);
  static const _red = Color(0xFFFF4040);
  static const _brown = Color(0xFFA0683C);

  /// Lettering for each emoticon in the basic pack (keys = Emoticon.id).
  static const byEmoticon = <String, EmotionFx>{
    'hello': EmotionFx('안뇽~!!', 'Hiii~!!', '嗨嗨~！！', _orange),
    'yummy': EmotionFx('냠냠쩝쩝!!', 'Nom nom!!', '吧唧吧唧！！', _orange, tilt: 5),
    'yay': EmotionFx('신난다아!!', 'Yaaay!!', '耶耶耶！！', _yellow, tilt: -8),
    'love': EmotionFx('헤헷 ♡', 'Hehe ♡', '嘿嘿 ♡', _pink, tilt: 4),
    'tickle': EmotionFx('꺄르르~ㅋㅋ', 'Teehee~ lol', '咯咯咯~哈哈', _pink, tilt: 8),
    'thanks': EmotionFx('꾸벅!', '*bows*', '鞠躬！', _green, tilt: -3, bouncy: false),
    'sleepy': EmotionFx('하아암…', 'Yaaawn…', '哈欠…', _navy, tilt: 0, bouncy: false),
    'night': EmotionFx('쿨쿨…zZ', 'zzZ…', '呼呼…zZ', _navy, tilt: 0, bouncy: false),
    'morning': EmotionFx('기지개 쭈욱~', 'Streeetch~', '伸个懒腰~', _yellow, tilt: -4),
    'hungry': EmotionFx('꼬르륵…', '*grumble*…', '咕噜噜…', _brown, tilt: 3, bouncy: false),
    'playwithme': EmotionFx('놀아조오~ㅠ', 'Play with meee~', '陪我玩嘛~', _purple, tilt: -7),
    'sulky': EmotionFx('흥칫뿡!', 'Hmph!!', '哼唧！', _red, tilt: 7),
    'sad': EmotionFx('흐엥 ㅠㅠ', 'Waaah T_T', '呜呜呜 T_T', _blue, tilt: 0, bouncy: false),
    'best': EmotionFx('최고최고!!', 'THE BEST!!', '最棒啦！！', _yellow, tilt: -9),
    'hot': EmotionFx('녹는다…', 'Melting…', '要化了…', _red, tilt: 4, bouncy: false),
    'cold': EmotionFx('덜덜덜…', 'Brrrr…', '瑟瑟发抖…', _blue, tilt: -2),
    'scared': EmotionFx('히익!!', 'Eeek!!', '妈呀！！', _purple, tilt: 10),
    'hmm': EmotionFx('흐음…?', 'Hmmm…?', '嗯哼…？', _gray, tilt: 0, bouncy: false),
    'listening': EmotionFx('쫑긋!', '*ears up*', '竖起耳朵！', _green, tilt: -4, bouncy: false),
    'working': EmotionFx('타닥타닥…', 'Tap tap tap…', '噼里啪啦…', _gray, tilt: 0, bouncy: false),
    'done': EmotionFx('짜잔~!', 'Ta-da~!', '搞定~！', _green, tilt: -6),
    'oops': EmotionFx('앗차차…', 'Oopsie…', '哎呀呀…', _gray, tilt: 6, bouncy: false),
    'wakeup': EmotionFx('따르릉!!', 'RING RING!!', '叮铃铃！！', _red, tilt: -10),
    'coffee': EmotionFx('호로록~', 'Sluuurp~', '吸溜~', _brown, tilt: 3, bouncy: false),
    'umbrella': EmotionFx('토독토독~', 'Pitter-pat~', '滴答滴答~', _blue, tilt: -4),
  };

  /// Lettering for the pet's moods (speech bubbles without an emoticon).
  static const byMood = <PetMood, EmotionFx>{
    PetMood.idle: EmotionFx('뒹굴뒹굴~', 'La la la~', '悠哉悠哉~', _gray, tilt: 0, bouncy: false),
    PetMood.happy: EmotionFx('헤헤~', 'Hehe~', '嘿嘿~', _pink, tilt: -5),
    PetMood.celebrating: EmotionFx('축하축하!!', 'Woohoo!!', '撒花撒花！！', _yellow, tilt: -9),
    PetMood.sad: EmotionFx('시무룩…', '*sniff*…', '委屈巴巴…', _blue, tilt: 0, bouncy: false),
    PetMood.bored: EmotionFx('심심해애~', 'Boooored~', '好无聊~', _purple, tilt: 5, bouncy: false),
    PetMood.sleepy: EmotionFx('꾸벅꾸벅…', '*nods off*…', '打瞌睡…', _navy, tilt: 0, bouncy: false),
    PetMood.talking: EmotionFx('조잘조잘~', 'Chit-chat~', '叽叽喳喳~', _green, tilt: -4),
    PetMood.thinking: EmotionFx('으음…?', 'Hmm…?', '嗯…？', _gray, tilt: 0, bouncy: false),
    PetMood.eating: EmotionFx('냠냠!', 'Nom!', '吧唧！', _orange, tilt: 5),
    PetMood.sick: EmotionFx('콜록콜록…', '*cough cough*…', '咳咳…', _green, tilt: 0, bouncy: false),
    PetMood.waving: EmotionFx('안뇽!', 'Hi hi!', '嗨！', _orange, tilt: -6),
    PetMood.rain: EmotionFx('주룩주룩…', 'Drip drop…', '哗啦啦…', _blue, tilt: 0, bouncy: false),
    PetMood.hot: EmotionFx('헥헥…', '*pant pant*…', '呼哧呼哧…', _red, tilt: 4, bouncy: false),
  };
}

/// The cute rounded font for the pet's own words: Jua (Korean + Latin),
/// ZCOOL KuaiLe for Chinese. Both SIL OFL 1.1, bundled in assets/fonts.
class CuteFont {
  static String get family => Lang.zh ? 'ZCOOLKuaiLe' : 'Jua';
  static List<String> get fallback => Lang.zh ? const ['Jua'] : const ['ZCOOLKuaiLe'];

  /// Owner's choice for chat text (menu / settings): cute font or the
  /// system font, and a size factor. Lettering on stickers stays cute.
  static bool cute = true;
  static double scale = 1.0;

  /// Jua has no ’ ‘ … — –; the fallback (ZCOOL KuaiLe) draws them full
  /// width, so "I’m" looked like "I’ m". Swap them for Jua's own glyphs
  /// before showing chat or bubble text in the cute font.
  static String fit(String s) {
    if (!cute || Lang.zh) return s;
    return s
        .replaceAll(RegExp('[‘’]'), "'")
        .replaceAll('…', '...')
        .replaceAll(RegExp('[–—]'), '-');
  }

  /// Chat and speech-bubble text.
  static TextStyle style({double size = 13, Color color = Colors.black87}) => cute
      ? TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: size * scale, color: color, height: 1.25)
      : TextStyle(fontSize: (size - 1) * scale, color: color, height: 1.3);
}

/// Outlined lettering: white outline, colored fill, slight tilt.
class FxText extends StatelessWidget {
  final EmotionFx fx;
  final double size;
  const FxText(this.fx, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    // Jua/KuaiLe are already chunky: no faux bold.
    final style = TextStyle(fontFamily: CuteFont.family, fontFamilyFallback: CuteFont.fallback,
        fontSize: size, height: 1.0, letterSpacing: -0.2);
    return Transform.rotate(
      angle: fx.tilt * 3.14159 / 180,
      child: Stack(
        children: [
          Text(fx.text,
              style: style.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = size / 4.5
                    ..strokeJoin = StrokeJoin.round
                    ..color = Colors.white)),
          Text(fx.text, style: style.copyWith(color: fx.color, shadows: [
            Shadow(color: Colors.black.withValues(alpha: 0.18), offset: const Offset(0, 1.5), blurRadius: 1.5),
          ])),
        ],
      ),
    );
  }
}
