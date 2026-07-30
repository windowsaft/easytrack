import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/di/providers.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/i18n/language_picker.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/pack/pack_service.dart';
import '../../l10n/app_localizations.dart';
import '../backup/backup_flow.dart';
import 'pack_manager_sheet.dart';

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
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final languageIsExplicit =
        ref.read(localeControllerProvider.notifier).hasExplicitChoice;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: l10n.settingsTitle.toUpperCase(),
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: l10n.commonBack,
                onPressed: Navigator.of(context).pop,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  // App preferences only — no goals. Calorie/macro/water/factor
                  // targets live on the Ziele-Seite, reached from Profil.
                  _GroupHeader(l10n.settingsGroupActivity.toUpperCase()),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.add_circle_outline,
                        label: l10n.settingsActivityAddsBudget,
                        subtitle: l10n.settingsActivityAddsBudgetHint,
                        chevron: false,
                        trailing: BoldToggle(
                          value: profile?.activityAddsToBudget ?? true,
                          onChanged: (value) =>
                              settings.setActivityAddsToBudget(value: value),
                        ),
                      ),
                    ],
                  ),
                  _GroupHeader(l10n.settingsGroupUnitsDisplay.toUpperCase()),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.translate,
                        label: l10n.settingsLanguage,
                        value: languageIsExplicit
                            ? languageNativeName(locale.languageCode)
                            : l10n.languageSystemDefault,
                        onTap: () => showLanguagePicker(context, ref),
                      ),
                      BoldListRow(
                        icon: Icons.straighten,
                        label: l10n.settingsUnits,
                        value: l10n.settingsUnitsMetric,
                        chevron: false,
                      ),
                      BoldListRow(
                        icon: Icons.dark_mode,
                        label: l10n.settingsTheme,
                        value: l10n.settingsThemeDark,
                        chevron: false,
                      ),
                    ],
                  ),
                  _GroupHeader(l10n.settingsGroupProductData.toUpperCase()),
                  _Group(
                    children: [
                      // One entry into the unified product-database sheet:
                      // region, download/update (with progress), and file import
                      // all live there now.
                      BoldListRow(
                        icon: Icons.inventory_2_outlined,
                        label: l10n.settingsProductDatabase,
                        subtitle: _packSubtitle(l10n, packState),
                        onTap: () => showPackManagerSheet(context, ref),
                      ),
                    ],
                  ),
                  _GroupHeader(l10n.settingsGroupBackup.toUpperCase()),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.ios_share,
                        label: l10n.settingsBackupExport,
                        subtitle: l10n.settingsBackupExportHint,
                        onTap: () => exportBackup(context, ref),
                      ),
                      BoldListRow(
                        icon: Icons.settings_backup_restore,
                        label: l10n.settingsBackupRestore,
                        subtitle: l10n.settingsBackupRestoreHint,
                        onTap: () => importBackup(context, ref),
                      ),
                    ],
                  ),
                  _GroupHeader(l10n.settingsGroupDiagnostics.toUpperCase()),
                  _Group(
                    children: [
                      BoldListRow(
                        icon: Icons.article_outlined,
                        label: l10n.settingsLogExport,
                        subtitle: l10n.settingsLogExportHint,
                        onTap: () => _exportLog(context, ref),
                      ),
                      BoldListRow(
                        icon: Icons.delete_outline,
                        label: l10n.settingsLogClear,
                        subtitle: l10n.settingsLogClearHint,
                        chevron: false,
                        onTap: () => _clearLog(context),
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

  static String _packSubtitle(AppLocalizations l10n, PackInstallState? state) {
    if (state == null) {
      return l10n.settingsPackChecking;
    }
    if (!state.isInstalled) {
      return l10n.settingsPackNotLoaded;
    }
    if (state.regionChanged) {
      return l10n.settingsPackRegionChanged;
    }
    final version = state.installedVersion;
    return version == null
        ? l10n.settingsPackLoaded
        : l10n.settingsPackLoadedVersion(version);
  }

  /// Writes the App-Protokoll to a temp file and hands it to the system share
  /// sheet, so it can be mailed to yourself or dropped into a file manager.
  Future<void> _exportLog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      final info = ref.read(packageInfoProvider).value;
      final tempDir = await getTemporaryDirectory();
      final file = await AppLog.instance.exportTo(
        tempDir,
        header: _logHeader(info),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: l10n.settingsLogShareSubject,
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsLogExportFailed(error.toString()))),
      );
    }
  }

  Future<void> _clearLog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await AppLog.instance.clear();
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsLogCleared)));
  }

  /// A small header prepended to an exported protocol, so a shared log carries
  /// the build it came from and the platform it ran on.
  static String _logHeader(PackageInfo? info) {
    final version = info == null
        ? 'unbekannt'
        : '${info.version}+${info.buildNumber}';
    return 'EasyTrack $version · ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}\n'
        'Exportiert: ${DateTime.now().toIso8601String()}\n'
        '${'-' * 40}';
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
