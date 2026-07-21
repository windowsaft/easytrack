import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/repositories/settings_repository.dart';
import '../goals/goals_screen.dart';
import '../settings/settings_screen.dart';
import '../weight/weight_screen.dart';
import 'about_sheets.dart';

/// Screen 10a/12a — Profil: a glance at the targets and the doorways out.
///
/// Follows the "one home per thing" IA (turn 10b): no identity banner, no charts
/// here. The three-target overview is a doorway to the Ziele-Seite; weight is a
/// value + chevron into Gewicht; everything else lives behind the MEHR rows.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(currentTargetProvider).value;
    final factor = ref.watch(safetyFactorProvider);
    final weight = ref.watch(latestWeightProvider).value;
    final info = ref.watch(packageInfoProvider).value;
    final kcal = target?.kcal ?? SettingsRepository.defaultKcal;
    final waterMl = target?.waterMl ?? SettingsRepository.defaultWaterMl;
    final isAuto = target?.isAuto ?? false;

    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        const BoldHeader(overline: 'LOKAL · KEIN KONTO', title: 'PROFIL'),
        const SizedBox(height: 8),
        // DEINE ZIELE — the original three-StatTile overview, kept, now a
        // doorway into the Ziele-Seite where the targets are viewed and edited.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(context, const GoalsScreen()),
            child: Column(
              children: [
                const SectionHeader(title: 'DEINE ZIELE'),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.screenPadding,
                    8,
                    AppTheme.screenPadding,
                    0,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAuto
                              ? 'Berechnet · antippen, um Ziele anzupassen'
                              : 'Manuell · antippen, um Ziele anzupassen',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.grotesk(
                            size: 11,
                            weight: 500,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.chevron,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'MEHR'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              BoldListRow(
                icon: Icons.monitor_weight_outlined,
                label: 'Gewicht',
                subtitle: weight == null ? 'Noch nichts erfasst' : null,
                value: weight == null ? null : '${_trim(weight)} kg',
                onTap: () => _open(context, const WeightScreen()),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.settings,
                label: 'Einstellungen',
                subtitle: 'App, Anzeige, Produktdaten',
                onTap: () => _open(context, const SettingsScreen()),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'DATEN & RECHTLICHES'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              BoldListRow(
                icon: Icons.info_outline,
                label: 'Datenquellen',
                subtitle: 'BLS 4.0 · Open Food Facts',
                onTap: () => showDataSources(context),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.description_outlined,
                label: 'Lizenzen',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'EasyTrack',
                ),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'ÜBER'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: BoldListRow(
            icon: Icons.info_outline,
            label: 'Über EasyTrack',
            subtitle: versionLine(info),
            onTap: () => showAbout(context, info),
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

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}
