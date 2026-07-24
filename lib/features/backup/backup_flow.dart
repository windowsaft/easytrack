import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_boot.dart';
import '../../core/di/providers.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/backup/backup_service.dart';
import '../../l10n/app_localizations.dart';

/// Shared export/import flows, reused by Einstellungen and by onboarding's
/// "restore" affordance. Both surface progress and errors as snackbars, so they
/// need a [context] under a [ScaffoldMessenger] (every screen here has one).

/// Builds a backup zip and hands it to the system share sheet. Because the file
/// carries an `application/zip` type, the sheet lists the Files app ("In Datei
/// speichern") alongside the usual share targets — that is the save-to-folder
/// path on Android.
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.backupCreating)),
  );
  try {
    final service = await ref.read(backupServiceProvider.future);
    final zip = await service.exportToZip();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zip.path, mimeType: 'application/zip')],
        subject: l10n.backupShareSubject,
        text: l10n.backupShareText,
      ),
    );
    AppLog.instance.log('Sicherung exportiert', tag: 'backup');
  } on Object catch (error, stack) {
    AppLog.instance.log(
      'Export fehlgeschlagen',
      tag: 'backup',
      level: LogLevel.error,
      error: error,
      stack: stack,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.backupExportFailed(_message(error)))),
    );
  }
}

/// Picks a backup zip, verifies it, asks for confirmation (the restore replaces
/// all current data), then restarts the app onto the restored database. Nothing
/// is written to the live database until the confirmed restart, so cancelling or
/// picking an invalid file leaves the current data untouched.
Future<void> importBackup(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final zipGroup = XTypeGroup(
    label: l10n.backupZipLabel,
    extensions: const ['zip'],
    mimeTypes: const ['application/zip', 'application/x-zip-compressed'],
  );
  final picked = await openFile(acceptedTypeGroups: [zipGroup]);
  final path = picked?.path;
  if (path == null) return; // Cancelled.
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final service = await ref.read(backupServiceProvider.future);

  final BackupInfo info;
  try {
    info = await service.stageImport(File(path));
  } on Object catch (error, stack) {
    AppLog.instance.log(
      'Import-Prüfung fehlgeschlagen',
      tag: 'backup',
      level: LogLevel.error,
      error: error,
      stack: stack,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.backupImportFailed(_message(error)))),
    );
    return;
  }

  if (!context.mounted) {
    await service.discardStaged();
    return;
  }

  final confirmed = await _confirmRestore(context, info);
  if (confirmed != true) {
    await service.discardStaged();
    return;
  }

  AppLog.instance.log(
    'Import bestätigt (${info.entryCount} Einträge)',
    tag: 'backup',
  );
  if (!context.mounted) return;
  // Applies the staged file and rebuilds the app onto it.
  await AppBoot.restartForImport(context);
}

/// A themed confirm sheet spelling out that a restore overwrites everything,
/// with what the picked backup holds so the user can tell it is the right one.
Future<bool?> _confirmRestore(BuildContext context, BackupInfo info) {
  final l10n = AppLocalizations.of(context);
  final created = info.createdAt?.toLocal();
  final createdLabel = created == null
      ? null
      : DateFormat('d. MMMM y, HH:mm').format(created);

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          20,
          AppTheme.screenPadding,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupRestoreTitle.toUpperCase(), style: AppText.section(size: 18)),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.event_note_outlined,
              label: l10n.backupEntryCount(info.entryCount),
            ),
            if (createdLabel != null) ...[
              const SizedBox(height: 10),
              _InfoRow(icon: Icons.schedule, label: createdLabel),
            ],
            if (info.appVersion != null) ...[
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.info_outline,
                label: l10n.backupAppVersion(info.appVersion!),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  left: BorderSide(color: AppColors.coral, width: 3),
                ),
              ),
              child: Text(
                l10n.backupReplaceWarning,
                style: AppText.grotesk(
                  size: 13,
                  weight: 500,
                  color: AppColors.text,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: l10n.backupReplaceRestart.toUpperCase(),
              icon: Icons.restore,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            OutlineActionButton(
              label: l10n.commonCancel.toUpperCase(),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.lime),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppText.grotesk(size: 14, weight: 600, color: AppColors.text),
          ),
        ),
      ],
    );
  }
}

String _message(Object error) =>
    error is BackupException ? error.message : error.toString();
