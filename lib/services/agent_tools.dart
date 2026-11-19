import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../edition.dart';

/// One tool the AI may call: JSON-schema parameters, run on this Mac.
class AgentTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<String> Function(Map<String, dynamic> args) run;

  /// Short "doing it" label for the speech bubble.
  final String Function() busyLabel;

  AgentTool(this.name, this.description, this.parameters, this.run, this.busyLabel);

  Map<String, dynamic> get openAi => {
        'type': 'function',
        'function': {'name': name, 'description': description, 'parameters': parameters},
      };

  Map<String, dynamic> get anthropic =>
      {'name': name, 'description': description, 'input_schema': parameters};
}

/// What the pet can do for the owner when the AI asks: search the web,
/// read a page, check weather, alarms, notes and the Mac calendar.
/// The app-side actions come in as callbacks from PetBrain.
class AgentTools {
  final String Function(String command) reminder; // "/remind ..." -> reply
  final Future<String> Function(String text) saveNote;

  /// Brave Search API key (optional). Without it, DuckDuckGo's HTML page.
  String braveKey = '';
  bool calendarEnabled = true;

  static const _calendar = MethodChannel('hoodimong/calendar');

  AgentTools({required this.reminder, required this.saveNote});

  /// Models often drop the "in": "10 minutes" -> "in 10 minutes".
  static String _when(String w) => RegExp(r'^\s*\d+\s*(min|hour|hr|sec)', caseSensitive: false).hasMatch(w) ? 'in ${w.trim()}' : w;

  static Map<String, dynamic> _obj(Map<String, dynamic> props, [List<String> req = const []]) =>
      {'type': 'object', 'properties': props, 'required': req};
  static Map<String, dynamic> _s(String d) => {'type': 'string', 'description': d};

  /// A tool argument as trimmed text; missing / null becomes '' (never the word "null").
  static String _arg(Map<String, dynamic> a, String k) {
    final v = a[k];
    return v == null ? '' : '$v'.trim();
  }

  List<AgentTool> get all => [
        AgentTool('web_search', 'Search the web for current information. Returns titles, links and snippets.',
            _obj({'query': _s('search words, in the language of the owner\'s country (English for the US), not the chat language')}, ['query']), (a) async {
              final q = _arg(a, 'query');
              if (q.isEmpty) return 'error: query is empty';
              return webSearch(q);
            },
            () => Lang.t('🔎 찾아보는 중...', '🔎 Searching...', '🔎 搜索中...')),
        AgentTool('read_webpage', 'Read the main text of a web page (first ~6000 characters).',
            _obj({'url': _s('http(s) link')}, ['url']), (a) => readPage(_arg(a, 'url')),
            () => Lang.t('📄 읽는 중...', '📄 Reading...', '📄 阅读中...')),
        if (Ed.noncommercialApis) AgentTool('get_weather', 'Current weather and 3-day forecast (°F) for a place, or the owner\'s home if place is empty.',
            _obj({'place': _s('city name, optional')}), (a) => weather(_arg(a, 'place')),
            () => Lang.t('🌤 날씨 보는 중...', '🌤 Checking weather...', '🌤 查天气...')),
        AgentTool('set_reminder',
            'Set an alarm/reminder in the app. when must be one of these English forms whatever language the owner speaks: "in 10 minutes", "in 2 hours", "18:30" (24-hour clock), "tomorrow 15:00", "every day 9:00". Weekday names are not supported. If the result says it could not understand the time, tell the owner and ask for a clearer time; never claim it is set.',
            _obj({'when': _s('time, e.g. "in 10 minutes" or "tomorrow 8:00"'), 'what': _s('what to remind, in the owner\'s language')}, ['when', 'what']),
            (a) async {
              final when = _arg(a, 'when');
              if (when.isEmpty) return 'error: "when" is missing; ask the owner for a time';
              return reminder('/remind ${_when(when)} ${_arg(a, 'what')}'.trim());
            },
            () => Lang.t('⏰ 알람 맞추는 중...', '⏰ Setting alarm...', '⏰ 设闹钟...')),
        AgentTool('list_reminders', 'List the alarms/reminders that are set.', _obj({}),
            (a) async => reminder('/remind list'), () => Lang.t('⏰ 확인 중...', '⏰ Checking...', '⏰ 查看中...')),
        AgentTool('cancel_reminder', 'Cancel a reminder by its number from list_reminders, or "all".',
            _obj({'which': _s('number or "all"')}, ['which']), (a) async => reminder('/remind cancel ${_arg(a, 'which')}'.trim()),
            () => Lang.t('⏰ 지우는 중...', '⏰ Cancelling...', '⏰ 取消中...')),
        AgentTool('save_note', 'Save a note to the owner\'s Obsidian notes for the current chat room.',
            _obj({'text': _s('note text')}, ['text']), (a) => saveNote(_arg(a, 'text')),
            () => Lang.t('📝 적는 중...', '📝 Writing...', '📝 记录中...')),
        if (calendarEnabled) ...[
          AgentTool('calendar_events', 'Events on the owner\'s Mac calendars for the next N days (default 7).',
              _obj({'days': {'type': 'integer', 'description': '1-31'}}), (a) => calendarEvents(a['days']),
              () => Lang.t('📅 일정 보는 중...', '📅 Checking calendar...', '📅 查看日程...')),
          AgentTool('add_calendar_event',
              'Add an event to the owner\'s default Mac calendar. Only when the owner clearly asks. start/end: ISO 8601 local time.',
              _obj({'title': _s('event title'), 'start': _s('e.g. 2026-10-09T15:00'), 'end': _s('optional end'),
                    'location': _s('optional')}, ['title', 'start']),
              addCalendarEvent, () => Lang.t('📅 일정 넣는 중...', '📅 Adding event...', '📅 添加日程...')),
        ],
      ];

