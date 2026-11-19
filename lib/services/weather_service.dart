import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../edition.dart';

/// Weather condition the pet reacts to.
enum Sky { clear, cloudy, fog, drizzle, rain, snow, thunder }

/// Live weather from free, key-less APIs.
/// Location: IP-based guess (ipapi.co), weather: Open-Meteo.
class WeatherInfo {
  final double tempC;
  final double feelsC;
  final int code; // WMO weather code
  final bool isDay;
  final double windKmh;
  final double todayMax;
  final double todayMin;
  final int rainChance; // today's max precipitation probability, %
  final String city;
  final DateTime at;

  WeatherInfo({
    required this.tempC,
    required this.feelsC,
    required this.code,
    required this.isDay,
    required this.windKmh,
    required this.todayMax,
    required this.todayMin,
    required this.rainChance,
    required this.city,
    required this.at,
  });

  Sky get sky {
    if (code >= 95) return Sky.thunder;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return Sky.snow;
    final rain = (code >= 61 && code <= 67) || (code >= 80 && code <= 82);
    if (rain) return Sky.rain;
    if (code >= 51 && code <= 57) return Sky.drizzle;
    if (code == 45 || code == 48) return Sky.fog;
    if (code >= 2) return Sky.cloudy;
    return Sky.clear;
  }

  bool get isRain =>
      sky == Sky.rain ||
      sky == Sky.drizzle ||
      sky == Sky.thunder ||
      sky == Sky.snow;
  bool get isHot => feelsC >= 30;
  bool get isCold => feelsC <= 3;
  bool get isWindy => windKmh >= 35;

  /// Nice weather: dry, mild, daytime.
  bool get isLovely =>
      !isRain && isDay && tempC >= 15 && tempC <= 26 && sky != Sky.fog;

  String get skyKo => {
        Sky.clear: Lang.t('맑음', 'clear', '晴'),
        Sky.cloudy: Lang.t('흐림', 'cloudy', '多云'),
        Sky.fog: Lang.t('안개', 'foggy', '有雾'),
        Sky.drizzle: Lang.t('이슬비', 'drizzle', '毛毛雨'),
        Sky.rain: Lang.t('비', 'rainy', '下雨'),
        Sky.snow: Lang.t('눈', 'snowy', '下雪'),
        Sky.thunder: Lang.t('천둥번개', 'thunderstorm', '雷暴'),
      }[sky]!;

  String get emoji => const {
        Sky.clear: '☀️',
        Sky.cloudy: '☁️',
        Sky.fog: '🌫️',
        Sky.drizzle: '🌦️',
        Sky.rain: '🌧️',
        Sky.snow: '❄️',
        Sky.thunder: '⛈️',
      }[sky]!;

  /// Key for "did the situation change?" (sky + temperature band + wind).
  String get situation =>
      '${sky.name}|${isHot ? 'hot' : isCold ? 'cold' : 'mild'}|${isWindy ? 'wind' : ''}';

  /// One line for the AI prompt and the care tab.
  static int f(double c) => (c * 9 / 5 + 32).round();

  int get tempF => f(tempC);
  int get feelsF => f(feelsC);
  int get minF => f(todayMin);
  int get maxF => f(todayMax);

  // Fahrenheit only: the user thinks in °F.
  String get summary => Lang.t(
      '$city $tempF°F(체감 $feelsF°F) $skyKo, '
          '오늘 $minF~$maxF°F, 강수확률 $rainChance%'
          '${isWindy ? ', 바람 강함' : ''}',
      '$city $tempF°F (feels like $feelsF°F) $skyKo, '
          'today $minF~$maxF°F, rain chance $rainChance%'
          '${isWindy ? ', windy' : ''}');
}

class WeatherService {
  WeatherInfo? current;

  // Home location from the owner profile. Only coordinates are sent
  // (no address or IP lookup).
  String homeName = 'Los Angeles';
  double homeLat = 34.0522, homeLon = -118.2437;

  Future<void> refresh() async {
    if (!Ed.noncommercialApis) return;
    try {
      final wRes = await http
          .get(Uri.parse('https://api.open-meteo.com/v1/forecast'
              '?latitude=$homeLat&longitude=$homeLon'
              '&current=temperature_2m,apparent_temperature,weather_code,'
              'is_day,wind_speed_10m'
              '&daily=temperature_2m_max,temperature_2m_min,'
              'precipitation_probability_max'
              '&forecast_days=1&timezone=auto'))
          .timeout(const Duration(seconds: 8));
      if (wRes.statusCode == 200) {
        current =
            parse(jsonDecode(wRes.body) as Map<String, dynamic>, homeName);
      }
    } catch (_) {
      // keep last known weather
    }
  }

  /// Open-Meteo response -> WeatherInfo (separate for tests).
  static WeatherInfo parse(Map<String, dynamic> j, String city) {
    final c = j['current'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;
    double first(String k) {
      final l = d[k];
      return (l is List && l.isNotEmpty)
          ? ((l.first as num?)?.toDouble() ?? 0)
          : 0;
    }

    final t = (c['temperature_2m'] as num).toDouble();
    return WeatherInfo(
      tempC: t,
      feelsC: (c['apparent_temperature'] as num?)?.toDouble() ?? t,
      code: (c['weather_code'] as num).toInt(),
      isDay: ((c['is_day'] as num?) ?? 1) == 1,
      windKmh: (c['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      todayMax: first('temperature_2m_max'),
      todayMin: first('temperature_2m_min'),
      rainChance: first('precipitation_probability_max').round(),
      city: city,
      at: DateTime.now(),
    );
  }
}
