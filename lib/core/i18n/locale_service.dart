import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the language the user picked, if any.
///
/// A single device-local string (the language code) rather than a domain-data
/// row: the choice is a UI preference, not part of the user's diary, so it lives
/// in [SharedPreferences] next to the onboarding flag — see [OnboardingService]
/// for the same pattern. Absent means "no explicit choice yet", which the
/// [LocaleController] reads as "follow the device language".
class LocaleService {
  LocaleService(this._prefs);

  final SharedPreferences _prefs;

  /// Versioned so a future change to how the locale is stored (e.g. adding a
  /// country code) can re-decide for everyone by bumping the key.
  static const _key = 'app_locale_v1';

  /// The language the user explicitly chose, or null to follow the device.
  Locale? getLocale() {
    final code = _prefs.getString(_key);
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  /// Persists an explicit choice, or clears it (null) to follow the device again.
  Future<void> setLocale(Locale? locale) async {
    if (locale == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, locale.languageCode);
    }
  }
}
