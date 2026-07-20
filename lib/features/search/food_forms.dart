import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ids/uuid_v7.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/food/food_item.dart';

/// A quick calorie entry: a name and a kcal figure, logged directly.
///
/// Returns an ephemeral [FoodItem] the caller logs, deliberately *not* a saved
/// custom food — a quick entry is a one-off ("something at the bakery, 250
/// kcal"), and cluttering the user's food list with those defeats the point.
/// The food's default portion is 100 g at the entered per-100 g energy, so
/// logging one portion records exactly the number typed.
Future<FoodItem?> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<FoodItem>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _QuickAddSheet(),
  );
}

/// Creates a reusable custom food from name + per-100 g macros. Returns the
/// saved food so the caller can offer to log it straight away.
///
/// [initialBarcode] prefills the barcode when this is reached from a failed
/// scan, so the food the user enters becomes resolvable by a later scan.
Future<CustomFoodDraft?> showCreateFoodSheet(
  BuildContext context, {
  String? initialBarcode,
}) {
  return showModalBottomSheet<CustomFoodDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CreateFoodSheet(initialBarcode: initialBarcode),
  );
}

/// What [showCreateFoodSheet] collects. The repository turns it into a row.
class CustomFoodDraft {
  const CustomFoodDraft({
    required this.name,
    required this.nutrients,
    this.barcode,
  });

  final String name;
  final Nutrients nutrients;
  final String? barcode;
}

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet();

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _carbs = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _kcal, _carbs, _protein, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  void _submit() {
    final kcal = double.tryParse(_kcal.text.replaceAll(',', '.'));
    if (kcal == null || kcal <= 0) return;
    final name = _name.text.trim().isEmpty
        ? 'Schnell-Eintrag'
        : _name.text.trim();

    Navigator.of(context).pop(
      FoodItem(
        ref: FoodRef(FoodSourceType.custom, newId()),
        name: name,
        // The 100 g serving means the figures entered are logged as typed, so
        // the optional macros are the amounts for this one entry.
        nutrients: Nutrients(
          kcal: kcal,
          proteinG: _num(_protein),
          carbsG: _num(_carbs),
          fatG: _num(_fat),
        ),
        servings: const [ServingOption(label: 'Schnell-Eintrag', grams: 100)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'SCHNELL-EINTRAG',
      subtitle:
          'Kalorien und optional die Nährwerte. Für etwas, das du nicht als '
          'Lebensmittel speichern willst.',
      children: [
        _Field(controller: _name, label: 'Name (optional)', autofocus: false),
        const SizedBox(height: 12),
        _Field(
          controller: _kcal,
          label: 'Kalorien',
          suffix: 'kcal',
          number: true,
          autofocus: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _carbs,
                label: 'Kohlenh.',
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _protein,
                label: 'Eiweiß',
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _fat,
                label: 'Fett',
                suffix: 'g',
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'EINTRAGEN',
          icon: Icons.check_circle,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _CreateFoodSheet extends StatefulWidget {
  const _CreateFoodSheet({this.initialBarcode});

  final String? initialBarcode;

  @override
  State<_CreateFoodSheet> createState() => _CreateFoodSheetState();
}

class _CreateFoodSheetState extends State<_CreateFoodSheet> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _num(_kcal) <= 0) return;

    Navigator.of(context).pop(
      CustomFoodDraft(
        name: name,
        nutrients: Nutrients(
          kcal: _num(_kcal),
          proteinG: _num(_protein),
          carbsG: _num(_carbs),
          fatG: _num(_fat),
        ),
        barcode: widget.initialBarcode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barcode = widget.initialBarcode;
    return _SheetFrame(
      title: 'LEBENSMITTEL ANLEGEN',
      subtitle: barcode == null
          ? 'Nährwerte pro 100 g. Erscheint danach unter „Meine".'
          : 'Unbekannter Barcode $barcode. Lege das Produkt selbst an — beim '
                'nächsten Scan wird es erkannt.',
      children: [
        _Field(controller: _name, label: 'Name', autofocus: true),
        const SizedBox(height: 12),
        _Field(
          controller: _kcal,
          label: 'Kalorien',
          suffix: 'kcal',
          number: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _carbs,
                label: 'Kohlenh.',
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _protein,
                label: 'Eiweiß',
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _fat,
                label: 'Fett',
                suffix: 'g',
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'SPEICHERN',
          icon: Icons.check_circle,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Shared chrome for the two sheets: title, subtitle, keyboard-aware padding.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        20,
        AppTheme.screenPadding,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.section(size: 18)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppText.grotesk(
              size: 13,
              weight: 500,
              color: AppColors.textMute,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.suffix,
    this.number = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool number;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      style: AppText.grotesk(size: 15, weight: 600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.grotesk(
          size: 13,
          weight: 500,
          color: AppColors.textMute,
        ),
        suffixText: suffix,
        suffixStyle: AppText.grotesk(
          size: 13,
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
