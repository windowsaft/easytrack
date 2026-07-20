import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/repositories/settings_repository.dart';
import '../settings/settings_screen.dart';
import '../weight/weight_screen.dart';
import 'profile_edit_screen.dart';

/// Screen 6a — who you are, your current goals at a glance, and the way into
/// settings.
///
/// Reworked from the handoff, which showed a streak, a weight figure and a
/// weight-goal progress bar — all of which need data this app does not yet
/// collect (weight logging is phase 14), so they could only have been faked.
/// This screen shows only what is real: the local profile and today's targets.
/// Every figure here is backed by an actual value.
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
      // Top-only inset: the diary shell owns the bottom bar.
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        // No settings cog: it duplicated the "Einstellungen" row below, which
        // is the one obvious way in.
        const BoldHeader(title: 'PROFIL'),
        const SizedBox(height: 12),
        _IdentityCard(weightKg: weight, onEdit: () => _openEdit(context)),
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
        const SectionHeader(title: 'MEHR'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              // Distinct destinations, not three doors to the same room.
              BoldListRow(
                icon: Icons.straighten,
                label: 'Körperdaten & Ziel',
                subtitle: 'Kalorienziel aus Größe, Gewicht & Alter berechnen',
                onTap: () => _openEdit(context),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.monitor_weight_outlined,
                label: 'Gewicht',
                subtitle: 'Verlauf erfassen und den Trend verfolgen',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const WeightScreen()),
                ),
              ),
              const SizedBox(height: AppTheme.rowGap),
              BoldListRow(
                icon: Icons.settings,
                label: 'Einstellungen',
                subtitle: 'Ziele, Sicherheitsfaktor, Anzeige',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
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

  static Future<void> _openEdit(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));

  static String _litres(int ml) {
    final l = ml / 1000;
    return (l == l.roundToDouble() ? l.round().toString() : l.toString())
        .replaceAll('.', ',');
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.weightKg, required this.onEdit});

  final double? weightKg;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // Once a weight is on record the card shows it; until then it states the
    // one fact that is always true — this is a local, account-free profile.
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
