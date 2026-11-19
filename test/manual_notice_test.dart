import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/models/manual.dart';
import 'package:hoodimong/models/profile.dart';

void main() {
  test('manual says up front what this edition cannot do', () {
    for (final l in ['ko', 'en', 'zh']) {
      Lang.code = l;
      expect(Manual.notice, isNotEmpty);
      expect(Manual.text, contains(Manual.notice));
      // the no-weather line appears exactly where weather is off
      final noWeather = Manual.notice.split('\n').length >= (Ed.market ? 3 : 4);
      expect(noWeather, !Ed.noncommercialApis);
    }
    Lang.code = 'en';
  });
}
