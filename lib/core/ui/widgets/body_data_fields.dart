import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/tdee.dart';
import '../app_theme.dart';

/// The underlined numeric field used by the body-data calculator: a decimal
/// keyboard, a muted label and unit suffix, and the lime focus underline.
///
/// Shared by the Körperdaten calculator and onboarding so both screens ask for
/// height/weight/age in exactly the same control.
class LabeledNumberField extends StatelessWidget {
  const LabeledNumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: AppText.grotesk(size: 16, weight: 600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.grotesk(
          size: 13,
          weight: 500,
          color: AppColors.textMute,
        ),
        suffixText: suffix,
        suffixStyle: AppText.grotesk(
          size: 12,
          weight: 600,
          color: AppColors.textMute,
        ),
        isDense: true,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.strokeDashed),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lime, width: 2),
        ),
      ),
    );
  }
}

/// A selectable activity-level row: label, hint, and the ×factor multiplier,
/// with the lime left-border treatment when selected.
///
/// Shared by the Körperdaten calculator and onboarding.
class ActivityLevelRow extends StatelessWidget {
  const ActivityLevelRow({
    required this.level,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ActivityLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selectedRow : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: selected
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.lime, width: 3),
                  ),
                )
              : null,
          padding: EdgeInsets.fromLTRB(selected ? 11 : 14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.label,
                      style: AppText.grotesk(size: 14, weight: 600),
                    ),
                    const SizedBox(height: 2),
                    Text(level.hint, style: AppText.rowSubtitle()),
                  ],
                ),
              ),
              Text(
                '×${level.factor}',
                style: AppText.anton(
                  size: 16,
                  color: selected ? AppColors.lime : AppColors.textMute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
