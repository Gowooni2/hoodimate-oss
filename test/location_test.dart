import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/agent_tools.dart';

void main() {
  test('home line reads like an address', () {
    final p = OwnerProfile(placeName: 'Springfield', region: 'Illinois', zip: '62701');
    expect(p.homeLine, 'Springfield, Illinois 62701, US');
    p.fromJson({'placeName': 'Seoul', 'region': 'Seoul', 'zip': '', 'country': 'kr'});
    expect(p.homeLine, 'Seoul, Seoul, KR');
  });

  test('searches use the owner country, not the chat language', () {
    expect(AgentTools.ddgRegion('US'), 'us-en');
    expect(AgentTools.ddgRegion('kr'), 'kr-kr');
    expect(AgentTools.ddgRegion('FR'), 'wt-wt');
  });
}
