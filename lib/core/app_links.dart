import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Public links for the source-available project. The repo is
/// github.com/windowsaft/easytrack; feedback is filed as GitHub issues.
const kSourceUrl = 'https://github.com/windowsaft/easytrack';
const kFeedbackUrl = 'https://github.com/windowsaft/easytrack/issues';
const kLicenseUrl =
    'https://raw.githubusercontent.com/windowsaft/easytrack/master/LICENSE';

/// Opens [url] in the external browser. Surfaces a SnackBar on failure so a
/// missing browser or an unresolvable link isn't a silent no-op.
Future<void> openExternal(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.linkOpenFailed(url))),
    );
  }
}
