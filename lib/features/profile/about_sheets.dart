import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/ui/app_theme.dart';

/// "Version 1.0.0 · Build 1", or a placeholder while [PackageInfo] loads.
String versionLine(PackageInfo? info) => info == null
    ? 'Version wird geladen …'
    : 'Version ${info.version} · Build ${info.buildNumber}';

/// The data-source attribution sheet (BLS CC BY 4.0 + OFF ODbL), which the
/// licences require the app to display.
void showDataSources(BuildContext context) {
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

/// The About sheet: app identity plus version / build / package details.
void showAbout(BuildContext context, PackageInfo? info) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          22,
          AppTheme.screenPadding,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 52,
                    height: 52,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EasyTrack', style: AppText.anton(size: 26)),
                    const SizedBox(height: 2),
                    Text(
                      versionLine(info),
                      style: AppText.grotesk(
                        size: 12,
                        weight: 600,
                        color: AppColors.textMute,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Lokal-first Kalorien- & Ernährungstracker. Kein Konto, kein '
              'Abo, funktioniert offline.',
              style: AppText.grotesk(
                size: 13,
                weight: 500,
                color: AppColors.textBright,
                height: 1.5,
              ),
            ),
            if (info != null) ...[
              const SizedBox(height: 14),
              _AboutRow('Paket', info.packageName),
              _AboutRow('Version', info.version),
              _AboutRow('Build', info.buildNumber),
            ],
          ],
        ),
      ),
    ),
  );
}

class _AboutRow extends StatelessWidget {
  const _AboutRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppText.grotesk(
                size: 12,
                weight: 600,
                color: AppColors.textMute,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: AppText.grotesk(size: 13, weight: 600)),
          ),
        ],
      ),
    );
  }
}
