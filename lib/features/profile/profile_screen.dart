import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/number_format.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        BoldHeader(
          overline: l10n.profileOverline.toUpperCase(),
          title: l10n.navProfile.toUpperCase(),
        ),
        const SizedBox(height: 8),
        // DEINE ZIELE — the original three-StatTile overview, kept, now a
        // doorway into the Ziele-Seite where the targets are viewed and edited.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(context, const GoalsScreen()),
            child: Column(
              children: [
                SectionHeader(title: l10n.goalsTitle.toUpperCase()),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.screenPadding,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: l10n.fieldCalories.toUpperCase(),
                          value: formatKcal(kcal),
                          suffix: ' kcal',
                          accent: AppColors.lime,
                        ),
                      ),
                      const SizedBox(width: AppTheme.rowGap),
                      Expanded(
                        child: StatTile(
                          label: l10n.diaryWater.toUpperCase(),
                          value: _litres(waterMl),
                          suffix: ' L',
                          accent: AppColors.water,
                        ),
                      ),
                      const SizedBox(width: AppTheme.rowGap),
                      Expanded(
                        child: StatTile(
                          label: l10n.profileFactor.toUpperCase(),
                          value: formatFixed(factor, 2),
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
                              ? l10n.profileGoalsAuto
                              : l10n.profileGoalsManual,
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
        SectionHeader(title: l10n.profileMore.toUpperCase()),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              BoldListRow(
                icon: Icons.monitor_weight_outlined,
                label: l10n.fieldWeight,
                subtitle: weight == null ? l10n.profileNoWeight : null,
                value: weight == null ? null : '${_trim(weight)} kg',
                onTap: () => _open(context, const WeightScreen()),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.settings,
                label: l10n.settingsTitle,
                subtitle: l10n.profileSettingsSubtitle,
                onTap: () => _open(context, const SettingsScreen()),
              ),
            ],
          ),
        ),
        SectionHeader(title: l10n.profileDataLegal.toUpperCase()),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              BoldListRow(
                icon: Icons.lock_outline,
                label: l10n.profilePrivacy,
                subtitle: l10n.profilePrivacySubtitle,
                onTap: () => showPrivacy(context),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.info_outline,
                label: l10n.profileDataSources,
                subtitle: 'BLS 4.0 · Open Food Facts',
                onTap: () => showDataSources(context),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.description_outlined,
                label: l10n.profileLicenses,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'EasyTrack',
                ),
              ),
            ],
          ),
        ),
        SectionHeader(title: l10n.profileAbout.toUpperCase()),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: BoldListRow(
            icon: Icons.info_outline,
            label: l10n.profileAboutApp,
            subtitle: versionLine(l10n, info),
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

  static String _litres(int ml) => formatDecimal(ml / 1000, maxDecimals: 3);

  static String _trim(double value) => formatDecimal(value, maxDecimals: 1);
}
