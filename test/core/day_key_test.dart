import 'package:easytrack/core/time/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DayKey', () {
    test('encodes a date as yyyymmdd', () {
      expect(DayKey.fromDate(DateTime(2026, 7, 19)).value, 20260719);
      expect(DayKey.fromDate(DateTime(2026, 1, 1)).value, 20260101);
      expect(DayKey.fromDate(DateTime(2026, 12, 31)).value, 20261231);
    });

    test('round-trips through DateTime', () {
      const key = DayKey(20260719);
      expect(key.toDateTime(), DateTime(2026, 7, 19));
      expect(key.year, 2026);
      expect(key.month, 7);
      expect(key.day, 19);
    });

    test('sorts chronologically as an integer', () {
      final days = [
        DayKey.fromDate(DateTime(2026, 12, 31)),
        DayKey.fromDate(DateTime(2026, 1, 5)),
        DayKey.fromDate(DateTime(2025, 6, 30)),
      ]..sort();
      expect(days.map((d) => d.value), [20250630, 20260105, 20261231]);
    });

    test('crosses month and year boundaries', () {
      expect(const DayKey(20260131).next.value, 20260201);
      expect(const DayKey(20261231).next.value, 20270101);
      expect(const DayKey(20260101).previous.value, 20251231);
      // 2026 is not a leap year, so 1 March steps back to 28 February.
      expect(const DayKey(20260301).previous.value, 20260228);
      expect(const DayKey(20240301).previous.value, 20240229); // 2024 is
    });

    test('handles leap days', () {
      expect(const DayKey(20260228).next.value, 20260301); // 2026 is not leap
      expect(const DayKey(20240228).next.value, 20240229); // 2024 is leap
    });

    test('daysUntil counts calendar days in both directions', () {
      expect(const DayKey(20260719).daysUntil(const DayKey(20260726)), 7);
      expect(const DayKey(20260726).daysUntil(const DayKey(20260719)), -7);
      expect(const DayKey(20260719).daysUntil(const DayKey(20260719)), 0);
      // Across a year boundary.
      expect(const DayKey(20251231).daysUntil(const DayKey(20260101)), 1);
    });

    test('daysUntil is unaffected by DST transitions', () {
      // In German time, DST starts on the last Sunday of March. A naive
      // difference in local hours would give 23 hours here and truncate to 0.
      expect(const DayKey(20260328).daysUntil(const DayKey(20260329)), 1);
      // And ends on the last Sunday of October (25-hour day).
      expect(const DayKey(20261024).daysUntil(const DayKey(20261025)), 1);
    });

    test('addDays spans long ranges', () {
      expect(const DayKey(20260101).addDays(365).value, 20270101);
      expect(const DayKey(20260719).addDays(-200).value, 20251231);
    });
  });
}
