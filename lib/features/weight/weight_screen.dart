import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/number_format.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/day_picker.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/db/user_database.dart';
import '../../domain/weight_trend.dart';
import '../../l10n/app_localizations.dart';

/// Phase 14 — the body-weight log and its trend.
///
/// Weight is stored one measurement per calendar day and feeds the TDEE
/// calculation (the profile form prefills its weight from the latest entry). The
/// chart scatters the raw weigh-ins and draws a smoothed line through them, which
/// is the honest way to read weight: day-to-day noise from water and food is
/// large next to the trend that actually matters.
class WeightScreen extends ConsumerStatefulWidget {
  const WeightScreen({super.key});

  @override
  ConsumerState<WeightScreen> createState() => _WeightScreenState();
}

enum _Range {
  d7(7),
  d30(30),
  d90(90),
  y1(365),
  all(null);

  const _Range(this.days);
  final int? days;

  String label(AppLocalizations l10n) => switch (this) {
    _Range.d7 => l10n.rangeD7,
    _Range.d30 => l10n.rangeD30,
    _Range.d90 => l10n.rangeD90,
    _Range.y1 => l10n.rangeY1,
    _Range.all => l10n.searchTabAll,
  };
}

class _WeightScreenState extends ConsumerState<WeightScreen> {
  _Range _range = _Range.d90;

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(weightLogProvider).value ?? const <WeightEntry>[];
    final series = WeightSeries.of([
      for (final r in rows)
        WeightPoint(day: DayKey(r.measuredOn), kg: r.weightKg),
    ]);

