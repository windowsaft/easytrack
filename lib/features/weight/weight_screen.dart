import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/db/user_database.dart';
import '../../domain/weight_trend.dart';

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
  d30('30 Tage', 30),
  d90('90 Tage', 90),
  all('Alle', null);

  const _Range(this.label, this.days);
  final String label;
  final int? days;
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: 'GEWICHT',
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Zurück',
                onPressed: Navigator.of(context).pop,
              ),
              trailing: SquareIconButton(
                icon: Icons.add,
                tooltip: 'Gewicht eintragen',
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
                        const SectionHeader(title: 'EINTRÄGE'),
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
                  label: 'GEWICHT EINTRAGEN',
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
                'AKTUELL',
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
                    range.days == null ? 'GESAMT' : range.label.toUpperCase(),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        10,
        AppTheme.screenPadding,
        6,
      ),
      child: Row(
        children: [
          for (final range in _Range.values) ...[
            if (range != _Range.values.first) const SizedBox(width: 8),
            // Equal thirds so three German labels fit a phone width without the
            // fixed-width chips overflowing the row.
            Expanded(
              child: BoldChip(
                label: range.label,
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
                'Nicht genug Messungen im Zeitraum',
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
                  DateFormat(
                    'd.M.',
                    'de',
                  ).format(origin.addDays(value.round()).toDateTime()),
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
                  child: Text(
                    DateFormat('EEEE, d. MMM y', 'de').format(day.toDateTime()),
                    style: AppText.rowTitle(),
                  ),
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
              'Noch kein Gewicht erfasst',
              style: AppText.grotesk(size: 15, weight: 700),
            ),
            const SizedBox(height: 4),
            Text(
              'Trage dein Gewicht regelmäßig ein. Der Verlauf glättet die '
              'täglichen Schwankungen und dein Kalorienziel nutzt den neuesten '
              'Wert.',
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

/// 72 -> "72", 72.4 -> "72,4". German decimal comma, one place.
String formatKg(double kg) =>
    (kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1))
        .replaceAll('.', ',');

/// Signed change with a true minus sign: +1,2 / −0,5.
String formatDelta(double kg) {
  final sign = kg > 0 ? '+' : (kg < 0 ? '−' : '±');
  return '$sign${formatKg(kg.abs())}';
}

/// Asks for a weight and the day it was measured. Returns null if dismissed.
Future<({DayKey day, double kg})?> showWeightSheet(
  BuildContext context, {
  required DayKey initialDay,
  double? initialKg,
}) {
  return showModalBottomSheet<({DayKey day, double kg})>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _WeightSheet(initialDay: initialDay, initialKg: initialKg),
    ),
  );
}

class _WeightSheet extends StatefulWidget {
  const _WeightSheet({required this.initialDay, this.initialKg});

  final DayKey initialDay;
  final double? initialKg;

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
    _kg = TextEditingController(
      text: widget.initialKg == null ? '' : formatKg(widget.initialKg!),
    )..addListener(() => setState(() {}));
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

  @override
  Widget build(BuildContext context) {
    final value = _value;

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
            Text('GEWICHT EINTRAGEN', style: AppText.section(size: 18)),
            const SizedBox(height: 16),
            Row(
              children: [
                SquareIconButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Vorheriger Tag',
                  onPressed: () => setState(() => _day = _day.previous),
                ),
                Expanded(
                  child: Text(
                    _day.isToday
                        ? 'Heute'
                        : DateFormat(
                            'EEEE, d. MMM',
                            'de',
                          ).format(_day.toDateTime()),
                    textAlign: TextAlign.center,
                    style: AppText.grotesk(size: 15, weight: 600),
                  ),
                ),
                SquareIconButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Nächster Tag',
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
                labelText: 'Gewicht',
                suffixText: 'kg',
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
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'SPEICHERN',
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
