import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/db/user_database.dart';
import '../../domain/history.dart';
import '../../domain/weight_trend.dart';
import '../weight/weight_screen.dart';

/// Screen 7d — Verlauf: how the last week/month has gone against the target.
///
/// Everything is derived from local data already in the DB: per-day diary
/// rollups vs the history-preserving target, plus water, activity and the weight
/// trend. Chart style matches the Gewicht screen — lime line/bars, coral for
/// "over", faint fills, minimal chrome.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

enum _Period {
  woche('Woche', 7),
  monat('Monat', 30);

  const _Period(this.label, this.days);
  final String label;
  final int days;
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Period _period = _Period.woche;

  @override
  Widget build(BuildContext context) {
    final days =
        ref.watch(historyProvider(_period.days)).value ?? const <DayHistory>[];
    final summary = HistorySummary.of(days);

    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        const BoldHeader(title: 'VERLAUF'),
        _PeriodTabs(
          current: _period,
          onSelect: (p) => setState(() => _period = p),
        ),
        if (summary.daysLogged == 0)
          const _EmptyState()
        else ...[
          SectionHeader(
            title: 'KALORIEN',
            trailing: Text(
              'Ø ${summary.avgKcal.round()} kcal',
              style: AppText.grotesk(
                size: 11,
                weight: 600,
                color: AppColors.textMute,
                letterSpacing: 0.4,
              ),
            ),
          ),
          _KcalCard(days: days),
          const SectionHeader(title: 'ÜBERBLICK'),
          _TilePair(
            left: StatTile(
              label: 'ZIEL-TREUE',
              value: '${summary.adherentDays}',
              suffix: '/${summary.periodDays}',
              accent: AppColors.lime,
            ),
            right: StatTile(
              label: 'Ø ABWEICHUNG',
              value: _signedKcal(summary.avgDeviation),
              suffix: ' kcal',
              accent: AppColors.coral,
            ),
          ),
          const SizedBox(height: AppTheme.rowGap),
          _TilePair(
            left: StatTile(
              label: 'WASSER Ø',
              value: _litres(summary.avgWaterMl),
              suffix: ' L',
              accent: AppColors.water,
            ),
            right: StatTile(
              label: 'AKTIVITÄT Ø',
              value: '${summary.avgActivityKcal.round()}',
              suffix: ' kcal',
              accent: AppColors.coral,
            ),
          ),
          const SectionHeader(title: 'MAKRO-SPLIT Ø'),
          _MacroSplitCard(summary: summary),
        ],
        const SectionHeader(title: 'GEWICHT'),
        _WeightTrendCard(
          onManage: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => const WeightScreen())),
        ),
      ],
    );
  }

  static String _signedKcal(double kcal) {
    final n = kcal.round();
    final sign = n > 0 ? '+' : (n < 0 ? '−' : '±');
    return '$sign${n.abs()}';
  }

  static String _litres(double ml) {
    final l = ml / 1000;
    return l.toStringAsFixed(1).replaceAll('.', ',');
  }
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.current, required this.onSelect});

  final _Period current;
  final ValueChanged<_Period> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        8,
        AppTheme.screenPadding,
        6,
      ),
      child: Row(
        children: [
          for (final period in _Period.values) ...[
            if (period != _Period.values.first) const SizedBox(width: 8),
            Expanded(
              child: BoldChip(
                label: period.label,
                selected: current == period,
                onTap: () => onSelect(period),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kalorien vs. Ziel: a per-day bar chart with a dashed target line. The title
/// and Ø caption live in the section header above it.
class _KcalCard extends StatelessWidget {
  const _KcalCard({required this.days});

  final List<DayHistory> days;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: SizedBox(
        height: 138,
        child: CustomPaint(
          size: Size.infinite,
          painter: _KcalBarsPainter(days),
        ),
      ),
    );
  }
}

class _KcalBarsPainter extends CustomPainter {
  _KcalBarsPainter(this.days);

  final List<DayHistory> days;

  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  /// Reserved strip at the bottom for the day labels.
  static const _labelStrip = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    // Bars occupy everything above the label strip.
    final chartH = size.height - _labelStrip;
    final target = days.last.targetKcal > 0 ? days.last.targetKcal : 2000.0;
    final maxKcal = days.map((d) => d.kcal).fold(0.0, math.max);
    final maxY = math.max(maxKcal, target) * 1.18;
    if (maxY <= 0) return;

    final n = days.length;
    const gap = 4.0;
    final barW = (size.width - gap * (n - 1)) / n;

    for (var i = 0; i < n; i++) {
      final day = days[i];
      final h = (day.kcal / maxY) * chartH;
      final x = i * (barW + gap);

      // The last day is "today" — still being logged, so it reads as muted
      // rather than as a real over/under verdict.
      final color = !day.hasData
          ? AppColors.surfaceAlt
          : (i == n - 1
                ? AppColors.surfaceAlt
                : (day.isOverTarget ? AppColors.coral : AppColors.lime));

      if (h > 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, chartH - h, barW, h),
          Paint()..color = color,
        );
      }
    }

    // Dashed coral ZIEL line at the current target level.
    final ly = chartH - (target / maxY) * chartH;
    final linePaint = Paint()
      ..color = AppColors.coral
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, ly),
        Offset(math.min(x + 4, size.width), ly),
        linePaint,
      );
    }

    // Day labels under the bars: the weekday for a week, sparse day numbers for
    // a longer span so they do not collide.
    final every = n <= 10 ? 1 : (n / 6).ceil();
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      if (i % every != 0) continue;
      final date = days[i].day.toDateTime();
      final text = n <= 10 ? _weekdays[date.weekday - 1] : '${date.day}';
      tp
        ..text = TextSpan(
          text: text,
          style: const TextStyle(
            color: AppColors.textFaint,
            fontSize: 9.5,
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w600,
          ),
        )
        ..layout();
      final cx = i * (barW + gap) + barW / 2;
      tp.paint(canvas, Offset(cx - tp.width / 2, chartH + 5));
    }
  }

  @override
  bool shouldRepaint(_KcalBarsPainter oldDelegate) => oldDelegate.days != days;
}