  Future<String> call(String name, Map<String, dynamic> args) async {
    final t = all.where((t) => t.name == name).firstOrNull;
    if (t == null) return 'error: unknown tool $name';
    try {
      final out = await t.run(args);
      return out.length > 8000 ? '${out.substring(0, 8000)}…' : out;
    } catch (e) {
      return 'error: $e';
    }
  }

  String busyLabel(String name) =>
      all.where((t) => t.name == name).firstOrNull?.busyLabel() ?? '…';

  // ---------- web ----------

  static const _ua = {'User-Agent': 'Mozilla/5.0 (Macintosh) Hoodimate/0.4'};

  Future<String> webSearch(String q) async {
    if (braveKey.isEmpty && !Ed.noncommercialApis) {
      return 'Web search needs a Brave Search API key (Settings > AI tools).';
    }
    if (braveKey.isNotEmpty) {
      final r = await http.get(
          Uri.parse('https://api.search.brave.com/res/v1/web/search?count=6&country=${country.toLowerCase()}&q=${Uri.encodeQueryComponent(q)}'),
          headers: {'Accept': 'application/json', 'X-Subscription-Token': braveKey}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return 'error: search failed (HTTP ${r.statusCode})';
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final web = body is Map ? body['web'] : null;
      final res = (web is Map ? web['results'] as List? : null) ?? [];
      if (res.isEmpty) return 'no results';
      return res.whereType<Map>().take(6).map((x) => '- ${x['title'] ?? ''}\n  ${x['url'] ?? ''}\n  ${_strip('${x['description'] ?? ''}')}').join('\n');
    }
    final r = await http.post(Uri.parse('https://html.duckduckgo.com/html/'),
        headers: {..._ua, 'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'q=${Uri.encodeQueryComponent(q)}&kl=${ddgRegion(country)}').timeout(const Duration(seconds: 12));
    return parseDuckDuckGo(utf8.decode(r.bodyBytes, allowMalformed: true));
  }

  /// DuckDuckGo region for a country code (results from that country).
  static String ddgRegion(String country) => switch (country.trim().toUpperCase()) {
        'US' => 'us-en',
        'KR' => 'kr-kr',
        'CN' => 'cn-zh',
        'TW' => 'tw-tzh',
        'JP' => 'jp-jp',
        'GB' || 'UK' => 'uk-en',
        'CA' => 'ca-en',
        _ => 'wt-wt',
      };

  /// DuckDuckGo HTML results -> "- title / link / snippet" lines.
  static String parseDuckDuckGo(String html) {
    final out = <String>[];
    // the result block's class list ends with result__body
    final blocks = html.split(RegExp(r'class="[^"]*\bresult__body\b[^"]*"')).skip(1);
    for (final b in blocks.take(6)) {
      final a = RegExp(r'class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>').firstMatch(b);
      if (a == null) continue;
      var link = _unescape(a.group(1)!);
      final uddg = RegExp(r'uddg=([^&]+)').firstMatch(link);
      if (uddg != null) link = Uri.decodeComponent(uddg.group(1)!);
      final sn = RegExp(r'class="result__snippet"[^>]*>([\s\S]*?)</a>').firstMatch(b);
      out.add('- ${_strip(a.group(2)!)}\n  $link\n  ${_strip(sn?.group(1) ?? '')}');
    }
    return out.isEmpty ? 'no results' : out.join('\n');
  }

  Future<String> readPage(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return 'error: not a web link';
    if (_isPrivateHost(u.host)) return 'error: that address is on this Mac or its local network';
    final r = await http.get(u, headers: _ua).timeout(const Duration(seconds: 15));
    final html = utf8.decode(r.bodyBytes, allowMalformed: true);
    final title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1);
    final text = pageText(html);
    return '${title != null ? 'Title: ${_strip(title)}\n' : ''}${text.length > 6000 ? text.substring(0, 6000) : text}';
  }

  /// Loopback, link-local and private-range literals and local names. A page
  /// the model is steered to must not be able to read the owner's router,
  /// NAS or cloud metadata and hand it to a cloud AI.
  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal') || !h.contains('.') && !h.contains(':')) {
      return true;
    }
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal) return true;
    if (ip.type == InternetAddressType.IPv4) {
      final b = ip.rawAddress;
      return b[0] == 10 || b[0] == 0 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    final b = ip.rawAddress;
    return (b[0] & 0xfe) == 0xfc || ip.isMulticast; // fc00::/7
  }

