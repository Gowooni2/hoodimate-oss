import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Everything personal about the owner lives here, in profile.json in the
/// app's support folder, never in the source code: language, home
/// location for weather, a short "about me" for the AI, and one stock to
/// watch. Coin holdings are separate (portfolio.json, MarketService).
class OwnerProfile {
  /// 'en', 'ko' or 'zh'. Picks the UI, the pet's lines and the AI reply
  /// language. Text without a Chinese version falls back to English.
  String language;

  /// Weather location. Coordinates are stored so no address or IP lookup
  /// is sent anywhere at runtime.
  String placeName;
  double lat;
  double lon;

  /// Home ZIP / postal code, state or province, and country code (US, KR,
  /// CN ...). Local questions and news searches follow these, not the
  /// language the owner chats in.
  String zip;
  String region;
  String country;

  /// "Springfield, Illinois 62701, US" (whatever is known).
  String get homeLine => [placeName.trim(), '${region.trim()} ${zip.trim()}'.trim(), country.trim()]
      .where((s) => s.isNotEmpty)
      .join(', ');

  /// Free text the AI gets as context (who the owner is, units, ...).
  String about;

  /// One stock to watch (Yahoo symbol) and its display/news name.
  /// Empty symbol = no stock.
  String stockSymbol;
  String stockName;

  /// Owner's birthday as "MM-DD" (no year), empty = unknown.
  String birthday;

  /// Character pack id (assets/characters/<id>), empty = first available.
  String character;

  OwnerProfile({
    this.language = 'en',
    this.placeName = 'Los Angeles',
    this.lat = 34.0522,
    this.lon = -118.2437,
    this.zip = '',
    this.region = 'California',
    this.country = 'US',
    this.about = '',
    this.stockSymbol = '',
    this.stockName = '',
    this.birthday = '',
    this.character = '',
  });

  bool isBirthday(DateTime d) {
    if (birthday.isEmpty) return false;
    String mmdd(DateTime x) =>
        '${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    if (birthday == mmdd(d)) return true;
    // Born on Feb 29: celebrate on Feb 28 in common years.
    final leap = d.year % 4 == 0 && (d.year % 100 != 0 || d.year % 400 == 0);
    return birthday == '02-29' && !leap && d.month == 2 && d.day == 28;
  }

  bool get ko => language == 'ko';

  static const languages = ['en', 'ko', 'zh'];

  Map<String, dynamic> toJson() => {
        'language': language,
        'placeName': placeName,
        'lat': lat,
        'lon': lon,
        'zip': zip,
        'region': region,
        'country': country,
        'about': about,
        'stockSymbol': stockSymbol,
        'stockName': stockName,
        'birthday': birthday,
        'character': character,
      };

  void fromJson(Map<String, dynamic> j) {
    if (j.containsKey('language')) {
      language = languages.contains(j['language']) ? j['language'] as String : 'en';
    }
    placeName = (j['placeName'] ?? placeName).toString();
    lat = j['lat'] is num ? (j['lat'] as num).toDouble() : lat;
    lon = j['lon'] is num ? (j['lon'] as num).toDouble() : lon;
    zip = (j['zip'] ?? zip).toString();
    region = (j['region'] ?? region).toString();
    country = (j['country'] ?? country).toString().toUpperCase();
    about = (j['about'] ?? about).toString();
    stockSymbol = (j['stockSymbol'] ?? stockSymbol).toString();
    stockName = (j['stockName'] ?? stockName).toString();
    birthday = (j['birthday'] ?? birthday).toString();
    character = (j['character'] ?? character).toString();
  }

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/profile.json');
  }

  /// First run: the language follows the system locale.
  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        return;
      }
      final sys = Platform.localeName;
      language = sys.startsWith('ko') ? 'ko' : (sys.startsWith('zh') ? 'zh' : 'en');
      await save();
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      await (await _file()).writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }
}

/// The app's name in every language.
String get appName => Lang.t('후디메이트', 'Hoodimate', 'Hoodimate');

/// Shared language switch for code without a profile handle (pure
/// functions, widgets). PetBrain keeps it in sync with the profile.
class Lang {
  /// 'en', 'ko' or 'zh'.
  static String code = 'en';

  static bool get ko => code == 'ko';
  static set ko(bool v) => code = v ? 'ko' : 'en';
  static bool get zh => code == 'zh';

  /// Picks the line for the current language. Chinese is optional for now;
  /// without it the English line is shown.
  static String t(String ko_, String en, [String? zh_]) =>
      code == 'ko' ? ko_ : (code == 'zh' ? (zh_ ?? en) : en);
}

/// "Let's talk in English" / "한국어로 대화하자" / "我们说中文吧" in chat:
/// returns the language to switch to, or null.
class LanguageSwitch {
  static final _ko = RegExp(
      r'(한국어|한글)\s*로\s*(대화|얘기|이야기|말|해(?:\s*줘|\s*주세요|\s*봐)?\s*[.!?~]*$)|\b(speak|talk|chat|reply|switch)\s+(to\s+|in\s+)?korean\b|说韩语|用韩语',
      caseSensitive: false);
  static final _en = RegExp(
      r'영어\s*로\s*(대화|얘기|이야기|말|해(?:\s*줘|\s*주세요|\s*봐)?\s*[.!?~]*$)|\b(speak|talk|chat|reply|switch)\s+(to\s+|in\s+)?english\b|说英语|用英语|讲英语',
      caseSensitive: false);
  static final _zh = RegExp(
      r'중국어\s*로\s*(대화|얘기|이야기|말|해(?:\s*줘|\s*주세요|\s*봐)?\s*[.!?~]*$)|\b(speak|talk|chat|reply|switch)\s+(to\s+|in\s+)?(chinese|mandarin)\b|说中文|用中文|讲中文|说汉语',
      caseSensitive: false);

  static const _negation = r"(don'?t|do\s+not|stop|never|not|no)\b";

  /// A request that is turned down ("don't speak Korean", "한국어로 말하지 마").
  static bool _negated(String text, Match m) {
    final before = text.substring(m.start < 28 ? 0 : m.start - 28, m.start);
    final after = text.substring(m.end, m.end + 14 > text.length ? text.length : m.end + 14);
    return RegExp(_negation, caseSensitive: false).hasMatch(before) ||
        RegExp(r'하지\s*마|말고|말아|그만|싫어|안\s*할').hasMatch(after);
  }

  static String? detect(String text) {
    String? best;
    var bestAt = -1;
    for (final e in {'ko': _ko, 'en': _en, 'zh': _zh}.entries) {
      for (final m in e.value.allMatches(text)) {
        if (_negated(text, m)) continue;
        if (m.start > bestAt) {
          bestAt = m.start;
          best = e.key; // when two languages are named, the later one is the one asked for
        }
      }
    }
    return best;
  }

  static String confirm(String code) => switch (code) {
        'ko' => '좋아! 이제부터 한국어로 말할게 😊 메뉴도 한국어로 바꿨어.',
        'zh' => '好的！从现在开始我说中文 😊 菜单也换成中文了（部分还在翻译中）。',
        _ => "Okay! I'll talk in English from now on 😊 The menus are in English too.",
      };
}
