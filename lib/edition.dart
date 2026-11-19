/// Which build this is. Chosen at build time:
///   flutter build macos --dart-define=EDITION=store
/// tools/build_edition.sh also strips the assets an edition must not ship
/// (see the `# edition:` markers in pubspec.yaml).
///
///   personal  the owner's own build: everything (incl. market briefing)
///   store     Mac App Store: sandbox only, extra packs through In-App Purchase
///   direct    sold from our site: extra packs through license keys
///   lite      open-source build: one character, no tools/sync/cloud voice
enum Edition { personal, store, direct, lite }

/// How extra emoticon/character packs are unlocked in this edition.
enum PackSales { none, appStore, licenseKey }

class Ed {
  static const _name = String.fromEnvironment('EDITION', defaultValue: 'lite');
  static final Edition current =
      Edition.values.firstWhere((e) => e.name == _name, orElse: () => Edition.personal);

  static bool get isLite => current == Edition.lite;

  /// The editions we sell (Mac App Store, our own site). They get the
  /// first-run walkthrough, the care-first panel and the native Mac extras;
  /// the owner's own build keeps its earlier behaviour.
  static bool get isSold => current == Edition.store || current == Edition.direct;

  /// Web search, weather, calendar, notes etc. for the AI.
  static bool get agentTools => !isLite;

  /// Calendar access (EventKit).
  static bool get calendar => !isLite;

  /// Sync between Macs through a shared folder.
  static bool get sync => !isLite;

  /// ElevenLabs read-aloud (the owner's own key).
  static bool get cloudVoice => !isLite;

  /// Market briefing (CoinGecko + an unofficial Yahoo Finance endpoint whose
  /// terms don't allow commercial use): the owner's own build only.
  static bool get market => current == Edition.personal;

  /// Free data services whose terms are non-commercial (Open-Meteo weather
  /// and geocoding, Google News RSS, DuckDuckGo results page). Sold
  /// editions need licensed sources instead (e.g. Apple WeatherKit,
  /// the owner's own Brave Search key).
  static bool get noncommercialApis => current == Edition.personal || isLite;

  /// Version 1 ships with no purchases at all (decided 2026-10-09): the
  /// five Hoodies are included. In-App Purchase / license keys come later.
  /// Later: store -> PackSales.appStore, direct -> PackSales.licenseKey.
  /// Folder name for notes and for the sync folder. The owner's own build
  /// keeps the name its existing notes and sync data already use.
  static String get dataFolder => current == Edition.personal ? 'Hoodimong' : 'Hoodimate';

  static PackSales get packSales => PackSales.none;

  /// AI chat in sold builds keeps to a 16+ rating: no sexual content,
  /// graphic violence or self-harm instructions (App Review 2.3.6, 4.7).
  static bool get safetyRules => current != Edition.personal;

  /// Public pages (hosted on Vercel from `site/`). Override with
  /// --dart-define=SITE_URL=... once the real address is known.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://hoodimong.gowooni.com/hoodimate');
  static String get privacyUrl => '$siteUrl/privacy';
  static String get supportUrl => '$siteUrl/support';
}