/// The average macro split as one stacked bar plus a labelled % row.
class _MacroSplitCard extends StatelessWidget {
  const _MacroSplitCard({required this.summary});

  final HistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final split = summary.macroSplit;
    int flex(double share) => math.max(1, (share * 1000).round());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: flex(split.carbs),
                  child: Container(height: 14, color: AppColors.carbs),
                ),
                Expanded(
                  flex: flex(split.protein),
                  child: Container(height: 14, color: AppColors.protein),
                ),
                Expanded(
                  flex: flex(split.fat),
                  child: Container(height: 14, color: AppColors.fat),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MacroLabel('Kohlenh.', AppColors.carbs, split.carbs),
              _MacroLabel('Eiweiß', AppColors.protein, split.protein),
              _MacroLabel('Fett', AppColors.fat, split.fat),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroLabel extends StatelessWidget {
  const _MacroLabel(this.label, this.color, this.share);

  final String label;
  final Color color;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.grotesk(
                size: 11,
                weight: 600,
                color: AppColors.textMute,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(share * 100).round()}%',
            style: AppText.grotesk(size: 11, weight: 700),
          ),
        ],
      ),
    );
  }
}

/// A row of two equal StatTiles.
class _TilePair extends StatelessWidget {
  const _TilePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: AppTheme.rowGap),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// The weight-trend card + a doorway into the Gewicht screen.
class _WeightTrendCard extends ConsumerWidget {
  const _WeightTrendCard({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(weightLogProvider).value ?? const <WeightEntry>[];
    final series = WeightSeries.of([
      for (final r in rows)
        WeightPoint(day: DayKey(r.measuredOn), kg: r.weightKg),
    ]);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (series.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                series.isEmpty
                    ? 'Noch kein Gewicht erfasst.'
                    : 'Trend ab der zweiten Messung.',
                style: AppText.grotesk(size: 13, color: AppColors.textMute),
              ),
            )
          else
            SizedBox(height: 70, child: _WeightSparkline(series: series)),
          const Divider(height: 1, color: AppColors.stroke),
          InkWell(
            onTap: onManage,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gewicht verwalten',
                      style: AppText.grotesk(size: 14, weight: 600),
                    ),
                  ),
                  if (!series.isEmpty)
                    Text(
                      '${formatKg(series.latestKg!)} kg',
                      style: AppText.grotesk(
                        size: 13,
                        weight: 700,
                        color: AppColors.textMute,
                      ),
                    ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.chevron,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightSparkline extends StatelessWidget {
  const _WeightSparkline({required this.series});

  final WeightSeries series;

  @override
  Widget build(BuildContext context) {
    final origin = series.points.first.day;
    final spots = [
      for (final p in series.points)
        FlSpot(origin.daysUntil(p.day).toDouble(), p.kg),
    ];
    final minKg = series.minKg!;
    final maxKg = series.maxKg!;
    final pad = (maxKg - minKg) < 1 ? 1.0 : (maxKg - minKg) * 0.15;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.last.x <= 0 ? 1 : spots.last.x,
        minY: minKg - pad,
        maxY: maxKg + pad,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.lime,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.lime.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
      child: Column(
        children: [
          const Icon(Icons.insights, size: 48, color: AppColors.chevron),
          const SizedBox(height: 14),
          Text(
            'Noch keine Auswertung',
            style: AppText.grotesk(size: 15, weight: 700),
          ),
          const SizedBox(height: 4),
          Text(
            'Sobald du ein paar Tage einträgst, erscheint hier dein Verlauf '
            'gegen dein Ziel.',
            textAlign: TextAlign.center,
            style: AppText.grotesk(
              size: 13,
              color: AppColors.textMute,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
