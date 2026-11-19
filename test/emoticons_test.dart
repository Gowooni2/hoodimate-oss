import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/emoticons.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';

void main() {
  test('basic pack: 25 unique emoticons with captions in three languages', () {
    final items = Emoticons.basic.items;
    expect(items.length, 25);
    expect(items.map((e) => e.id).toSet().length, 25);
    for (final e in items) {
      expect(e.ko.isNotEmpty && e.en.isNotEmpty && e.zh.isNotEmpty, isTrue, reason: e.id);
    }
    Lang.code = 'ko';
    expect(Emoticons.byId('yummy')!.caption, '냠냠!');
    Lang.code = 'en';
    expect(Emoticons.byId('yummy')!.caption, 'Yum!');
  });

  test('every mood/reply mapping points to a real emoticon', () {
    for (final m in PetMood.values) {
      final id = Emoticons.forMood(m);
      if (id != null) expect(Emoticons.byId(id), isNotNull, reason: '$m');
    }
    for (final e in Emoticons.basic.items) {
      expect(Emoticons.byId(Emoticons.replyTo(e.id)), isNotNull, reason: e.id);
    }
  });
}
