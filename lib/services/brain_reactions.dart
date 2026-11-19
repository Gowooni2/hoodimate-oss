part of 'pet_brain.dart';

/// Weather, market and news reactions.
extension PetBrainReactions on PetBrain {
  // ---------- weather ----------


  /// Most notable thing about the weather right now (null = nothing to say).
  String? _weatherKey(WeatherInfo w) {
    if (w.sky == Sky.thunder) return 'thunder';
    if (w.sky == Sky.snow) return 'snow';
    if (w.sky == Sky.rain) return 'rain';
    if (w.sky == Sky.drizzle) return 'drizzle';
    if (w.isHot) return 'hot';
    if (w.isCold) return 'cold';
    if (w.isWindy) return 'windy';
    if (w.isLovely) return 'lovely';
    if (w.sky == Sky.fog) return 'fog';
    return null;
  }

  /// Called after every refresh: daily briefing once a day, and a comment
  /// (with voice where recorded) whenever the situation changes.
  void _onWeather({bool startup = false}) {
    final w = weather.current;
    _notify();
    if (w == null || thinking || listening) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_briefedOn != today && (startup || DateTime.now().hour >= 7)) {
      _briefedOn = today;
      _lastSituation = w.situation;
      final umbrella = w.rainChance >= 60
          ? Lang.t(' 오늘 비 소식 있어. 외출할 때 우산 챙겨 가!', ' Rain is on the way, take an umbrella when you go out!',
              ' 今天有雨，出门记得带伞！')
          : '';
      _say(
          Lang.t(
              '오늘 ${w.city} ${w.emoji} ${w.skyKo}, 지금 ${w.tempF}°F, '
                  '${w.minF}~${w.maxF}°F야. '
                  '비 올 확률 ${w.rainChance}%.$umbrella',
              'Today in ${w.city} ${w.emoji} ${w.skyKo}, ${w.tempF}°F now, '
                  '${w.minF}~${w.maxF}°F. '
                  'Rain chance ${w.rainChance}%.$umbrella',
              '今天${w.city} ${w.emoji} ${w.skyKo}，现在 ${w.tempF}°F，'
                  '${w.minF}~${w.maxF}°F。'
                  '降雨概率 ${w.rainChance}%。$umbrella'),
          mood: w.isRain || umbrella.isNotEmpty ? PetMood.rain : PetMood.talking,
          sticker: umbrella.isNotEmpty ? 'umbrella' : null);
      if (umbrella.isNotEmpty) _act('umbrella');
      _save();
      return;
    }
    if (w.situation == _lastSituation) return;
    _lastSituation = w.situation;
    final key = _weatherKey(w);
    if (key == null || sleeping) return;
    _weatherSaidAt = DateTime.now();
    final act = Reactions.weatherAction[key];
    if (act != null) _act(act);
    final line = Reactions.weatherLine(key, w, Random());
    _say(line,
        // rain: umbrella, gloomy or splashy, whatever the line says
        sticker: w.isRain ? Emoticons.forReply(line, PetMood.rain) : null,
        mood: key == 'thunder'
            ? PetMood.sad
            : key == 'hot'
                ? PetMood.hot
                : w.isRain
                    ? PetMood.rain
                    : key == 'lovely'
                        ? PetMood.happy
                        : PetMood.talking);
    if (key == 'rain' || key == 'drizzle') cues.play('rain', force: true);
    if (key == 'hot') cues.play('hot', force: true);
    if (key == 'lovely') cues.play('happy');
  }

  // ---------- market briefing (10:00 and 17:00 local) ----------


  /// Called every minute: gives each briefing once a day, up to 3 h late
  /// (e.g. if the Mac was asleep at 10:00).
  Future<void> _maybeMarketBrief() async {
    final now = DateTime.now();
    final today = now.toIso8601String().substring(0, 10);
    for (final h in PetBrain.briefHours) {
      if (now.hour < h || now.hour >= h + 3) continue;
      if (_briefed['$h'] == today) continue;
      _briefed['$h'] = today;
      _save();
      await marketBrief(morning: h == 10);
    }
  }

  /// Market (+ weather in the morning) briefing: short bubble, full detail
  /// in the 일상 chat thread. Information only, no advice.
  Future<void> marketBrief({bool morning = false}) async {
    if (!Ed.market) return;
    await market.refresh();
    final m = market.current;
    if (m == null) return;
    final w = weather.current;
    final general = memory.projects.first;
    final detail = [
      if (morning && w != null)
        Lang.t('☀️ 오늘 날씨: ${w.summary}', '☀️ Today\'s weather: ${w.summary}', '☀️ 今天天气：${w.summary}'),
      m.report(),
    ].join('\n\n');
    memory.addMessage(general,
        ChatMessage(text: detail, fromUser: false, at: DateTime.now()));
    memory.save();
    _act('mail'); // a letter with today's numbers
    final tier = Reactions.marketTier(m);
    if (tier != 0) {
      _marketDay = DateTime.now().toIso8601String().substring(0, 10);
      _marketShown = tier;
      _reactToMarket(tier, m);
      return;
    }
    _say(
        Lang.t('${morning ? '오전' : '오후'} 브리핑! ${m.headline}',
            '${morning ? 'Morning' : 'Afternoon'} briefing! ${m.headline}',
            '${morning ? '上午' : '下午'}简报！${m.headline}'),
        mood: PetMood.talking);
  }

  // ---------- news (Google News RSS) ----------

  List<String> get _newsTopics => [
        if (market.stockName.isNotEmpty) market.stockName
        else if (market.stockSymbol.isNotEmpty) market.stockSymbol,
        ...market.holdings
            .where((h) => h.symbol != 'PYUSD') // stablecoin: no news value
            .map((h) => '${h.name} crypto'),
      ];

  Future<void> _checkNews() async {
    if (demo) return;
    if (sleeping || thinking || listening || alarmText != null) return;
    final items = await news.fetch(_newsTopics);
    final now = DateTime.now();
    final n = news.pickBig(items, now);
    if (n == null || bubbleText != null || thinking) return;
    news.markShown(n, now);
    final topic = n.topic.replaceAll(' crypto', '');
    _act('news'); // reading the paper, eyes go wide
    _say(Lang.t('📰 깜짝 뉴스! [$topic] ${n.title}', '📰 Breaking news! [$topic] ${n.title}', '📰 突发新闻！[$topic] ${n.title}'),
        mood: PetMood.talking);
    memory.addMessage(
        memory.projects.first,
        ChatMessage(
            // Title and source only: the Google News redirect URL is very
            // long and chat bubbles can't open links anyway.
            text: '📰 [$topic] ${n.title}${n.source.isEmpty ? '' : ' (${n.source})'}',
            fromUser: false,
            at: now));
    memory.save();
  }

  // ---------- market & weather reactions ----------


  /// After each 15-min market refresh: react when the portfolio moves
  /// into a stronger tier than already mentioned today (or flips sign).
  void _onMarket() {
    _notify();
    final m = market.current;
    if (m == null || thinking || listening || sleeping) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_marketDay != today) {
      _marketDay = today;
      _marketShown = 0;
    }
    final tier = Reactions.marketTier(m);
    if (tier == 0) return;
    final flipped = tier.sign != _marketShown.sign;
    if (!flipped && tier.abs() <= _marketShown.abs()) return;
    _marketShown = tier;
    _reactToMarket(tier, m);
  }

  void _reactToMarket(int tier, MarketInfo m) {
    final act = Reactions.marketAction[tier];
    if (act != null) _act(act);
    _say(Reactions.marketLine(tier, m, Random()),
        mood: switch (tier) {
          -2 || -1 => PetMood.sad,
          2 => PetMood.celebrating,
          _ => PetMood.happy,
        });
    if (tier == -2) cues.play('sad', force: true);
    if (tier == 2) cues.play('celebrating', force: true);
  }

  /// While it stays hot/cold, a reminder comment about every 45 min.
  void _maybeWeatherNag() {
    final w = weather.current;
    if (w == null || !(w.isHot || w.isCold)) return;
    if (bubbleText != null || thinking || listening || sleeping) return;
    final last = _weatherSaidAt;
    if (last != null && DateTime.now().difference(last).inMinutes < 45) return;
    _weatherSaidAt = DateTime.now();
    final key = w.isHot ? 'hot' : 'cold';
    _act(Reactions.weatherAction[key]!);
    _say(Reactions.weatherLine(key, w, Random()),
        mood: w.isHot ? PetMood.hot : PetMood.sad);
  }
}