    final windowed = _range.days == null
        ? series
        : series.since(DayKey.today().addDays(-(_range.days! - 1)));

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: l10n.fieldWeight.toUpperCase(),
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: l10n.commonBack,
                onPressed: Navigator.of(context).pop,
              ),
              trailing: SquareIconButton(
                icon: Icons.add,
                tooltip: l10n.weightLog,
                onPressed: () => _add(),
              ),
            ),
            Expanded(
              child: series.isEmpty
                  ? const _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        _Summary(
                          full: series,
                          windowed: windowed,
                          range: _range,
                        ),
                        _RangeTabs(
                          current: _range,
                          onSelect: (r) => setState(() => _range = r),
                        ),
                        _ChartCard(series: windowed),
                        SectionHeader(title: l10n.weightEntries.toUpperCase()),
                        _EntryList(
                          rows: rows,
                          onEdit: (entry) => _add(
                            day: DayKey(entry.measuredOn),
                            kg: entry.weightKg,
                          ),
                          onDelete: (entry) => ref
                              .read(settingsRepositoryProvider)
                              .deleteWeight(entry.id),
                        ),
                      ],
                    ),
            ),
            if (series.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.screenPadding,
                  0,
                  AppTheme.screenPadding,
                  24,
                ),
                child: PrimaryButton(
                  label: l10n.weightLog.toUpperCase(),
                  icon: Icons.add,
                  onPressed: () => _add(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add({DayKey? day, double? kg}) async {
    final draft = await showWeightSheet(
      context,
      initialDay: day ?? DayKey.today(),
      initialKg: kg,
      lastKg: ref.read(latestWeightProvider).value,
    );
    if (draft == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .recordWeightOn(day: draft.day, kg: draft.kg);
  }
}

/// The current weight and its change over the selected range.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.full,
    required this.windowed,
    required this.range,
  });

  final WeightSeries full;
  final WeightSeries windowed;
  final _Range range;

  @override
  Widget build(BuildContext context) {
    final current = full.latestKg;
    final change = windowed.changeKg;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        8,
        AppTheme.screenPadding,
        4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.weightCurrent.toUpperCase(),
                style: AppText.grotesk(
                  size: 10,
                  weight: 700,
                  color: AppColors.textMute,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    current == null ? '—' : formatKg(current),
                    style: AppText.anton(size: 40, height: 1),
                  ),
                  Text(
                    ' kg',
                    style: AppText.grotesk(
                      size: 14,
                      weight: 600,
                      color: AppColors.textUnit,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          if (change != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDelta(change),
                    style: AppText.anton(size: 22, color: AppColors.text),
                  ),
                  Text(
                    range.days == null
                        ? l10n.weightTotal.toUpperCase()
                        : range.label(l10n).toUpperCase(),
                    style: AppText.grotesk(
                      size: 10,
                      weight: 600,
                      color: AppColors.textMute,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeTabs extends StatelessWidget {
  const _RangeTabs({required this.current, required this.onSelect});

  final _Range current;
  final ValueChanged<_Range> onSelect;

  @override
  Widget build(BuildContext context) {
    // Five ranges now, so a horizontal scroll rather than equal thirds — the
    // chips size to their content and slide if they run past the edge. The row
    // is tall enough that the chip labels are not vertically clipped.
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          10,
          AppTheme.screenPadding,
          10,
        ),
        children: [
          for (final range in _Range.values) ...[
            if (range != _Range.values.first) const SizedBox(width: 8),
            Center(
              child: BoldChip(
                label: range.label(AppLocalizations.of(context)),
                selected: current == range,
                onTap: () => onSelect(range),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The trend chart, or a placeholder until there are two points to draw a line.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.series});

  final WeightSeries series;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(6, 16, 16, 10),
      height: 220,
      child: series.length < 2
          ? Center(
              child: Text(
                AppLocalizations.of(context).weightNotEnough,
                style: AppText.grotesk(size: 13, color: AppColors.textMute),
              ),
            )
          : _TrendChart(series: series),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series});

  final WeightSeries series;

  @override
  Widget build(BuildContext context) {
    final origin = series.points.first.day;
    double x(DayKey day) => origin.daysUntil(day).toDouble();

    final rawSpots = [for (final p in series.points) FlSpot(x(p.day), p.kg)];
    final trend = series.movingAverage(7);
    final trendSpots = [for (final p in trend) FlSpot(x(p.day), p.kg)];

    final maxX = rawSpots.last.x <= 0 ? 1.0 : rawSpots.last.x;
    final minKg = series.minKg!;
    final maxKg = series.maxKg!;
    // Pad the band, and guarantee a non-zero span so the axis never collapses
    // when every reading is identical.
    final minY = (minKg - 1).floorToDouble();
    var maxY = (maxKg + 1).ceilToDouble();
    if (maxY - minY < 2) maxY = minY + 2;
    final yInterval = ((maxY - minY) / 4).ceilToDouble().clamp(1.0, 1000.0);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.stroke, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: yInterval,
              getTitlesWidget: (value, _) => Text(
                value.round().toString(),
                style: AppText.grotesk(size: 10, color: AppColors.textFaint),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: maxX,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DateFormat.Md().format(
                    origin.addDays(value.round()).toDateTime(),
                  ),
                  style: AppText.grotesk(size: 10, color: AppColors.textFaint),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          // Raw weigh-ins as a faint scatter — barWidth 0 hides the connecting
          // line, leaving just the dots.
          LineChartBarData(
            spots: rawSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 2.5,
                color: AppColors.textMute,
                strokeWidth: 0,
              ),
            ),
          ),
          // The smoothed trend.
          LineChartBarData(
            spots: trendSpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.lime,
            barWidth: 3,
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

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.rows,
    required this.onEdit,
    required this.onDelete,
  });

  /// Oldest-first from the store; shown newest-first, with each row's change
  /// measured against the entry chronologically before it.
  final List<WeightEntry> rows;
  final void Function(WeightEntry) onEdit;
  final void Function(WeightEntry) onDelete;

  @override
  Widget build(BuildContext context) {
    final reversed = rows.reversed.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Column(
        children: [
          for (var i = 0; i < reversed.length; i++) ...[
            if (i > 0) const SizedBox(height: AppTheme.rowGap),
            _EntryRow(
              entry: reversed[i],
              // The previous reading in time sits one further along the
              // reversed list.
              previousKg: i + 1 < reversed.length
                  ? reversed[i + 1].weightKg
                  : null,
              onEdit: () => onEdit(reversed[i]),
              onDelete: () => onDelete(reversed[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.previousKg,
    required this.onEdit,
    required this.onDelete,
  });

  final WeightEntry entry;
  final double? previousKg;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final day = DayKey(entry.measuredOn);
    final change = previousKg == null ? null : entry.weightKg - previousKg!;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        color: AppColors.coral,
        child: const Icon(Icons.delete, color: AppColors.bg),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.monitor_weight_outlined,
                  size: 22,
                  color: AppColors.lime,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(_entryDate(day), style: AppText.rowTitle()),
                ),
                if (change != null && change != 0) ...[
                  Text(
                    formatDelta(change),
                    style: AppText.grotesk(
                      size: 12,
                      weight: 600,
                      color: AppColors.textMute,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  '${formatKg(entry.weightKg)} kg',
                  style: AppText.rowValue(size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.monitor_weight_outlined,
              size: 48,
              color: AppColors.chevron,
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).weightEmptyTitle,
              style: AppText.grotesk(size: 15, weight: 700),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).weightEmptyBody,
              textAlign: TextAlign.center,
              style: AppText.grotesk(
                size: 13,
                color: AppColors.textMute,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 72 -> "72", 72.4 -> "72,4". Locale decimal separator, one place.
String formatKg(double kg) => formatDecimal(kg, maxDecimals: 1);

/// Signed change with a true minus sign: +1,2 / −0,5.
String formatDelta(double kg) {
  final sign = kg > 0 ? '+' : (kg < 0 ? '−' : '±');
  return '$sign${formatKg(kg.abs())}';
}

/// A compact entry date: "FR · 17. Juli" / "FRI · July 17" — an abbreviated
/// weekday and the day + month, without the year. Locale-aware via
/// [Intl.defaultLocale], which the active language pins, so both the names and
/// the day/month order follow the UI language.
String _entryDate(DayKey day) {
  final date = day.toDateTime();
  return '${DateFormat('EE').format(date).toUpperCase()} · '
      '${DateFormat.MMMMd().format(date)}';
}

/// Asks for a weight and the day it was measured. Returns null if dismissed.
///
/// [lastKg] pre-fills a brand-new entry with the most recent weigh-in, so the
/// common case — nudging yesterday's number by a few hundred grams — is a couple
/// of taps on the +/- chips rather than typing a fresh figure.
Future<({DayKey day, double kg})?> showWeightSheet(
  BuildContext context, {
  required DayKey initialDay,
  double? initialKg,
  double? lastKg,
}) {
  return showModalBottomSheet<({DayKey day, double kg})>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _WeightSheet(
        initialDay: initialDay,
        initialKg: initialKg,
        lastKg: lastKg,
      ),
    ),
  );
}

class _WeightSheet extends StatefulWidget {
  const _WeightSheet({required this.initialDay, this.initialKg, this.lastKg});

  final DayKey initialDay;
  final double? initialKg;
  final double? lastKg;

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  late DayKey _day;
  late final TextEditingController _kg;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDay;
    // Editing a day shows that day's value; a new entry starts from the last
    // weigh-in so the +/- chips have a sensible base.
    final seed = widget.initialKg ?? widget.lastKg;
    _kg = TextEditingController(text: seed == null ? '' : formatKg(seed))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_kg.text.replaceAll(',', '.'));
    return (v != null && v > 0 && v < 500) ? v : null;
  }

  bool get _atToday => _day.value >= DayKey.today().value;

  /// Opens a calendar to jump to any past day (with a Heute shortcut), rather
  /// than stepping one chevron at a time. Today is the latest selectable day —
  /// a weight cannot be recorded for a day that has not happened.
  Future<void> _pickDay() async {
    final picked = await showDayPicker(
      context,
      initial: _day,
      last: DayKey.today(),
    );
    if (picked != null) setState(() => _day = picked);
  }

  /// Nudges the field by [delta] kg, seeding from the last weigh-in when empty
  /// so the very first tap still produces a plausible number.
  void _adjust(double delta) {
    final base = _value ?? widget.lastKg ?? 70.0;
    final next = (base + delta).clamp(1.0, 499.0);
    setState(() {
      _kg.text = formatKg(double.parse(next.toStringAsFixed(1)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          20,
          AppTheme.screenPadding,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.weightLog.toUpperCase(), style: AppText.section(size: 18)),
            const SizedBox(height: 16),
            Row(
              children: [
                SquareIconButton(
                  icon: Icons.chevron_left,
                  tooltip: l10n.diaryPreviousDay,
                  onPressed: () => setState(() => _day = _day.previous),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickDay,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          // The compact "FR · 17. Juli" form the entry rows use,
                          // so the sheet's day reads the same as the list below.
                          _entryDate(_day),
                          style: AppText.grotesk(size: 15, weight: 600),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: AppColors.textMute,
                        ),
                      ],
                    ),
                  ),
                ),
                SquareIconButton(
                  icon: Icons.chevron_right,
                  tooltip: l10n.diaryNextDay,
                  // A weight cannot be recorded for a day that has not happened.
                  onPressed: _atToday
                      ? null
                      : () => setState(() => _day = _day.next),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _kg,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: AppText.grotesk(size: 20, weight: 700),
              decoration: InputDecoration(
                labelText: l10n.fieldWeight,
                suffixText: 'kg',
                helperText: widget.initialKg == null && widget.lastKg != null
                    ? l10n.weightLast(formatKg(widget.lastKg!))
                    : null,
                helperStyle: AppText.grotesk(
                  size: 12,
                  weight: 500,
                  color: AppColors.textFaint,
                ),
                labelStyle: AppText.grotesk(
                  size: 13,
                  weight: 500,
                  color: AppColors.textMute,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.strokeDashed),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.lime, width: 2),
                ),
              ),
              onSubmitted: (_) => _submit(value),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final step in const [-0.5, -0.1, 0.1, 0.5]) ...[
                  if (step != -0.5) const SizedBox(width: 8),
                  Expanded(
                    child: _AdjustChip(step: step, onTap: () => _adjust(step)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: l10n.commonSave.toUpperCase(),
              icon: Icons.check_circle,
              onPressed: value == null ? null : () => _submit(value),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(double? value) {
    if (value == null) return;
    Navigator.of(context).pop((day: _day, kg: value));
  }
}

/// A +/- quick-adjust chip for the weight field (−0,5 … +0,5 kg).
class _AdjustChip extends StatelessWidget {
  const _AdjustChip({required this.step, required this.onTap});

  final double step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sign = step > 0 ? '+' : '−';
    final magnitude = formatKg(step.abs());
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              '$sign$magnitude',
              style: AppText.grotesk(size: 14, weight: 700),
            ),
          ),
        ),
      ),
    );
  }
}
