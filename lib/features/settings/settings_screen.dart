import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/db/user_database.dart';
import '../../data/pack/off_region.dart';
import '../../data/pack/pack_service.dart';
import '../../data/repositories/settings_repository.dart';

/// Screen 6b — settings, reached from the profile.
///
/// Deviates from the handoff in one deliberate way: the ACCOUNT section
/// (subscription, log out, connected apps) is absent. EasyTrack has no account
/// and no subscription by design (`docs/plan.md`), so those rows could only
/// ever have been decoration. The DATEN section replaces them, and carries the
/// data-source attribution that the BLS licence actually requires.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsRepositoryProvider);
    final target = ref.watch(currentTargetProvider).value;
    final profile = ref.watch(userProfileProvider).value;
    final factor = ref.watch(safetyFactorProvider);
    final packState = ref.watch(packStateProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: 'EINSTELLUNGEN',
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Zurück',
                onPressed: Navigator.of(context).pop,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  const _GroupHeader('ZIELE'),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.local_fire_department,
                        label: 'Tageskalorien',
                        value:
                            '${formatKcal(target?.kcal ?? SettingsRepository.defaultKcal)} kcal',
                        onTap: () => _editKcal(context, ref, target?.kcal),
                      ),
                      BoldListRow(
                        icon: Icons.pie_chart,
                        label: 'Makro-Verteilung',
                        value: _macroSummary(target),
                        onTap: () => _editMacros(context, ref),
                      ),
                      BoldListRow(
                        icon: Icons.water_drop,
                        label: 'Wasserziel',
                        value:
                            '${target?.waterMl ?? SettingsRepository.defaultWaterMl} ml',
                        onTap: () => _editWater(context, ref, target?.waterMl),
                      ),
                      BoldListRow(
                        icon: Icons.local_drink,
                        label: 'Glasgröße',
                        value: '${ref.watch(waterCupMlProvider)} ml',
                        onTap: () => _editCup(
                          context,
                          ref,
                          ref.read(waterCupMlProvider),
                        ),
                      ),
                    ],
                  ),
                  const _GroupHeader('AKTIVITÄT'),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.shield,
                        label: 'Sicherheitsfaktor',
                        subtitle: 'Skaliert manuell erfasste Aktivität',
                        highlight: true,
                        trailing: Text(
                          factor.toStringAsFixed(2).replaceAll('.', ','),
                          style: AppText.anton(size: 18, color: AppColors.lime),
                        ),
                        onTap: () => _editFactor(context, ref, factor),
                      ),
                      BoldListRow(
                        icon: Icons.add_circle_outline,
                        label: 'Aktivität erhöht Budget',
                        subtitle: 'Verbrannte Kalorien zum Tagesziel addieren',
                        chevron: false,
                        trailing: BoldToggle(
                          value: profile?.activityAddsToBudget ?? true,
                          onChanged: (value) =>
                              settings.setActivityAddsToBudget(value: value),
                        ),
                      ),
                    ],
                  ),
                  const _GroupHeader('EINHEITEN & ANZEIGE'),
                  _Group(
                    children: [
                      const BoldListRow(
                        icon: Icons.straighten,
                        label: 'Einheiten',
                        value: 'Metrisch',
                        chevron: false,
                      ),
                      const BoldListRow(
                        icon: Icons.dark_mode,
                        label: 'Design',
                        value: 'Dunkel',
                        chevron: false,
                      ),
                    ],
                  ),
                  const _GroupHeader('PRODUKTDATEN'),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.public,
                        label: 'Region',
                        subtitle:
                            (packState?.selectedRegion ?? OffRegion.fallback)
                                .hint,
                        value: (packState?.selectedRegion ?? OffRegion.fallback)
                            .label,
                        onTap: () => _editRegion(context, ref),
                      ),
                      BoldListRow(
                        icon: Icons.inventory_2_outlined,
                        label: 'Produktdatenbank',
                        subtitle: _packSubtitle(packState),
                        onTap: () => _managePack(context, ref),
                      ),
                    ],
                  ),
                  const _GroupHeader('DATEN & RECHTLICHES'),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.info_outline,
                        label: 'Datenquellen',
                        onTap: () => _showSources(context),
                      ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ordered carbs / protein / fat, matching the design's "40 / 30 / 30".
  static String _macroSummary(TargetRow? target) {
    final protein = target?.proteinG;
    final carbs = target?.carbsG;
    final fat = target?.fatG;
    if (protein == null && carbs == null && fat == null) return 'Nicht gesetzt';
    return '${carbs?.round() ?? '–'} / ${protein?.round() ?? '–'} / '
        '${fat?.round() ?? '–'} g';
  }

  Future<void> _editKcal(
    BuildContext context,
    WidgetRef ref,
    double? current,
  ) async {
    final value = await _promptNumber(
      context,
      title: 'Tageskalorien',
      suffix: 'kcal',
      initial: current ?? SettingsRepository.defaultKcal,
    );
    if (value == null) return;
    await ref.read(settingsRepositoryProvider).setTarget(kcal: value);
  }

  Future<void> _editWater(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final value = await _promptNumber(
      context,
      title: 'Wasserziel',
      suffix: 'ml',
      initial: (current ?? SettingsRepository.defaultWaterMl).toDouble(),
    );
    if (value == null) return;
    await ref
        .read(settingsRepositoryProvider)
        .setTarget(waterMl: value.round());
  }

  Future<void> _editCup(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final value = await _promptNumber(
      context,
      title: 'Glasgröße',
      suffix: 'ml',
      initial: current.toDouble(),
    );
    if (value == null) return;
    await ref.read(settingsRepositoryProvider).setWaterCupMl(value.round());
  }

  Future<void> _editFactor(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => _FactorSheet(initial: current),
    );
    if (value == null) return;
    await ref.read(settingsRepositoryProvider).setSafetyFactor(value);
  }

  Future<void> _editMacros(BuildContext context, WidgetRef ref) async {
    final protein = await _promptNumber(
      context,
      title: 'Eiweiß',
      suffix: 'g',
      initial: 130,
    );
    if (protein == null || !context.mounted) return;

    final carbs = await _promptNumber(
      context,
      title: 'Kohlenhydrate',
      suffix: 'g',
      initial: 210,
    );
    if (carbs == null || !context.mounted) return;

    final fat = await _promptNumber(
      context,
      title: 'Fett',
      suffix: 'g',
      initial: 70,
    );
    if (fat == null) return;

    await ref
        .read(settingsRepositoryProvider)
        .setTarget(proteinG: protein, carbsG: carbs, fatG: fat);
  }

  static String _packSubtitle(PackInstallState? state) {
    if (state == null) {
      return 'Wird geprüft …';
    }
    if (!state.isInstalled) {
      return 'Open Food Facts — noch nicht geladen';
    }
    if (state.regionChanged) {
      return 'Region geändert — neu laden zum Aktualisieren';
    }
    final version = state.installedVersion;
    return version == null
        ? 'Open Food Facts — geladen'
        : 'Open Food Facts · Stand $version';
  }

  Future<void> _editRegion(BuildContext context, WidgetRef ref) async {
    final service = await ref.read(packServiceProvider.future);
    if (!context.mounted) return;
    final current = service.selectedRegion;

    final chosen = await showModalBottomSheet<OffRegion>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.screenPadding,
            20,
            AppTheme.screenPadding,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REGION', style: AppText.section(size: 18)),
              const SizedBox(height: 14),
              for (final region in OffRegion.values) ...[
                BoldListRow(
                  icon: Icons.public,
                  label: region.label,
                  subtitle: region.hint,
                  chevron: false,
                  highlight: region == current,
                  onTap: () => Navigator.of(context).pop(region),
                ),
                const SizedBox(height: AppTheme.rowGap),
              ],
            ],
          ),
        ),
      ),
    );

    if (chosen == null || chosen == current) {
      return;
    }
    await service.setRegion(chosen);
    ref.invalidate(packStateProvider);
  }

  Future<void> _managePack(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = await ref.read(packServiceProvider.future);

    messenger.showSnackBar(
      const SnackBar(content: Text('Lade Produktdaten …')),
    );
    try {
      final release = await service.install();
      // The pack file changed, so re-open it and rebuild the search stack.
      ref.invalidate(offPackProvider);
      ref.invalidate(packStateProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${release.rowCount} Produkte geladen')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Produktdaten fehlgeschlagen: $error')),
      );
    }
  }

  static void _showSources(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          20,
          AppTheme.screenPadding,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DATENQUELLEN', style: AppText.section(size: 18)),
            const SizedBox(height: 14),
            Text(
              'Bundeslebensmittelschlüssel (BLS), Version 4.0 — Deutsche '
              'Nährstoffdatenbank.\n'
              'Max Rubner-Institut (2025), Karlsruhe.\n'
              'DOI: 10.25826/Data20251217-134202-0\n'
              'Lizenz: CC BY 4.0',
              style: AppText.grotesk(
                size: 13,
                weight: 500,
                color: AppColors.textBright,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Produktdaten (Barcode-Produkte):\n'
              'Open Food Facts — beigetragen von der Open-Food-Facts-'
              'Gemeinschaft.\n'
              'openfoodfacts.org\n'
              'Lizenz: Open Database License (ODbL) v1.0',
              style: AppText.grotesk(
                size: 13,
                weight: 500,
                color: AppColors.textBright,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A single-value editor. Deliberately a plain sheet rather than a designed
  /// screen: the handoff marks these detail views as "not yet designed", and
  /// inventing one would be guessing at a direction rather than following it.
  static Future<double?> _promptNumber(
    BuildContext context, {
    required String title,
    required String suffix,
    required double initial,
  }) {
    final controller = TextEditingController(text: initial.round().toString());

    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(),
        title: Text(title, style: AppText.section(size: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppText.anton(size: 28),
          decoration: InputDecoration(
            suffixText: suffix,
            suffixStyle: AppText.grotesk(
              size: 14,
              weight: 600,
              color: AppColors.textMute,
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.strokeDashed),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.lime, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'ABBRECHEN',
              style: AppText.grotesk(
                size: 13,
                weight: 700,
                color: AppColors.textMute,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              Navigator.of(
                context,
              ).pop(parsed == null || parsed <= 0 ? null : parsed);
            },
            child: Text(
              'SPEICHERN',
              style: AppText.grotesk(
                size: 13,
                weight: 700,
                color: AppColors.lime,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppTheme.screenPadding,
      14,
      AppTheme.screenPadding,
      5,
    ),
    child: Text(
      title,
      style: AppText.anton(
        size: 14,
        color: AppColors.textMute,
        letterSpacing: 0.06,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
    child: Column(
      children: [
        for (final child in children) ...[
          if (child != children.first) const SizedBox(height: AppTheme.rowGap),
          child,
        ],
      ],
    ),
  );
}

/// Picks the safety factor from a short list. A free-text field would invite
/// values like 1.4, which would inflate the day's budget rather than guard it.
class _FactorSheet extends StatelessWidget {
  const _FactorSheet({required this.initial});

  final double initial;

  static const _options = [0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 1.0];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        20,
        AppTheme.screenPadding,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SICHERHEITSFAKTOR', style: AppText.section(size: 18)),
          const SizedBox(height: 6),
          Text(
            'Manuell erfasste Aktivität wird mit diesem Faktor multipliziert, '
            'bevor sie das Tagesbudget erhöht.',
            style: AppText.grotesk(
              size: 13,
              weight: 500,
              color: AppColors.textMute,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _options)
                BoldChip(
                  label: option.toStringAsFixed(2).replaceAll('.', ','),
                  selected: (option - initial).abs() < 0.001,
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
