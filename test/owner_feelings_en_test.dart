import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/owner_feelings.dart';

// English rules (owner, 2026-10-28): same moods as the Korean ones.
void main() {
  String mood(String t) => OwnerFeelings.read(t).mood;

  test('insults, with the negation and praise guards', () {
    expect(mood("you're stupid"), 'insult_bot');
    expect(mood('shut up'), 'insult_bot');
    expect(mood('you are so annoying'), 'insult_bot');
    expect(mood("you're not stupid"), isNot('insult_bot'));
    expect(mood("you're stupid but cute"), 'praise_bot');
  });

  test('apology, love, praise, thanks', () {
    expect(mood("I'm sorry"), 'apology');
    expect(mood('my bad'), 'apology');
    expect(mood('I love you'), 'love');
    expect(mood("you're so cute"), 'praise_bot');
    expect(mood('good job!'), 'praise_bot');
    expect(mood('thank you'), 'thanks');
  });

  test('greeting and farewell', () {
    expect(mood('hi there'), 'greeting');
    expect(mood('Good morning!'), 'greeting');
    expect(mood('bye bye'), 'farewell');
    expect(mood('good night'), 'farewell');
  });

  test('sad, with the negation guard; boring alone is sad, not an insult', () {
    expect(mood("I'm so tired"), 'sad');
    expect(mood('today was boring'), 'sad');
    expect(mood("I'm not sad"), isNot('sad'));
  });

  test('funny, angry, surprise, cheerful', () {
    expect(mood('lol'), 'funny');
    expect(mood('hahaha'), 'funny');
    expect(mood("I'm so angry"), 'angry_user');
    expect(mood('omg'), 'surprise');
    expect(mood("I'm happy today"), 'cheerful');
  });

  test('weather, food, question', () {
    expect(mood("what's the weather like?"), 'weather');
    expect(mood("I'm hungry"), 'food');
    expect(mood('can you help me'), 'question');
    expect(mood('where is it?'), 'question');
  });

  test('names: "my name is Alex" yes, "my name is robot" no', () {
    expect(OwnerFeelings.read('my name is Alex').name, 'Alex');
    expect(OwnerFeelings.read('my name is robot').name, isNull);
    expect(mood("what's your name?"), 'ask_name');
  });

  test('words inside other words do not count', () {
    expect(mood('the hotel was fine'), isNot('weather'));
    expect(mood('scarf'), 'neutral');
  });

  test('English sulk: insult -> sulky, apology lifts it', () {
    final s = SulkState(rng: Random(1));
    expect(s.react(OwnerFeelings.read('you are dumb')), [OwnerFeeling.angry, OwnerFeeling.sulky]);
    expect(s.sulking, isTrue);
    expect(s.react(OwnerFeelings.read('what time is it?')), [OwnerFeeling.sulky]);
    s.react(OwnerFeelings.read('sorry!'));
    expect(s.sulking, isFalse);
  });

  test('a lone emoji stays neutral (Chinese has its own rules)', () {
    expect(mood('🙂'), 'neutral');
    expect(mood('你好'), 'greeting');
  });
}
