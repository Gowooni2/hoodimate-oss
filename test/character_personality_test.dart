import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/character.dart';
import 'package:hoodimong/models/profile.dart';

void main() {
  test('Mongsil has its canon personality in ko, en and zh', () {
    // The lite tree ships Mongsil only.
    final j = jsonDecode(File('assets/characters/mongsil/character.json').readAsStringSync()) as Map;
    final c = Character.fromJson(j, 'mongsil');
    for (final l in ['ko', 'en', 'zh']) {
      Lang.code = l;
      expect(c.personalityText, isNotEmpty, reason: 'mongsil $l');
    }
    Lang.code = 'en';
  });
}
