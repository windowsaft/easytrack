import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../di/providers.dart';
import '../ui/app_theme.dart';
import '../ui/widgets/bold_controls.dart';

/// The endonym (a language's name in that language) for each language we might
/// ship. Language names are shown in their own language by convention — never
/// translated — so a Turkish speaker recognises "Türkçe" whatever the current
/// UI language is. Codes with no entry fall back to their upper-cased code,
/// which is enough to keep a freshly added translation usable before its name
/// is added here.
const _nativeNames = <String, String>{
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'pt': 'Português',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'sv': 'Svenska',
  'da': 'Dansk',
  'nb': 'Norsk',
  'fi': 'Suomi',
  'cs': 'Čeština',
  'ru': 'Русский',
  'uk': 'Українська',
  'tr': 'Türkçe',
  'ar': 'العربية',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
};

/// The display name for a language code, in that language.
String languageNativeName(String code) =>
    _nativeNames[code] ?? code.toUpperCase();

/// Wraps the chosen language so the sheet can distinguish "picked System"
/// (locale == null) from "dismissed without choosing" (the sheet returns null).
class _LangChoice {
  const _LangChoice(this.locale);
  final Locale? locale;
}

/// Opens the shared language chooser and applies the selection.
///
/// The single entry point behind both the Settings row and the onboarding
/// welcome step, so the two stay identical. Lists every language the app ships
/// a translation for (from [AppLocalizations.supportedLocales]) plus a "System
/// default" option that clears the explicit choice and follows the device.
Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final controller = ref.read(localeControllerProvider.notifier);
  final current = ref.read(localeControllerProvider);
  final hasExplicit = controller.hasExplicitChoice;

  final locales = [...AppLocalizations.supportedLocales]
    ..sort((a, b) => languageNativeName(
      a.languageCode,
    ).compareTo(languageNativeName(b.languageCode)));

  final chosen = await showModalBottomSheet<_LangChoice>(
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
            Text(
              l10n.settingsLanguage.toUpperCase(),
              style: AppText.section(size: 18),
            ),
            const SizedBox(height: 14),
            BoldListRow(
              icon: Icons.smartphone,
              label: l10n.languageSystemDefault,
              subtitle: l10n.languageSystemDefaultHint,
              chevron: false,
              highlight: !hasExplicit,
              onTap: () => Navigator.of(context).pop(const _LangChoice(null)),
            ),
            const SizedBox(height: AppTheme.rowGap),
            for (final locale in locales) ...[
              BoldListRow(
                icon: Icons.translate,
                label: languageNativeName(locale.languageCode),
                chevron: false,
                highlight:
                    hasExplicit &&
                    locale.languageCode == current.languageCode,
                onTap: () =>
                    Navigator.of(context).pop(_LangChoice(locale)),
              ),
              const SizedBox(height: AppTheme.rowGap),
            ],
          ],
        ),
      ),
    ),
  );

  if (chosen == null) return; // Dismissed.
  await controller.setLocale(chosen.locale);
}
