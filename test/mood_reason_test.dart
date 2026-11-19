import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoodimong/models/pet_state.dart';
import 'package:hoodimong/models/profile.dart';
import 'package:hoodimong/services/market_service.dart';
import 'package:hoodimong/services/pet_brain.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

// Owner (2026-10-12): the eyes looked down while the care tab said
// "기분 좋아요!" — the pet has to say it's the market.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late PetBrain b;

  setUp(() {
    for (final c in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    Lang.code = 'ko';
    tmp = Directory.systemTemp.createTempSync('mood_reason');
    PathProviderPlatform.instance = _Paths(tmp.path);
    b = PetBrain();
    b.hunger = 66;
    b.happiness = 87;
    b.health = 85;
    b.energy = 61;
  });
  tearDown(() {
    Lang.code = 'en';
    b.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  MarketInfo info({double coin = 0, double stock = 0}) => MarketInfo(
        [CoinQuote(Holding('bitcoin', 'BTC', 'Bitcoin', 1), 100, coin)],
        StockQuote('SKHY', 162, stock, true, name: 'SK hynix'),
        DateTime.now(),
      );

  test('market drop: sad eyes and the care tab says why', () {
    b.market.current = info(coin: -6.9, stock: -4.0);
    expect(b.baseMood(), PetMood.sad);
    expect(b.needText(), contains('시세가 떨어져서'));
    expect(b.needText(), contains('코인 -6.9%'));
    expect(b.needText(), isNot(contains('SK hynix')), reason: 'stock -4 % is not past the line');
  });

  test('market up: excited, with the reason', () {
    b.market.current = info(stock: 7.5);
    expect(b.baseMood(), PetMood.celebrating);
    expect(b.needText(), contains('시세가 올라서'));
    expect(b.needText(), contains('SK hynix +7.5%'));
  });

  test('a care need still comes first', () {
    b.market.current = info(coin: -8);
    b.hunger = 10;
    expect(b.needText(), contains('배고파요'));
  });

  test('calm market: feeling great', () {
    b.market.current = info(coin: -1);
    expect(b.needText(), contains('기분 좋아요'));
  });
}
