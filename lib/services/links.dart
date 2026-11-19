import 'package:flutter/services.dart';

import '../edition.dart';

/// Opens the public pages (privacy policy, support) in the browser.
class Links {
  static const _ch = MethodChannel('hoodimong/link');

  static Future<void> open(String url) async {
    try {
      await _ch.invokeMethod('open', url);
    } catch (_) {}
  }

  static Future<void> privacy() => open(Ed.privacyUrl);
  static Future<void> support() => open(Ed.supportUrl);
}
