import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/domain/weight_trend.dart';
import 'package:flutter_test/flutter_test.dart';

WeightPoint point(int day, double kg) => WeightPoint(day: DayKey(day), kg: kg);

void main() {
  group('WeightSeries', () {
    test('sorts points oldest-first regardless of input order', () {
      final series = WeightSeries.of([
        point(20260703, 78),
        point(20260701, 80),
        point(20260702, 82),
      ]);
      expect(series.points.map((p) => p.day.value), [
        20260701,
        20260702,
        20260703,
      ]);
      expect(series.firstKg, 80);
      expect(series.latestKg, 78);
    });

    test('change is latest minus first, and null below two points', () {
      expect(WeightSeries.of([point(20260701, 80)]).changeKg, isNull);
      final series = WeightSeries.of([
        point(20260701, 80),
        point(20260710, 77.5),
      ]);
      expect(series.changeKg, closeTo(-2.5, 0.0001));
    });

    test('reports the min and max of the band', () {
      final series = WeightSeries.of([
        point(20260701, 80),
        point(20260702, 76),
        point(20260703, 83),
      ]);
      expect(series.minKg, 76);
      expect(series.maxKg, 83);
    });

    test('since keeps only points on or after the cutoff', () {
      final series = WeightSeries.of([
        point(20260701, 80),
        point(20260705, 79),
        point(20260710, 78),
      ]);
      final recent = series.since(DayKey(20260705));
      expect(recent.points.map((p) => p.day.value), [20260705, 20260710]);
    });

    test('an empty series has no summaries but does not throw', () {
      final series = WeightSeries.of(const []);
      expect(series.isEmpty, isTrue);
      expect(series.latestKg, isNull);
      expect(series.changeKg, isNull);
      expect(series.movingAverage(7), isEmpty);
    });

    group('movingAverage', () {
      test('smooths over a trailing window, shrinking at the start', () {
        final series = WeightSeries.of([
          point(20260701, 80),
          point(20260702, 82),
          point(20260703, 78),
          point(20260704, 76),
        ]);
        final smoothed = series.movingAverage(3);
        expect(smoothed.map((p) => p.kg.toStringAsFixed(3)), [
          '80.000', // [80]
          '81.000', // [80, 82]
          '80.000', // [80, 82, 78]
          '78.667', // [82, 78, 76]
        ]);
        // The smoothed line stays aligned with the raw days.
        expect(smoothed.map((p) => p.day.value), [
          20260701,
          20260702,
          20260703,
          20260704,
        ]);
      });

      test('a window of one is a passthrough', () {
        final series = WeightSeries.of([
          point(20260701, 80),
          point(20260702, 82),
        ]);
        expect(series.movingAverage(1).map((p) => p.kg), [80, 82]);
      });
    });
  });
}
