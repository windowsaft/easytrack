import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/diagnostics/app_log.dart';
import '../../core/i18n/enum_labels.dart';
import '../../core/i18n/number_format.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/pack/off_region.dart';
import '../../data/pack/pack_installer.dart';
import '../../data/pack/pack_manifest.dart';
import '../../data/pack/pack_service.dart';
import '../../l10n/app_localizations.dart';

/// The unified product-database sheet: pick a region, download/update the Open
/// Food Facts pack (with live progress and a cancel), or import one from a file.
///
/// Replaces the old "tap the row → instant, opaque download" flow: the download
/// is now an explicit button that shows the size before it starts and a progress
/// bar while it runs.
Future<void> showPackManagerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _PackManagerSheet(),
  );
}

class _PackManagerSheet extends ConsumerStatefulWidget {
  const _PackManagerSheet();

  @override
  ConsumerState<_PackManagerSheet> createState() => _PackManagerSheetState();
}

class _PackManagerSheetState extends ConsumerState<_PackManagerSheet> {
  PackService? _service;
  PackInstallState? _state;
  PackManifest? _manifest;
  OffRegion _region = OffRegion.fallback;

  bool _loadingManifest = true;

  bool _downloading = false;
  bool _importing = false;
  int _received = 0;
  int _total = 0;
  PackCancelToken? _cancelToken;

  String? _resultText;
  bool _resultIsError = false;