  /// HTML -> readable text (scripts, styles and tags removed).
  static String pageText(String html) => _strip(html
      .replaceAll(RegExp(r'<(script|style|noscript|svg|nav|footer|header)[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<(br|p|div|li|h[1-6]|tr)[^>]*>', caseSensitive: false), '\n'));

  static String _strip(String s) => _unescape(s.replaceAll(RegExp(r'<[^>]+>'), ''))
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .trim();

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');

  // ---------- weather (Open-Meteo, °F) ----------

  /// Home coordinates from the profile, used when no place is given.
  /// Owner's country code (profile) so searches find local results.
  String country = 'US';

  String homeName = '';
  double homeLat = 0, homeLon = 0;

  Future<String> weather(String place) async {
    var name = homeName, lat = homeLat, lon = homeLon;
    if (place.trim().isNotEmpty) {
      final g = await http
          .get(Uri.parse('https://geocoding-api.open-meteo.com/v1/search?count=1&name=${Uri.encodeQueryComponent(place)}'))
          .timeout(const Duration(seconds: 10));
      final res = (jsonDecode(g.body)['results'] as List?) ?? [];
      if (res.isEmpty) return 'place not found: $place';
      final m = res.first as Map;
      name = '${m['name']}, ${m['country'] ?? ''}';
      lat = (m['latitude'] as num).toDouble();
      lon = (m['longitude'] as num).toDouble();
    }
    final r = await http.get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
        '&forecast_days=3&timezone=auto&temperature_unit=fahrenheit&wind_speed_unit=mph')).timeout(const Duration(seconds: 10));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final c = j['current'] as Map, d = j['daily'] as Map;
    final days = [
      for (var i = 0; i < (d['time'] as List).length; i++)
        '${d['time'][i]}: ${d['temperature_2m_min'][i]}–${d['temperature_2m_max'][i]}°F, '
            'rain ${d['precipitation_probability_max'][i]}%, code ${d['weather_code'][i]}'
    ];
    return '$name now ${c['temperature_2m']}°F (feels ${c['apparent_temperature']}°F), '
        'code ${c['weather_code']}, wind ${c['wind_speed_10m']} mph\n${days.join('\n')}\n'
        '(WMO codes: 0 clear, 1-3 clouds, 45-48 fog, 51-67 rain, 71-77 snow, 80-82 showers, 95-99 thunder. Weather data by Open-Meteo.com)';
  }

  // ---------- Mac calendar (EventKit, see CalendarChannel) ----------

  Future<String> calendarEvents(Object? days) async {
    final n = (days is num ? days.toInt() : int.tryParse('$days') ?? 7).clamp(1, 31);
    final r = await _calendar.invokeMethod<Object>('events', {'days': n});
    if (r is String) return r; // error / no access
    final list = (r as List?) ?? [];
    if (list.isEmpty) return 'no events in the next $n days';
    return list.map((e) => '- ${e['start']}${e['allDay'] == true ? ' (all day)' : ' → ${e['end']}'}: ${e['title']}'
        '${(e['location'] ?? '').toString().isNotEmpty ? ' @ ${e['location']}' : ''} [${e['calendar']}]').join('\n');
  }

  Future<String> addCalendarEvent(Map<String, dynamic> a) async {
    final r = await _calendar.invokeMethod<String>('add', {
      'title': '${a['title']}',
      'start': '${a['start']}',
      'end': '${a['end'] ?? ''}',
      'location': '${a['location'] ?? ''}',
    });
    return r ?? 'error';
  }
}
