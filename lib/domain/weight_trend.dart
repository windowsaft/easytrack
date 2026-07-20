import 'dart:math' as math;

import '../core/time/day_key.dart';

/// One weigh-in: a calendar day and a body weight.
class WeightPoint {
  const WeightPoint({required this.day, required this.kg});

  final DayKey day;
  final double kg;
}

/// A body-weight series, sorted oldest-first, with the summaries the trend view
/// needs. Deliberately free of drift and Flutter so the arithmetic is
/// unit-testable in isolation.
class WeightSeries {
  WeightSeries._(this.points);

  /// Sorts the points oldest-first. The store hands them over ordered, but the
  /// class owns its invariant so a caller passing an unsorted list — a filtered
  /// subset, a test fixture — still gets correct summaries.
  factory WeightSeries.of(Iterable<WeightPoint> points) {
    final sorted = [...points]
      ..sort((a, b) => a.day.value.compareTo(b.day.value));
    return WeightSeries._(List.unmodifiable(sorted));
  }

  final List<WeightPoint> points;

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  double? get firstKg => isEmpty ? null : points.first.kg;
  double? get latestKg => isEmpty ? null : points.last.kg;

  /// Net change over the series (latest − first). Null below two points, where
  /// a change has no meaning yet — distinct from a change of zero.
  double? get changeKg =>
      points.length < 2 ? null : points.last.kg - points.first.kg;

  double? get minKg =>
      isEmpty ? null : points.map((p) => p.kg).reduce(math.min);
  double? get maxKg =>
      isEmpty ? null : points.map((p) => p.kg).reduce(math.max);

  /// The sub-series measured on or after [from]. Used by the range toggle.
  WeightSeries since(DayKey from) => WeightSeries._([
    for (final p in points)
      if (p.day.value >= from.value) p,
  ]);

  /// Trailing simple moving average over [window] points — the smoothed trend
  /// line drawn over the scattered daily weigh-ins.
  ///
  /// Averaged over a count of points rather than a span of days: the log is not
  /// guaranteed to have an entry every day, and counting points is the honest
  /// smoothing for an irregular series. Each output keeps the day of the point
  /// it ends on, so the smoothed line stays aligned with the raw one. Early
  /// points average over the shorter run available rather than being dropped.
  List<WeightPoint> movingAverage(int window) {
    if (window <= 1 || points.length < 2) return points;
    return [
      for (var i = 0; i < points.length; i++)
        WeightPoint(day: points[i].day, kg: _trailingMean(i, window)),
    ];
  }

  double _trailingMean(int end, int window) {
    final start = math.max(0, end - window + 1);
    var sum = 0.0;
    for (var j = start; j <= end; j++) {
      sum += points[j].kg;
    }
    return sum / (end - start + 1);
  }
}
