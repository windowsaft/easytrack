import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/di/providers.dart';
import '../../core/i18n/number_format.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/db/user_database.dart';
import '../../domain/history.dart';
import '../../domain/weight_trend.dart';
import '../../l10n/app_localizations.dart';
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

extension on HistoryUnit {
  String label(AppLocalizations l10n) => switch (this) {
    HistoryUnit.week => l10n.historyWeek,
    HistoryUnit.month => l10n.historyMonth,
  };
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Which stretch of days is on screen. The stepping and clamping rules live
  /// in [HistoryRange] so they are unit-testable away from the widget.
  HistoryRange _range = const HistoryRange(HistoryUnit.week);

  @override
  Widget build(BuildContext context) {
    final today = DayKey.today();
    final weekStart = ref.watch(weekStartProvider);
    final range = _range.days(today, weekStart);
    final days = ref.watch(historyProvider(range)).value ?? const <DayHistory>[];
    final summary = HistorySummary.of(days);
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        BoldHeader(title: l10n.navHistory.toUpperCase()),
        _PeriodTabs(
          current: _range.unit,
          onSelect: (unit) => setState(() => _range = _range.withUnit(unit)),
        ),
        _RangeBar(
          label: _rangeLabel(l10n, range),
          canForward: _range.canStepForward(today),
          onStep: (direction) =>
              setState(() => _range = _range.step(direction, today)),
          onPickCustom: () => _pickCustom(range),
        ),
        if (summary.daysLogged == 0)
          const _EmptyState()
        else ...[
          SectionHeader(
            title: l10n.fieldCalories.toUpperCase(),
            trailing: Text(
              l10n.historyAvgKcal(summary.avgKcal.round()),
              style: AppText.grotesk(
                size: 11,
                weight: 600,
                color: AppColors.textMute,
                letterSpacing: 0.4,
              ),
            ),
          ),
          _KcalCard(days: days),
          SectionHeader(title: l10n.historyOverview.toUpperCase()),
          _TilePair(
            left: StatTile(
              label: l10n.historyAdherence.toUpperCase(),
              value: '${summary.adherentDays}',
              suffix: '/${summary.periodDays}',
              accent: AppColors.lime,
            ),
            right: StatTile(
              label: l10n.historyAvgDeviation.toUpperCase(),
              value: _signedKcal(summary.avgDeviation),
              suffix: ' kcal',
              accent: AppColors.violet,
            ),
          ),
          const SizedBox(height: AppTheme.rowGap),
          _TilePair(
            left: StatTile(
              label: l10n.historyWaterAvg.toUpperCase(),
              value: _litres(summary.avgWaterMl),
              suffix: ' L',
              accent: AppColors.water,
            ),
            right: StatTile(
              label: l10n.historyActivityAvg.toUpperCase(),
              value: '${summary.avgActivityKcal.round()}',
              suffix: ' kcal',
              accent: AppColors.coral,
            ),
          ),
          SectionHeader(title: l10n.historyMacroSplitAvg.toUpperCase()),
          _MacroSplitCard(summary: summary),
        ],
        SectionHeader(title: l10n.fieldWeight.toUpperCase()),
        _WeightTrendCard(
          onManage: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => const WeightScreen())),
        ),
      ],
    );
  }

  Future<void> _pickCustom(({DayKey from, DayKey to}) current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DayKey.today().toDateTime(),
      initialDateRange: DateTimeRange(
        start: current.from.toDateTime(),
        end: current.to.toDateTime(),
      ),
    );
    if (picked == null) return;
    setState(
      () => _range = _range.withCustom(
        DayKey.fromDate(picked.start),
        DayKey.fromDate(picked.end),
      ),
    );
  }

  String _rangeLabel(AppLocalizations l10n, ({DayKey from, DayKey to}) range) {
    if (_range.isRolling) return l10n.historyLastDays(_range.unit.rollingDays);
    // A whole calendar month names itself; a week has to spell its ends out.
    if (_range.custom == null && _range.unit == HistoryUnit.month) {
      return DateFormat.yMMMM().format(range.from.toDateTime());
    }
    return '${_dayLabel(range.from)} – ${_dayLabel(range.to)}';
  }

  /// Day and month, plus the year once the range has walked out of this one.
  static String _dayLabel(DayKey day) {
    final date = day.toDateTime();
    return day.year == DayKey.today().year
        ? DateFormat.MMMd().format(date)
        : DateFormat.yMMMd().format(date);
  }

  static String _signedKcal(double kcal) {
    final n = kcal.round();
    final sign = n > 0 ? '+' : (n < 0 ? '−' : '±');
    return '$sign${n.abs()}';
  }

  static String _litres(double ml) => formatFixed(ml / 1000, 1);
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.current, required this.onSelect});

  final HistoryUnit current;
  final ValueChanged<HistoryUnit> onSelect;

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
          for (final unit in HistoryUnit.values) ...[
            if (unit != HistoryUnit.values.first) const SizedBox(width: 8),
            Expanded(
              child: BoldChip(
                label: unit.label(AppLocalizations.of(context)),
                selected: current == unit,
                onTap: () => onSelect(unit),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which stretch of days is on screen, with chevrons to walk it.
///
/// The label is the control for a hand-picked range: the calendar glyph next to
/// it is what advertises that, since the tap itself is invisible.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.label,
    required this.canForward,
    required this.onStep,
    required this.onPickCustom,
  });

  final String label;
  final bool canForward;
  final ValueChanged<int> onStep;
  final VoidCallback onPickCustom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        0,
        AppTheme.screenPadding,
        8,
      ),
      child: Row(
        children: [
          SquareIconButton(
            icon: Icons.chevron_left,
            size: 34,
            iconSize: 20,
            tooltip: l10n.historyPreviousRange,
            onPressed: () => onStep(-1),
          ),
          Expanded(
            child: InkWell(
              onTap: onPickCustom,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.grotesk(
                          size: 12,
                          weight: 700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.calendar_month,
                      size: 15,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Opacity(
            opacity: canForward ? 1 : 0.3,
            child: SquareIconButton(
              icon: Icons.chevron_right,
              size: 34,
              iconSize: 20,
              tooltip: l10n.historyNextRange,
              onPressed: canForward ? () => onStep(1) : null,
            ),
          ),
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

      // Today is still being logged, so it reads as muted rather than as a real
      // over/under verdict. Tested by date, not by position: a range paged into
      // the past ends on a finished day that deserves its verdict.
      final color = !day.hasData || day.day.isToday
          ? AppColors.surfaceAlt
          : (day.isOverTarget ? AppColors.coral : AppColors.lime);

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
      // Locale-aware weekday abbreviation via Intl.defaultLocale (pinned by the
      // active language); day-of-month numbers for longer spans.
      final text = n <= 10 ? DateFormat('EE').format(date) : '${date.day}';
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
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Row(
                children: [
                  _MacroLabel(l10n.macroCarbsShort, AppColors.carbs, split.carbs),
                  _MacroLabel(l10n.macroProteinShort, AppColors.protein, split.protein),
                  _MacroLabel(l10n.macroFatShort, AppColors.fat, split.fat),
                ],
              );
            },
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
                    ? AppLocalizations.of(context).historyNoWeight
                    : AppLocalizations.of(context).historyTrendFromSecond,
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
                      AppLocalizations.of(context).historyManageWeight,
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
            AppLocalizations.of(context).historyEmptyTitle,
            style: AppText.grotesk(size: 15, weight: 700),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).historyEmptyBody,
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
