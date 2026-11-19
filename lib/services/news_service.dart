import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../edition.dart';

class NewsItem {
  final String topic; // what we searched for (e.g. "Apple")
  final String title;
  final String link;
  final String source;
  final DateTime? published;
  NewsItem(this.topic, this.title, this.link, this.source, this.published);
}

/// Big news about what the owner holds, from Google News RSS (no key).
/// Only headlines with strong words count as "깜짝 뉴스"; each one is
/// reacted to once (seen list kept on this Mac), at most 3 a day.
class NewsService {
  static const maxPerDay = 3;

  final Set<String> _seen = {};
  final Map<String, int> _perDay = {};

  /// Strong-move / big-event words in English headlines.
  static final big = RegExp(
      r'\b(soar\w*|surg\w*|plung\w*|crash\w*|tumbl\w*|skyrocket\w*|'
      r'record high|all[- ]time high|rall(y|ies)|sell-?off|slump\w*|'
      r'hack(ed)?|exploit|ban(s|ned)?|lawsuit|SEC|ETF|approv\w*|'
      r'bankrupt\w*|halt\w*|delist\w*|breakthrough|earnings beat|'
      r'jump(s|ed)?|sink(s)?|sank|spik\w*)\b',
      caseSensitive: false);

  static String url(String query) =>
      'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent('$query when:1d')}'
      '&hl=en-US&gl=US&ceid=US:en';

  static DateTime? _date(String s) {
    try {
      return HttpDate.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Minimal RSS reading (titles, links, dates); no XML package needed.
  static List<NewsItem> parse(String topic, String xml) {
    String tag(String block, String name) {
      final m = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>').firstMatch(block);
      var v = m?.group(1)?.trim() ?? '';
      v = v.replaceAll(RegExp(r'^<!\[CDATA\[|\]\]>$'), '');
      return v
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>');
    }

    final out = <NewsItem>[];
    for (final m in RegExp(r'<item>([\s\S]*?)</item>').allMatches(xml)) {
      final b = m.group(1)!;
      var title = tag(b, 'title');
      final source = tag(b, 'source');
      // Google appends " - Source" to titles.
      if (source.isNotEmpty && title.endsWith(' - $source')) {
        title = title.substring(0, title.length - source.length - 3);
      }
      out.add(NewsItem(topic, title, tag(b, 'link'), source,
          _date(tag(b, 'pubDate'))));
    }
    return out;
  }

  /// The first new, big, recent headline among [items] (null = nothing).
  NewsItem? pickBig(List<NewsItem> items, DateTime now) {
    final day = now.toIso8601String().substring(0, 10);
    if ((_perDay[day] ?? 0) >= maxPerDay) return null;
    for (final n in items) {
      if (_seen.contains(n.link) || _seen.contains(n.title)) continue;
      final p = n.published;
      if (p != null && now.difference(p).inHours > 6) continue;
      if (!big.hasMatch(n.title)) continue;
      return n;
    }
    return null;
  }

  void markShown(NewsItem n, DateTime now) {
    final day = now.toIso8601String().substring(0, 10);
    _perDay[day] = (_perDay[day] ?? 0) + 1;
    _seen
      ..add(n.link)
      ..add(n.title);
    _save();
  }

  /// Fetches every topic; returns all items (newest first per topic).
  Future<List<NewsItem>> fetch(List<String> topics) async {
    if (!Ed.noncommercialApis) return [];
    final all = <NewsItem>[];
    for (final t in topics) {
      try {
        final r = await http
            .get(Uri.parse(url(t)))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          all.addAll(parse(t, utf8.decode(r.bodyBytes)));
        }
      } catch (_) {}
    }
    return all;
  }

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/news_seen.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _seen.addAll((j['seen'] as List? ?? []).map((e) => e.toString()));
      (j['perDay'] as Map? ?? {})
          .forEach((k, v) => _perDay[k.toString()] = (v as num).toInt());
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final keep = _seen.toList();
      final trimmed = keep.length > 400 ? keep.sublist(keep.length - 400) : keep;
      await (await _file())
          .writeAsString(jsonEncode({'seen': trimmed, 'perDay': _perDay}));
    } catch (_) {}
  }
}
