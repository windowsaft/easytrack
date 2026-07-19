/// A local calendar day encoded as `yyyymmdd`, e.g. 2026-07-19 -> 20260719.
///
/// Diary entries are keyed by this rather than by a UTC timestamp. A timestamp
/// forces every read to convert back through a timezone, and the moment the
/// user travels — or the device changes timezone — entries silently migrate
/// across day boundaries. What the user means by "what I ate on Tuesday" is the
/// local calendar day, so that is what gets stored.
///
/// The integer form sorts and ranges correctly (`BETWEEN 20260701 AND 20260731`
/// is exactly July), which keeps day-range queries trivial.
extension type const DayKey(int value) implements int {
  factory DayKey.fromDate(DateTime date) =>
      DayKey(date.year * 10000 + date.month * 100 + date.day);

  /// The current local day.
  factory DayKey.today() => DayKey.fromDate(DateTime.now());

  int get year => value ~/ 10000;
  int get month => (value ~/ 100) % 100;
  int get day => value % 100;

  /// Local midnight at the start of this day.
  DateTime toDateTime() => DateTime(year, month, day);

  /// Shifts by [days], correctly crossing month and year boundaries by going
  /// through DateTime rather than doing arithmetic on the packed integer.
  DayKey addDays(int days) =>
      DayKey.fromDate(DateTime(year, month, day + days));

  DayKey get previous => addDays(-1);
  DayKey get next => addDays(1);

  bool get isToday => value == DayKey.today().value;

  /// Number of days from this day to [other]; negative if [other] is earlier.
  ///
  /// Uses UTC internally so that a DST transition in between does not turn a
  /// whole-day difference into 23 or 25 hours and truncate to the wrong value.
  int daysUntil(DayKey other) {
    final a = DateTime.utc(year, month, day);
    final b = DateTime.utc(other.year, other.month, other.day);
    return b.difference(a).inDays;
  }
}
