import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/owner_feelings.dart';

// Chinese rules (owner, 2026-10-28): same moods as Korean and English.
void main() {
  String mood(String t) => OwnerFeelings.read(t).mood;

  test('insult, negation, insult + praise', () {
    expect(mood('你是笨蛋'), 'insult_bot');
    expect(mood('你好烦'), 'insult_bot');
    expect(mood('闭嘴！'), 'insult_bot');
    expect(mood('笨笨的好可爱'), 'praise_bot');
  });

  test('你好 is a greeting, 你好棒 is praise', () {
    expect(mood('你好'), 'greeting');
    expect(mood('你好棒'), 'praise_bot');
    expect(mood('早上好！'), 'greeting');
  });

  test('apology, love, thanks, farewell', () {
    expect(mood('对不起'), 'apology');
    expect(mood('不好意思'), 'apology');
    expect(mood('我爱你'), 'love');
    expect(mood('谢谢你'), 'thanks');
    expect(mood('晚安'), 'farewell');
  });

  test('sad with negation guard', () {
    expect(mood('我好累'), 'sad');
    expect(mood('今天好无聊'), 'sad');
    expect(mood('我不难过'), isNot('sad'));
    expect(mood('我没生气'), isNot('angry_user'));
  });

  test('funny, surprise, cheerful, weather, food, question', () {
    expect(mood('哈哈哈'), 'funny');
    expect(mood('哇！'), 'surprise');
    expect(mood('今天好开心'), 'cheerful');
    expect(mood('今天天气怎么样'), 'weather');
    expect(mood('我饿了'), 'food');
    expect(mood('现在几点？'), 'question');
  });

  test('names', () {
    expect(OwnerFeelings.read('我叫小明').name, '小明');
    expect(OwnerFeelings.read('我叫学生').name, isNull);
    expect(mood('你叫什么名字'), 'ask_name');
  });

  test('Chinese sulk: insult -> sulky, apology lifts it', () {
    final s = SulkState(rng: Random(1));
    expect(s.react(OwnerFeelings.read('你是笨蛋')), [OwnerFeeling.angry, OwnerFeeling.sulky]);
    expect(s.react(OwnerFeelings.read('现在几点？')), [OwnerFeeling.sulky]);
    s.react(OwnerFeelings.read('对不起'));
    expect(s.sulking, isFalse);
  });
}
