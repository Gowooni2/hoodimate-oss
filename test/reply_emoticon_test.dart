import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/emoticons.dart';
import 'package:hoodimong/models/pet_state.dart';

// Owner (2026-10-12): every chat reply showed the same "Yaaay!!" emoticon.
void main() {
  String? r(String reply, {String q = '', PetMood mood = PetMood.happy, String? last}) =>
      Emoticons.forReply(reply, mood, question: q, last: last, pick: (_) => 0);

  test('the emoticon follows what was said, in all three languages', () {
    expect(r('Maybe a cozy snack and a little nap?'), 'yummy');
    expect(r('Thanks for asking!'), 'thanks');
    expect(r('Done! I set a reminder for 3 PM.'), 'done');
    expect(r('Sorry, I couldn\'t find that.'), 'oops');
    expect(r('Good night, sleep tight!'), 'night');
    expect(r('커피 한 잔 어때?'), 'coffee');
    expect(r('고마워!'), 'thanks');
    expect(r('오늘 많이 힘들었구나'), 'sad');
    expect(r('好的，提醒已经设好了'), 'done');
    expect(r('一起玩吧！'), 'playwithme');
  });

  test('the owner\'s question counts when the reply has no topic word', () {
    expect(r('Sure thing!', q: 'Any snack ideas?'), 'yummy');
    expect(r('물론이지!', q: '알람 맞춰줘'), 'done');
  });

  test('English words match whole words only', () {
    // "great" has "eat", "display" has "play", "shot" has "hot".
    expect(r('That looks great on the display, nice shot!', last: 'yay'), isNot(anyOf('yummy', 'playwithme', 'hot')));
  });

  test('no topic word: a different emoticon from the mood set than last time', () {
    final first = r('Sounds fun!');
    final second = r('Sounds fun!', last: first);
    expect(first, isNotNull);
    expect(second, isNot(first));
    for (var i = 0; i < 5; i++) {
      final id = Emoticons.forReply('Sounds fun!', PetMood.happy, pick: (_) => i % 4);
      expect(Emoticons.byId(id), isNotNull, reason: '$id');
    }
  });

  test('rain talk gets the umbrella; gloomy rain gets a sulk (owner, 2026-10-12)', () {
    expect(r('It might rain later, take an umbrella!'), 'umbrella');
    expect(r('오늘 비 와? 우산 챙겨야 하나'), 'umbrella');
    expect(r('비가 오네~'), 'umbrella');
    expect(r('今天下雨，记得带伞'), 'umbrella');
    expect(r('하늘이 우중충하네…'), 'sulky');
    // 준비 (ready) has 비 in it: not rain
    expect(r('준비가 다 됐어!'), 'done');
    expect(r('준비와 정리 끝!', last: 'yay'), isNot('umbrella'));
    expect(r('Training is going well', last: 'yay'), isNot('umbrella'));
  });

  test('every emoticon it can pick exists in the basic pack', () {
    for (final m in PetMood.values) {
      for (var i = 0; i < 6; i++) {
        final id = Emoticons.forReply('ok', m, pick: (n) => i % n);
        if (id != null) expect(Emoticons.byId(id), isNotNull, reason: '$m $id');
      }
    }
  });
}
