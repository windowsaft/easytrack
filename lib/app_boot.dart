import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/ui/app_theme.dart';
import 'data/backup/backup_service.dart';

/// Hosts the [ProviderScope] so the whole provider graph — the open
/// [UserDatabase] included — can be torn down and rebuilt after a data import.
///
/// A restore can't overwrite `user.sqlite` while a connection holds it, so
/// [restartForImport] first drops the ProviderScope (disposing the database
/// provider, which closes the native connection), then applies the file the
/// import staged, then mounts a fresh scope that opens the swapped database.
/// `main()` performs the same swap on a cold start, so an app kill between
/// staging and this restart still lands the import on the next launch.
class AppBoot extends StatefulWidget {
  const AppBoot({super.key});

  /// Applies a staged import and rebuilds the app onto the restored database.
  /// Call only after [BackupService.stageImport] has succeeded.
  static Future<void> restartForImport(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppBootState>();
    assert(state != null, 'AppBoot must be an ancestor to restart the app');
    return state!._applyImportAndRestart();
  }

  @override
  State<AppBoot> createState() => _AppBootState();
}

class _AppBootState extends State<AppBoot> {
  Key _scopeKey = UniqueKey();
  bool _swapping = false;

  Future<void> _applyImportAndRestart() async {
    // Render a scope-less frame first: unmounting the ProviderScope disposes the
    // UserDatabase provider, and its onDispose closes the connection so the file
    // can be replaced.
    setState(() => _swapping = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      await BackupService.applyPendingImport(
        documentsDirectory: getApplicationDocumentsDirectory,
      );
    } finally {
      if (mounted) {
        setState(() {
          // A fresh key forces a brand-new ProviderScope, so every provider —
          // and the database opening the restored file — starts clean.
          _scopeKey = UniqueKey();
          _swapping = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_swapping) {
      // Deliberately no ProviderScope: this is the frame that tears the old
      // graph (and its database connection) down before the swap.
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        color: AppColors.bg,
        home: ColoredBox(color: AppColors.bg),
      );
    }
    return ProviderScope(key: _scopeKey, child: const EasyTrackApp());
  }
}
