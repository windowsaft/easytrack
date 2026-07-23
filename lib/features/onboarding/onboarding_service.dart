import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the first-run onboarding has been completed.
///
/// A single device-local flag rather than inferring it from the database: the
/// user can legitimately finish onboarding by *skipping* it (accepting the
/// default target), which leaves no profile behind, so "has a profile" is not a
/// reliable proxy for "has seen onboarding". The gate still treats an existing
/// configured profile as already-onboarded so returning installs never see it.
class OnboardingService {
  OnboardingService(this._prefs);

  final SharedPreferences _prefs;

  /// Versioned so a future onboarding revision can re-run for everyone by
  /// bumping the key, without a migration.
  static const _key = 'onboarding_complete_v1';

  bool get isComplete => _prefs.getBool(_key) ?? false;

  Future<void> markComplete() => _prefs.setBool(_key, true);
}