  bool get _busy => _downloading || _importing;
  PackRelease? get _release => _manifest?.releaseFor(_region);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final service = await ref.read(packServiceProvider.future);
    final state = await service.state();
    if (!mounted) return;
    setState(() {
      _service = service;
      _state = state;
      _region = service.selectedRegion;
    });
    await _loadManifest();
  }

  Future<void> _loadManifest() async {
    final service = _service;
    if (service == null) return;
    setState(() => _loadingManifest = true);
    try {
      final manifest = await service.fetchManifest();
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _loadingManifest = false;
      });
    } catch (_) {
      // Leaves _manifest null; the action area shows "unavailable" + retry.
      if (!mounted) return;
      setState(() => _loadingManifest = false);
    }
  }

  Future<void> _selectRegion(OffRegion region) async {
    final service = _service;
    if (service == null || _busy || region == _region) return;
    await service.setRegion(region);
    ref.invalidate(packStateProvider);
    final state = await service.state();
    if (!mounted) return;
    setState(() {
      _region = region;
      _state = state;
      _resultText = null;
    });
  }

  Future<void> _download() async {
    final service = _service;
    final release = _release;
    if (service == null || release == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final token = PackCancelToken();
    setState(() {
      _downloading = true;
      _received = 0;
      _total = release.bytes;
      _cancelToken = token;
      _resultText = null;
    });
    try {
      final installed = await service.install(
        cancel: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) _total = total;
          });
        },
      );
      ref.invalidate(offPackProvider);
      ref.invalidate(packStateProvider);
      final state = await service.state();
      if (!mounted) return;
      setState(() {
        _state = state;
        _downloading = false;
        _cancelToken = null;
        _resultText = l10n.settingsPackLoadedCount(installed.rowCount);
        _resultIsError = false;
      });
    } on PackCancelledException {
      // Aborted by the user — quietly return to the idle state.
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _cancelToken = null;
        _resultText = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _cancelToken = null;
        _resultText = l10n.settingsPackFailed(error.toString());
        _resultIsError = true;
      });
    }
  }

  Future<void> _import() async {
    final service = _service;
    if (service == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final zipGroup = XTypeGroup(
      label: l10n.settingsPackZipLabel,
      extensions: const ['zip'],
      mimeTypes: const ['application/zip', 'application/x-zip-compressed'],
    );
    final picked = await openFile(acceptedTypeGroups: [zipGroup]);
    final path = picked?.path;
    if (path == null || !mounted) return;
    setState(() {
      _importing = true;
      _resultText = null;
    });
    try {
      final installed = await service.installFromZip(File(path));
      ref.invalidate(offPackProvider);
      ref.invalidate(packStateProvider);
      final state = await service.state();
      AppLog.instance.log(
        'Paket importiert: ${installed.rowCount} Produkte '
        '(${installed.version})',
        tag: 'pack',
      );
      if (!mounted) return;
      setState(() {
        _state = state;
        _importing = false;
        _resultText = l10n.settingsPackImportedCount(installed.rowCount);
        _resultIsError = false;
      });
    } catch (error) {
      AppLog.instance.log(
        'Paket-Import fehlgeschlagen',
        tag: 'pack',
        level: LogLevel.error,
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _importing = false;
        _resultText = l10n.settingsPackImportFailed(error.toString());
        _resultIsError = true;
      });
    }
  }

  /// Whole megabytes, locale-formatted: 63512576 -> "61".
  String _mb(num bytes) => formatInt(bytes / 1048576);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          20,
          AppTheme.screenPadding,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: _service == null
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _content(l10n),
                ),
              ),
      ),
    );
  }

  List<Widget> _content(AppLocalizations l10n) => [
    Text(
      l10n.settingsProductDatabase.toUpperCase(),
      style: AppText.section(size: 18),
    ),
    const SizedBox(height: 8),
    Text(
      l10n.settingsPackManageHint,
      style: AppText.rowSubtitle(color: AppColors.textMute),
    ),
    const SizedBox(height: 18),
    Text(l10n.settingsRegion.toUpperCase(), style: AppText.overline()),
    const SizedBox(height: 8),
    for (final region in OffRegion.values) ...[
      BoldListRow(
        icon: Icons.public,
        label: region.label(l10n),
        subtitle: region.hint(l10n),
        chevron: false,
        highlight: region == _region,
        onTap: _busy ? null : () => _selectRegion(region),
      ),
      const SizedBox(height: AppTheme.rowGap),
    ],
    const SizedBox(height: 18),
    ..._actionArea(l10n),
    if (_resultText != null) ...[
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _resultIsError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: _resultIsError ? AppColors.text : AppColors.lime,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _resultText!,
              style: AppText.rowSubtitle(color: AppColors.text),
            ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 20),
    OutlineActionButton(
      label: l10n.settingsLoadPackFromFile,
      icon: Icons.folder_zip_outlined,
      onPressed: _busy ? null : _import,
    ),
  ];

  List<Widget> _actionArea(AppLocalizations l10n) {
    if (_downloading) {
      return [
        _progressBar(_total > 0 ? _received / _total : null),
        const SizedBox(height: 8),
        Text(
          l10n.settingsPackDownloadingProgress(
            _mb(_received),
            _mb(_total > 0 ? _total : _received),
          ),
          style: AppText.rowSubtitle(color: AppColors.textMute),
        ),
        const SizedBox(height: 12),
        OutlineActionButton(
          label: l10n.commonCancel,
          icon: Icons.close,
          onPressed: () => _cancelToken?.cancel(),
        ),
      ];
    }
    if (_importing) {
      return [
        _progressBar(null),
        const SizedBox(height: 8),
        Text(
          l10n.settingsPackImporting,
          style: AppText.rowSubtitle(color: AppColors.textMute),
        ),
      ];
    }
    if (_loadingManifest) {
      return [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.settingsPackChecking,
              style: AppText.rowSubtitle(color: AppColors.textMute),
            ),
          ],
        ),
      ];
    }
    final release = _release;
    if (release == null) {
      // Manifest unreachable, or the selected region has no pack.
      return [
        Text(
          l10n.settingsPackUnavailable,
          style: AppText.rowSubtitle(color: AppColors.text),
        ),
        const SizedBox(height: 10),
        OutlineActionButton(
          label: l10n.commonRetry,
          icon: Icons.refresh,
          onPressed: _loadManifest,
        ),
      ];
    }

    final state = _state;
    final size = '${_mb(release.bytes)} MB';
    final installedMatches = state != null &&
        state.isInstalled &&
        !state.regionChanged &&
        state.installedVersion == release.version;

    if (installedMatches) {
      return [
        Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 18, color: AppColors.lime),
            const SizedBox(width: 8),
            Text(
              l10n.settingsPackUpToDate,
              style: AppText.rowSubtitle(color: AppColors.textMute),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlineActionButton(
          label: l10n.settingsPackRedownloadAction(size),
          icon: Icons.download,
          onPressed: _download,
        ),
      ];
    }

    final isUpdate = state != null &&
        state.isInstalled &&
        !state.regionChanged &&
        state.installedVersion != release.version;
    return [
      PrimaryButton(
        label: isUpdate
            ? l10n.settingsPackUpdateAction(size)
            : l10n.settingsPackDownloadAction(size),
        icon: Icons.download,
        onPressed: _download,
      ),
    ];
  }

  Widget _progressBar(double? value) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 8,
      backgroundColor: AppColors.surfaceAlt,
      color: AppColors.lime,
    ),
  );
}
