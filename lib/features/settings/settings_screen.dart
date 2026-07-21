import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/pack/off_region.dart';
import '../../data/pack/pack_service.dart';

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
    final profile = ref.watch(userProfileProvider).value;
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
                  // App preferences only — no goals. Calorie/macro/water/factor
                  // targets live on the Ziele-Seite, reached from Profil.
                  const _GroupHeader('AKTIVITÄT'),
                  _Group(
                    children: [
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
