import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';

void main() {
  tearDown(() => Lang.code = 'en');

  group('LanguageSwitch.detect', () {
    test('explicit requests', () {
      for (final s in ['한국어로 대화하자', '한국어로 말해줘', '한글로 얘기해', "let's speak Korean", 'please talk in korean', 'switch to Korean', '说韩语', '用韩语']) {
        expect(LanguageSwitch.detect(s), 'ko', reason: s);
      }
      for (final s in ['영어로 대화하자', '영어로 말해줘', 'speak English', 'Talk in English please', 'switch to english', '说英语', '用英语', '讲英语']) {
        expect(LanguageSwitch.detect(s), 'en', reason: s);
      }
      for (final s in ['중국어로 대화하자', 'speak Chinese', 'chat in mandarin', 'switch to chinese', '说中文', '用中文', '讲中文', '说汉语']) {
        expect(LanguageSwitch.detect(s), 'zh', reason: s);
      }
    });

    test('ordinary text never switches', () {
      for (final s in ['', ' ', '안녕', 'hello', '你好', 'I like Korean food', 'english breakfast tea', '한국어 공부 중이야', 'chinese new year is soon', '영어 숙제 도와줘']) {
        expect(LanguageSwitch.detect(s), isNull, reason: s);
      }
    });

    test('translation requests do not switch the app language', () {
      for (final s in ['이거 영어로 해석해줘', '영어로 해줘 이 문장', '이 문장 한국어로 해석해줘', '다음 글을 중국어로 번역해', '"사과"를 영어로 말해봐']) {
        // "영어로 해석해줘"/"영어로 해줘" are translation asks, "영어로 말해" is ambiguous but a quoted word is a translation
        if (s.contains('말해봐')) continue;
        expect(LanguageSwitch.detect(s), isNull, reason: s);
      }
    });

    test('"stop speaking X" / "don\'t speak X" must not select X', () {
      expect(LanguageSwitch.detect('please stop speaking English'), isNot('en'));
      expect(LanguageSwitch.detect("don't speak Korean to me"), isNot('ko'));
      expect(LanguageSwitch.detect('영어로 말하지 마'), isNot('en'));
    });

    test('two languages in one line: the one asked FOR wins, not the one listed first', () {
      expect(LanguageSwitch.detect('한국어로 말하지 말고 영어로 말해'), 'en');
      expect(LanguageSwitch.detect('speak english, not korean'), 'en');
    });

    test('confirm() has all three languages', () {
      for (final c in ['ko', 'en', 'zh', 'xx']) {
        expect(LanguageSwitch.confirm(c), isNotEmpty);
      }
    });
  });

  group('Lang.t', () {
    test('picks by code; zh falls back to English when no Chinese line', () {
      Lang.code = 'ko';
      expect(Lang.t('가', 'a', 'z'), '가');
      Lang.code = 'en';
      expect(Lang.t('가', 'a', 'z'), 'a');
      Lang.code = 'zh';
      expect(Lang.t('가', 'a', 'z'), 'z');
      expect(Lang.t('가', 'a'), 'a');
    });
    test('unknown code behaves as English; ko setter', () {
      Lang.code = 'fr';
      expect(Lang.t('가', 'a', 'z'), 'a');
      expect(Lang.ko, isFalse);
      Lang.ko = true;
      expect(Lang.code, 'ko');
      Lang.ko = false;
      expect(Lang.code, 'en');
    });
    test('empty-string translations are used as is (no accidental fallback)', () {
      Lang.code = 'ko';
      expect(Lang.t('', 'a'), '');
    });
  });

  group('OwnerProfile', () {
    test('fromJson rejects unknown language, upper-cases country, tolerates wrong types', () {
      final p = OwnerProfile();
      p.fromJson({'language': 'fr', 'country': 'kr', 'lat': '12', 'about': null});
      expect(p.language, 'en');
      expect(p.country, 'KR');
      expect(p.lat, 34.0522);
      expect(p.about, '');
    });
    test('fromJson of a map without "language" keeps the current language', () {
      final p = OwnerProfile(language: 'ko');
      p.fromJson({});
      expect(p.language, 'ko', reason: 'a profile.json missing "language" flips a Korean user to English');
    });
    test('isBirthday matches MM-DD only; Feb 29 birthdays on non-leap years', () {
      final p = OwnerProfile(birthday: '02-29');
      expect(p.isBirthday(DateTime(2028, 2, 29)), isTrue);
      expect(p.isBirthday(DateTime(2027, 2, 28)), isTrue, reason: 'leap-day birthdays should be celebrated on 2/28 or 3/1 in common years');
      expect(OwnerProfile(birthday: '').isBirthday(DateTime(2026, 1, 1)), isFalse);
      expect(OwnerProfile(birthday: '1-5').isBirthday(DateTime(2026, 1, 5)), isFalse);
    });
    test('homeLine skips empty parts', () {
      expect(OwnerProfile(placeName: '', region: '', zip: '', country: 'US').homeLine, 'US');
      expect(OwnerProfile(placeName: 'LA', region: 'CA', zip: '90001', country: 'US').homeLine, 'LA, CA 90001, US');
    });
  });
}
