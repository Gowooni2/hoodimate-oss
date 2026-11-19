// Ported from AvatarTalk_App/tests/logic_test.js (emotion analysis, negation,
// insult/praise, sequences, sulking). Date: 2026-10-28.
// Skipped: arithmetic/template replies, name memory state, character
// catchphrases, STT silence logic, image asset checks.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/owner_feelings.dart';

String mood(String s) => OwnerFeelings.read(s).mood;

List<OwnerFeeling> go(SulkState st, String s) => st.react(OwnerFeelings.read(s));

void main() {
  group('emotion analysis', () {
    test('basic moods', () {
      expect(mood('바보야'), 'insult_bot');
      expect(mood('오늘 정말 재미있었어 ㅋㅋㅋ'), 'funny');
      expect(mood('사랑해!'), 'love');
      expect(mood('나 오늘 좀 우울해 ㅠㅠ'), 'sad');
      expect(mood('안녕!'), 'greeting');
      expect(mood('내 이름은 고운이야'), 'tell_name');
      expect(mood('3 더하기 5 알려줘'), 'question');
      expect(mood('그냥 평범한 날이었어'), 'neutral');
    });

    test('name recognition keeps names, drops common nouns', () {
      expect(OwnerFeelings.read('내 이름은 고운이야').name, '고운');
      expect(OwnerFeelings.read('나는 학생입니다').name, isNull);
      expect(OwnerFeelings.read('별명이라고 해').name, isNull);
      expect(OwnerFeelings.read('민수라고 해').name, '민수');
      expect(OwnerFeelings.read('고운이라고 해').name, '고운');
    });

    test('v2 misclassification fixes', () {
      expect(mood('나는 너무 슬퍼 ㅠㅠ'), 'sad');
      expect(mood('나는 배고파'), 'food');
      expect(mood('바보 같이 귀여워'), 'praise_bot');
      expect(mood('안녕히 잘 가'), 'farewell');
      expect(mood('안 슬퍼'), 'neutral');
      expect(mood('사과 하나 먹을까'), 'food');
    });

    test('v3 trailing negation guard', () {
      expect(mood('바보 아니야'), 'neutral');
      expect(mood('슬프지 않아'), 'neutral');
      expect(mood('기분 좋아 아니야'), 'neutral');
      expect(mood('바보'), 'insult_bot');
    });

    test('v4 false-positive fixes', () {
      expect(mood('아 배 안아파'), 'neutral');
      expect(mood('배 아파'), 'sad');
      expect(mood('꼭 안아줘'), 'love');
      expect(mood('아침 먹기 싫어'), 'sad');
      expect(mood('너 진짜 싫어'), 'insult_bot');
      expect(mood('뭐랄까 그냥 심심해'), 'sad');
      expect(mood('뭐랄까 그냥 그래'), 'neutral');
      expect(mood('사랑해 아니야'), 'neutral');
    });

    test('flags and neutral fallbacks', () {
      final r = OwnerFeelings.read('바보야!');
      expect(r.insult, isTrue);
      expect(r.feeling, OwnerFeeling.angry);
      expect(r.strength, greaterThan(0));
      expect(OwnerFeelings.read('바보 같이 귀여워').insult, isFalse);
      expect(OwnerFeelings.read('바보 같이 귀여워').praise, isTrue);
      expect(OwnerFeelings.read('미안해').apology, isTrue);
      // no Hangul: neutral by design
      // English has its own rules since 2026-10-28 (owner_feelings_en_test.dart).
      expect(OwnerFeelings.read('hello').mood, 'greeting');
      expect(OwnerFeelings.read('🙂'), same(FeelingRead.neutral));
      expect(OwnerFeelings.read(''), same(FeelingRead.neutral));
    });
  });

  group('sequences and sulking', () {
    test('insult -> angry then sulky, stays sulky, apology lifts', () {
      final st = SulkState();
      final seq = go(st, '바보야!');
      expect(seq.first, OwnerFeeling.angry); // angry feeling
      expect(seq[1], OwnerFeeling.sulky); // angry -> sulky sequence
      expect(st.sulking, isTrue);
      expect(go(st, '같이 놀자'), [OwnerFeeling.sulky]); // sulk persists
      final sorry = go(st, '미안해');
      expect(sorry.last, OwnerFeeling.happy); // released after apology
      expect(st.sulking, isFalse);
    });

    test('love gives surprised -> love', () {
      expect(go(SulkState(), '사랑해')[1], OwnerFeeling.love);
    });

    test('v4 name sentences do not break sequences', () {
      final st = SulkState();
      expect(go(st, '고운이라고 해').first, OwnerFeeling.surprised);
      expect(go(st, '별명이라고 해').first, OwnerFeeling.thinking);
    });

    test('v5 praise starts with surprise', () {
      final st = SulkState(rng: Random(1));
      final seq = go(st, '너 진짜 귀엽다');
      expect(seq.first, OwnerFeeling.surprised);
      expect([OwnerFeeling.happy, OwnerFeeling.love], contains(seq[1]));
    });

    test('v5 pain/sadness: surprised -> sad', () {
      expect(go(SulkState(), '나 오늘 배 아파 ㅠㅠ')[1], OwnerFeeling.sad);
    });

    test('v5 question: thinking first', () {
      expect(go(SulkState(), '7 더하기 8?').first, OwnerFeeling.thinking);
    });

    test('two loving words lift a sulk; praise does not', () {
      final st = SulkState();
      go(st, '바보야');
      expect(go(st, '너 귀엽다').first, OwnerFeeling.surprised);
      expect(st.sulking, isTrue);
      expect(go(st, '사랑해'), [OwnerFeeling.sulky]);
      expect(go(st, '사랑해').last, OwnerFeeling.love);
      expect(st.sulking, isFalse);
    });

    test('json round trip', () {
      final st = SulkState();
      go(st, '바보야');
      go(st, '사랑해');
      final back = SulkState.fromJson(st.toJson());
      expect(back.sulking, isTrue);
      expect(back.niceCount, 1);
    });
  });

  group('listening preview', () {
    test('maps typing text to a feeling', () {
      expect(OwnerFeelings.listeningPreview(''), [OwnerFeeling.neutral]);
      expect(OwnerFeelings.listeningPreview('오늘 뭐 해?'), [OwnerFeeling.thinking]);
      expect(OwnerFeelings.listeningPreview('ㅋㅋㅋ'), [OwnerFeeling.happy]);
      expect(OwnerFeelings.listeningPreview('사랑해'), [OwnerFeeling.surprised]);
      expect(OwnerFeelings.listeningPreview('그냥 평범한 날'), [OwnerFeeling.curious]);
      expect(OwnerFeelings.listeningPreview('안녕', sulking: true), [OwnerFeeling.sulky]);
    });
  });
}
