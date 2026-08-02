import 'day_key.dart';

/// Which weekday a calendar week is counted from.
///
/// Only the two conventions the shipped languages need: German — like most of
/// Europe — counts from Monday, English (US) from Sunday. A third variant
/// (Saturday, used across the Arabic-speaking world) is a case here plus a
/// label in the picker, once a translation needs it.
enum WeekStart {
  monday(DateTime.monday),
  sunday(DateTime.sunday);

  const WeekStart(this.firstWeekday);

  /// The [DateTime.weekday] value a week begins on.
  final int firstWeekday;

  /// The convention [languageCode] uses, for a user who has not chosen one.
  static WeekStart forLanguage(String languageCode) =>
      languageCode == 'en' ? WeekStart.sunday : WeekStart.monday;

  /// The first day of the week containing [day].
  DayKey startOfWeek(DayKey day) =>
      day.addDays(-((day.toDateTime().weekday - firstWeekday + 7) % 7));
}
