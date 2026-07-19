import 'package:flutter/material.dart';

/// The activity presets offered as chips on the add-activity screen.
///
/// Deliberately a short fixed list rather than a database table: it exists to
/// label an entry and pick an icon, and the calorie figure is always typed by
/// hand. A user-editable catalogue would be a feature with no payoff until
/// activities are estimated rather than entered.
enum ActivityType {
  bike('Radfahren', Icons.directions_bike),
  run('Laufen', Icons.directions_run),
  walk('Gehen', Icons.directions_walk),
  gym('Kraftsport', Icons.fitness_center);

  const ActivityType(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Resolves a stored entry's free-text label back to an icon.
///
/// Labels are stored as text, not as an enum reference, so that renaming or
/// removing a preset cannot orphan historical rows. The lookup falls back to a
/// generic icon rather than failing.
IconData activityIconFor(String label) {
  for (final type in ActivityType.values) {
    if (type.label.toLowerCase() == label.toLowerCase()) return type.icon;
  }
  return Icons.local_fire_department;
}
