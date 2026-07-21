import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/db/user_database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/weight_trend.dart';
import '../settings/settings_screen.dart';
import '../weight/weight_screen.dart';
import 'profile_edit_screen.dart';

/// Screen 7a — the profile "snapshot": who you are, your targets at a glance,
/// and your weight trend, with the ways into the body form and settings.
///
/// Follows the reworked handoff (turn 7a): weight is surfaced as its own card
/// instead of a buried list row, and the header carries a settings shortcut. The
/// three targets keep the original "DEINE ZIELE" three-`StatTile` overview.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(currentTargetProvider).value;
    final factor = ref.watch(safetyFactorProvider);
    final weight = ref.watch(latestWeightProvider).value;
    final kcal = target?.kcal ?? SettingsRepository.defaultKcal;
    final waterMl = target?.waterMl ?? SettingsRepository.defaultWaterMl;
    // Auto once computed from body stats; manual once the user typed a target.
    final isAuto = target?.isAuto ?? false;

    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        BoldHeader(
          title: 'PROFIL',
          trailing: SquareIconButton(
            icon: Icons.settings,
            tooltip: 'Einstellungen',
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ),
        const SizedBox(height: 12),
        _IdentityCard(
          weightKg: weight,
          onEdit: () => _open(context, const ProfileEditScreen()),
        ),
        SectionHeader(
          title: 'DEINE ZIELE',
          trailing: Text(
            isAuto ? 'BERECHNET' : 'MANUELL',
            style: AppText.grotesk(
              size: 10,
              weight: 700,
              color: AppColors.textFaint,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'KALORIEN',
                  value: formatKcal(kcal),
                  suffix: ' kcal',
                  accent: AppColors.lime,
                ),
              ),
              const SizedBox(width: AppTheme.rowGap),
              Expanded(
                child: StatTile(
                  label: 'WASSER',
                  value: _litres(waterMl),
                  suffix: ' L',
                  accent: AppColors.water,
                ),
              ),
              const SizedBox(width: AppTheme.rowGap),
              Expanded(
                child: StatTile(
                  label: 'FAKTOR',
                  value: factor.toStringAsFixed(2).replaceAll('.', ','),
                  accent: AppColors.coral,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.rowGap),
        _WeightCard(onTap: () => _open(context, const WeightScreen())),
        const SectionHeader(title: 'MEHR'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              BoldListRow(
                icon: Icons.straighten,
                label: 'Körperdaten & Ziel',
                subtitle: 'Kalorienziel aus Größe, Gewicht & Alter berechnen',
                onTap: () => _open(context, const ProfileEditScreen()),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.settings,
                label: 'Einstellungen',
                subtitle: 'Ziele, Sicherheitsfaktor, Anzeige',
                onTap: () => _open(context, const SettingsScreen()),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.description_outlined,
                label: 'Datenquellen & Lizenzen',
                subtitle: 'BLS 4.0 · CC BY 4.0',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'EasyTrack',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _open(BuildContext context, Widget screen) =>
      Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => screen));

  static String _litres(int ml) {
    final l = ml / 1000;
    return (l == l.roundToDouble() ? l.round().toString() : l.toString())
        .replaceAll('.', ',');
  }
}

/// Identity header card (→ Körperdaten). The original layout: monogram, name,
/// and a one-line status subtitle.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.weightKg, required this.onEdit});

  final double? weightKg;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final subtitle = weightKg == null
        ? 'LOKAL · KEIN KONTO'
        : 'AKTUELL ${_trim(weightKg!)} KG';

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.lime, width: 2),
                ),
                child: Center(
                  child: Text(
                    'ET',
                    style: AppText.anton(size: 26, color: AppColors.lime),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dein Profil',
                      style: AppText.grotesk(size: 19, weight: 700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppText.grotesk(
                        size: 11,
                        weight: 600,
                        color: AppColors.textMute,
                        letterSpacing: 0.44,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit, size: 22, color: AppColors.textMute),
            ],
          ),
        ),
      ),
    );
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}

/// The weight snapshot: current kg + change + a sparkline, or a prompt to start.
class _WeightCard extends ConsumerWidget {
  const _WeightCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(weightLogProvider).value ?? const <WeightEntry>[];
    final series = WeightSeries.of([
      for (final r in rows)
        WeightPoint(day: DayKey(r.measuredOn), kg: r.weightKg),
    ]);

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.lime, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
          child: series.isEmpty ? _emptyBody() : _dataBody(series),
        ),
      ),
    );
  }

  Widget _emptyBody() => Row(
    children: [
      const Icon(
        Icons.monitor_weight_outlined,
        size: 24,
        color: AppColors.lime,
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GEWICHT', style: _labelStyle),
            const SizedBox(height: 2),
            Text(
              'Noch nichts erfasst — tippen zum Starten',
              style: AppText.rowSubtitle(),
            ),
          ],
        ),
      ),
      const Icon(Icons.chevron_right, size: 22, color: AppColors.chevron),
    ],
  );

  Widget _dataBody(WeightSeries series) {
    final change = series.changeKg;
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GEWICHT', style: _labelStyle),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatKg(series.latestKg!),
                  style: AppText.anton(size: 26, height: 1),
                ),
                Text(
                  ' kg',
                  style: AppText.grotesk(
                    size: 12,
                    weight: 600,
                    color: AppColors.textUnit,
                  ),
                ),
              ],
            ),
            if (change != null) ...[
              const SizedBox(height: 2),
              Text(
                '${formatDelta(change)} kg',
                style: AppText.grotesk(
                  size: 11,
                  weight: 600,
                  color: AppColors.textMute,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: SizedBox(
            height: 44,
            child: series.length < 2
                ? const SizedBox.shrink()
                : _Sparkline(series: series),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right, size: 22, color: AppColors.chevron),
      ],
    );
  }

  static final _labelStyle = AppText.grotesk(
    size: 10,
    weight: 700,
    color: AppColors.textMute,
    letterSpacing: 1.2,
  );
}

/// A minimal weight sparkline — the Gewicht chart style, stripped to a line.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.series});

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
