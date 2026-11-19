// Pet mood and chat models.
library;

import 'character.dart';
import 'profile.dart';

enum PetMood {
  idle,
  happy,
  celebrating,
  sad,
  bored,
  sleepy,
  talking,
  thinking,
  eating,
  sick,
  waving,
  rain,
  hot,
}

extension PetMoodSprite on PetMood {
  /// Asset path for the sprite to show for this mood.
  String get sprite {
    // paw on chin, looking up (pose from the situation sheet)
    if (this == PetMood.thinking) return Character.current.sprite('thinking');
    // celebrating.png has a baked-in confetti background and a smaller
    // character than the rest of the set, so the happy pose stands in.
    if (this == PetMood.celebrating) return Character.current.sprite('happy');
    return Character.current.sprite(name);
  }

  String get label {
    switch (this) {
      case PetMood.idle:
        return Lang.t('평온', 'Calm', '平静');
      case PetMood.happy:
        return Lang.t('기쁨', 'Happy', '开心');
      case PetMood.celebrating:
        return Lang.t('축하', 'Cheer', '庆祝');
      case PetMood.sad:
        return Lang.t('슬픔', 'Sad', '难过');
      case PetMood.bored:
        return Lang.t('심심', 'Bored', '无聊');
      case PetMood.sleepy:
        return Lang.t('졸림', 'Sleepy', '困困');
      case PetMood.talking:
        return Lang.t('말하는 중', 'Talking', '说话中');
      case PetMood.thinking:
        return Lang.t('생각 중', 'Thinking', '思考中');
      case PetMood.eating:
        return Lang.t('냠냠', 'Yum', '吧唧吧唧');
      case PetMood.sick:
        return Lang.t('아픔', 'Sick', '不舒服');
      case PetMood.waving:
        return Lang.t('인사', 'Hello', '你好');
      case PetMood.rain:
        return Lang.t('비', 'Rain', '下雨');
      case PetMood.hot:
        return Lang.t('더위', 'Hot', '炎热');
    }
  }
}

/// Physical reactions to the mouse (drive the pet's procedural motion).
enum PetReaction { none, boop, pet, tickle, thanks }

class ChatMessage {
  final String text;
  final bool fromUser;
  final DateTime at;

  /// Emoticon id (models/emoticons.dart) shown as an animated sticker above
  /// the text, KakaoTalk style. Null for plain text.
  final String? sticker;

  ChatMessage({required this.text, required this.fromUser, required this.at, this.sticker});
}
