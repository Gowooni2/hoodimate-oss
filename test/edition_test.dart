import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/edition.dart';
import 'package:hoodimong/services/chat_ai.dart';

void main() {
  test('feature gates follow the edition', () {
    final full = Ed.current != Edition.lite;
    expect(Ed.agentTools && Ed.sync && Ed.cloudVoice && Ed.calendar, full);
    expect(Ed.market, Ed.current == Edition.personal);
    expect(Ed.packSales, PackSales.none);
  });

  test('cloud AI needs consent once, local AI never', () {
    final ai = ChatAi();
    final cloud = ai.providers.firstWhere((p) => !p.isLocal);
    final local = ai.providers.firstWhere((p) => p.isLocal);
    expect(ai.needsConsent(cloud), isTrue);
    expect(ai.needsConsent(local), isFalse);
    ai.consented.add(cloud.id);
    expect(ai.needsConsent(cloud), isFalse);
  });

  test('consent given to older wording is asked again', () {
    expect(ChatAi.consentsFrom({'consented': ['gemini']}), isEmpty); // v1, before ZIP was sent
    expect(ChatAi.consentsFrom({'consented': ['gemini'], 'consentVersion': ChatAi.consentVersion}), {'gemini'});
  });
}
