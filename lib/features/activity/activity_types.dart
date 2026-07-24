import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The activity presets offered as chips on the add-activity screen.
///
/// Deliberately a short fixed list rather than a database table: it exists to
/// label an entry and pick an icon, and the calorie figure is always typed by
/// hand. A user-editable catalogue would be a feature with no payoff until
/// activities are estimated rather than entered.
enum ActivityType {
  bike(Icons.directions_bike),
  run(Icons.directions_run),
  walk(Icons.directions_walk),
  gym(Icons.fitness_center);

  const ActivityType(this.icon);

  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
    ActivityType.bike => l10n.activityBike,
    ActivityType.run => l10n.activityRun,
    ActivityType.walk => l10n.activityWalk,
    ActivityType.gym => l10n.activityGym,
  };
}

/// Resolves a stored entry's label back to an icon.
///
/// Labels are stored as the localized preset text at the moment of entry, not
/// as an enum reference, so that renaming or removing a preset cannot orphan
/// historical rows. Matching is against the *current* language's preset names,
/// so an entry logged in another language falls back to the generic icon rather
/// than failing.
IconData activityIconFor(AppLocalizations l10n, String label) {
  for (final type in ActivityType.values) {
    if (type.label(l10n).toLowerCase() == label.toLowerCase()) return type.icon;
  }
  return Icons.local_fire_department;
}
