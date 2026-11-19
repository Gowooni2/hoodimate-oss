import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/services/notes.dart';

void main() {
  test('English note commands', () {
    expect(Notes.parseCommand('save this to my notes'), '');
    expect(Notes.parseCommand('Add buy milk to my notes'), 'buy milk');
    expect(Notes.parseCommand('note that down'), '');
    expect(Notes.parseCommand('/note call mom'), 'call mom');
    expect(Notes.parseCommand('what are notes for?'), isNull);
  });
}
