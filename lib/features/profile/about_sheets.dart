import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_links.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';

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

/// The privacy sheet: states plainly how data flows, including the one place
/// the app talks to the network (the Open Food Facts online fallback). Mirrors
/// the "Privacy, precisely" section on the marketing site, word for word.
void showPrivacy(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
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
              Text('DATENSCHUTZ', style: AppText.section(size: 18)),
              const SizedBox(height: 6),
              Text(
                'Kein Kleingedrucktes. So funktioniert es genau:',
                style: AppText.grotesk(
                  size: 13,
                  weight: 500,
                  color: AppColors.textMute,
                ),
              ),
              const SizedBox(height: 18),
              _PrivacyPoint(
                title: 'Deine Daten bleiben hier',
                body:
                    'Tagebuch, Gewicht und Ziele liegen nur auf diesem Gerät '
                    '— niemals mit einem Server synchronisiert. Du kannst '
                    'alles jederzeit als ZIP exportieren, das nur dir gehört.',
              ),
              _PrivacyPoint(
                title: 'Lebensmittelsuche, erklärt',
                body:
                    'Rund 300.000 Lebensmittel sind für die Offline-Suche '
                    'dabei (BLS 4.0 + Open Food Facts). Nur ein unbekannter '
                    'Barcode oder eine ausdrückliche „Online suchen“-Anfrage '
                    'geht an Open Food Facts — öffentliche Produktdaten, lokal '
                    'zwischengespeichert. Dein Tagebuch wird dabei nie '
                    'übertragen.',
              ),
              _PrivacyPoint(
                title: 'Nichts vom Üblichen',
                body:
                    'Kein Konto. Keine Analyse. Keine Drittanbieter-Tracker. '
                    'Keine Werbung. Es gibt nichts abzuwählen, weil nichts '
                    'davon vorhanden ist.',
              ),
            ],
          ),
        ),
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
            const SizedBox(height: 18),
            // Source-available project: the code lives on GitHub, feedback is
            // filed as issues there. Chips rather than list rows keep the About
            // sheet compact.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                BoldChip(
                  label: 'Quellcode',
                  icon: Icons.code,
                  selected: false,
                  radius: AppRadii.chip,
                  onTap: () => openExternal(context, kSourceUrl),
                ),
                BoldChip(
                  label: 'Feedback',
                  icon: Icons.chat_bubble_outline,
                  selected: false,
                  radius: AppRadii.chip,
                  onTap: () => openExternal(context, kFeedbackUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.grotesk(
              size: 14,
              weight: 700,
              color: AppColors.lime,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: AppText.grotesk(
              size: 13,
              weight: 500,
              color: AppColors.textBright,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
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
