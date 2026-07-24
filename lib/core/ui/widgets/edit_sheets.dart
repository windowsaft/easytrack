import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../app_theme.dart';
import 'bold_controls.dart';

/// A single-value number editor. A plain dialog rather than a designed screen —
/// the handoff marks these detail views as "not yet designed". Shared by the
/// goals page and the Körperdaten calculator's overridable rows.
Future<double?> promptNumber(
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
            AppLocalizations.of(context).commonCancel.toUpperCase(),
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
            AppLocalizations.of(context).commonSave.toUpperCase(),
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

/// Picks the activity safety factor from a short list. A free-text field would
/// invite values like 1.4, which would inflate the day's budget rather than
/// guard it.
Future<double?> promptFactor(BuildContext context, {required double initial}) =>
    showModalBottomSheet<double>(
      context: context,
      builder: (context) => _FactorSheet(initial: initial),
    );

class _FactorSheet extends StatelessWidget {
  const _FactorSheet({required this.initial});

  final double initial;

  static const _options = [0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 1.0];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          Text(l10n.factorTitle.toUpperCase(), style: AppText.section(size: 18)),
          const SizedBox(height: 6),
          Text(
            l10n.factorHint,
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
