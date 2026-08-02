import 'package:shared_preferences/shared_preferences.dart';

import '../time/week_start.dart';

/// Remembers which weekday the user counts a week from, if they have said.
///
/// A device-local display preference rather than diary data, so it lives in
/// [SharedPreferences] next to the language — see [LocaleService] for the same
/// reasoning. Absent means "no explicit choice yet", which the controller reads
/// as the convention of the active language.
class WeekStartService {
  WeekStartService(this._prefs);

  final SharedPreferences _prefs;

  /// Versioned like the locale key, so a future change to the stored form can
  /// re-decide for everyone by bumping it.
  static const _key = 'week_start_v1';

  /// The convention the user explicitly chose, or null to follow the language.
  WeekStart? getWeekStart() {
    final name = _prefs.getString(_key);
    for (final value in WeekStart.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  Future<void> setWeekStart(WeekStart start) =>
      _prefs.setString(_key, start.name);
}
