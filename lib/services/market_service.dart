import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/profile.dart';

/// One coin the owner holds (Coinbase). Quantities are stored only on this
/// Mac in portfolio.json; price lookups send coin IDs only.
class Holding {
  final String id; // CoinGecko id
  final String symbol;
  final String name;
  double qty;
  Holding(this.id, this.symbol, this.name, this.qty);

  Map<String, dynamic> toJson() =>
      {'id': id, 'symbol': symbol, 'name': name, 'qty': qty};
  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
      j['id'].toString(),
      j['symbol'].toString(),
      j['name'].toString(),
      (j['qty'] as num).toDouble());
}

/// No coins by default. The owner's holdings live only in portfolio.json
/// on their own machine (edit it, or a future settings screen).
List<Holding> defaultHoldings() => [];

class CoinQuote {
  final Holding h;
  final double price;
  final double change24h; // %
  CoinQuote(this.h, this.price, this.change24h);
  double get value => h.qty * price;
}

/// US-listed stock quote (USD).
class StockQuote {
  final String symbol; // Yahoo symbol, e.g. AAPL
  final double price;
  final double changePct;
  final bool open;
  final String name; // display name ("Apple"); defaults to the symbol
  StockQuote(this.symbol, this.price, this.changePct, this.open, {String? name})
      : name = name ?? symbol;
}

class MarketInfo {
  final List<CoinQuote> coins;
  final StockQuote? stock;
  final DateTime at;
  MarketInfo(this.coins, this.stock, this.at);

  double get totalUsd => coins.fold(0, (a, c) => a + c.value);

  /// Portfolio 24h change, value-weighted.
  double get totalChangePct {
    double now = 0, before = 0;
    for (final c in coins) {
      now += c.value;
      before += c.value / (1 + c.change24h / 100);
    }
    return before == 0 ? 0 : (now / before - 1) * 100;
  }

  bool get crash => totalChangePct <= -5 || (stock?.changePct ?? 0) <= -5;
  bool get moon => totalChangePct >= 5 || (stock?.changePct ?? 0) >= 5;

  static String pct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  static String usd(double v) =>
      v >= 1 ? '\$${v.toStringAsFixed(2)}' : '\$${v.toStringAsPrecision(3)}';

  /// Short line for the bubble.
  String get headline =>
      '${Lang.t('코인', 'Crypto', '加密币')} ${usd(totalUsd)} (${pct(totalChangePct)})'
      '${stock == null ? '' : ' · ${stock!.symbol} ${usd(stock!.price)} (${pct(stock!.changePct)})'}';

  /// Full briefing for the chat log.
  String report() {
    final sorted = [...coins]..sort((a, b) => b.value.compareTo(a.value));
    final movers = [...coins]
      ..sort((a, b) => b.change24h.abs().compareTo(a.change24h.abs()));
    final lines = <String>[
      Lang.t('📈 시장 브리핑', '📈 Market briefing', '📈 市场简报'),
      if (stock != null)
        '${stock!.name} ${stock!.symbol} ${usd(stock!.price)} (${pct(stock!.changePct)})'
            '${stock!.open ? Lang.t(' · 장중', ' · market open', ' · 盘中') : Lang.t(' · 장 마감 기준', ' · at last close', ' · 按收盘价')}',
      Lang.t('코인 합계 ${usd(totalUsd)} (24시간 ${pct(totalChangePct)})',
          'Crypto total ${usd(totalUsd)} (24h ${pct(totalChangePct)})', '加密币合计 ${usd(totalUsd)}（24小时 ${pct(totalChangePct)}）'),
      for (final c in sorted)
        '· ${c.h.symbol} ${usd(c.value)} (${pct(c.change24h)})',
      if (movers.isNotEmpty && movers.first.change24h.abs() >= 3)
        Lang.t('가장 크게 움직인 건 ${movers.first.h.symbol} ${pct(movers.first.change24h)}!',
            'Biggest mover: ${movers.first.h.symbol} ${pct(movers.first.change24h)}!', '波动最大的是 ${movers.first.h.symbol} ${pct(movers.first.change24h)}！'),
      Lang.t('※ 정보 안내일 뿐 투자 조언은 아니야.',
          '* Just info, not investment advice.', '※ 仅为信息提示，不构成投资建议。'),
    ];
    return lines.join('\n');
  }
}

class MarketService {
  MarketInfo? current;
  List<Holding> holdings = defaultHoldings();

  /// The one stock to watch (from the owner profile). Empty = none.
  String stockSymbol = '';
  String stockName = '';

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/portfolio.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as List;
        holdings =
            j.whereType<Map<String, dynamic>>().map(Holding.fromJson).toList();
      } else {
        await save();
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f
          .writeAsString(jsonEncode(holdings.map((h) => h.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> refresh() async {
    final coins = <CoinQuote>[];
    try {
      final ids = holdings.map((h) => h.id).join(',');
      final r = await http
          .get(Uri.parse('https://api.coingecko.com/api/v3/simple/price'
              '?ids=$ids&vs_currencies=usd&include_24hr_change=true'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        for (final h in holdings) {
          final q = j[h.id];
          if (q is Map) {
            coins.add(CoinQuote(h, (q['usd'] as num).toDouble(),
                (q['usd_24h_change'] as num?)?.toDouble() ?? 0));
          }
        }
      }
    } catch (_) {}
    final stock = await _stock();
    if (coins.isEmpty && stock == null) return; // keep last known
    current = MarketInfo(coins.isEmpty ? (current?.coins ?? []) : coins,
        stock ?? current?.stock, DateTime.now());
  }

  /// The watched stock via the Yahoo chart API.
  Future<StockQuote?> _stock() async {
    final symbol = stockSymbol.trim();
    if (symbol.isEmpty) return null;
    try {
      final r = await http.get(
          Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/'
              '$symbol?range=1d&interval=1d'),
          headers: {
            'User-Agent': 'Mozilla/5.0'
          }).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final m = (jsonDecode(r.body)['chart']['result'] as List).first['meta'];
      final p = (m['regularMarketPrice'] as num).toDouble();
      final prev = (m['chartPreviousClose'] as num?)?.toDouble() ?? p;
      final reg = m['currentTradingPeriod']?['regular'];
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final open = reg != null &&
          now >= (reg['start'] as num) &&
          now < (reg['end'] as num);
      return StockQuote(symbol, p, prev == 0 ? 0 : (p / prev - 1) * 100, open,
          name: stockName.isEmpty ? symbol : stockName);
    } catch (_) {
      return null;
    }
  }
}
