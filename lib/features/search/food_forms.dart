import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ids/uuid_v7.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/measure_unit.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/food/food_item.dart';
import '../../l10n/app_localizations.dart';

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
    this.brand,
    this.barcode,
    this.servingG,
    this.servingUnit,
    this.measure = MeasureUnit.grams,
  });

  final String name;

  /// Whether the food is measured in grams or millilitres (a drink).
  final MeasureUnit measure;

  /// The manufacturer, kept separate from [name] so search and display can
  /// treat "Skyr" and "Arla" independently.
  final String? brand;

  final Nutrients nutrients;
  final String? barcode;

  /// An optional named serving: [servingUnit] of it weighs [servingG]. Lets a
  /// user-created food log as "1× Cookie (25 g)" instead of a bare weight.
  final double? servingG;
  final String? servingUnit;
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
        ? AppLocalizations.of(context).searchQuickEntry
        : _name.text.trim();

    Navigator.of(context).pop(
      FoodItem(
        ref: FoodRef(FoodSourceType.custom, newId()),
        name: name,
        // No named serving: it logs at the grams default (100 g) of the entered
        // per-100 g figures, so a quick entry records exactly what was typed.
        nutrients: Nutrients(
          kcal: kcal,
          proteinG: _num(_protein),
          carbsG: _num(_carbs),
          fatG: _num(_fat),
        ),
        servings: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SheetFrame(
      title: l10n.searchQuickEntry.toUpperCase(),
      subtitle: l10n.quickAddSubtitle,
      children: [
        _Field(
          controller: _name,
          label: l10n.fieldNameOptional,
          autofocus: false,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _kcal,
          label: l10n.fieldCalories,
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
                label: l10n.macroCarbsShort,
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _protein,
                label: l10n.macroProteinShort,
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _fat,
                label: l10n.macroFatShort,
                suffix: 'g',
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: l10n.shellAddTitle.toUpperCase(),
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
  final _brand = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  // Optional detail — left blank stays "unknown", not zero.
  final _sugar = TextEditingController();
  final _fiber = TextEditingController();
  final _satFat = TextEditingController();
  final _salt = TextEditingController();
  // Optional named serving ("1 Cookie = 25 g").
  final _servingUnit = TextEditingController();
  final _servingG = TextEditingController();
  // Grams for solids, millilitres for drinks.
  MeasureUnit _measure = MeasureUnit.grams;

  @override
  void dispose() {
    for (final c in [
      _name,
      _brand,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _sugar,
      _fiber,
      _satFat,
      _salt,
      _servingUnit,
      _servingG,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  /// Null when the field is empty or unparseable, so an omitted micro-nutrient
  /// stays "not known" rather than being recorded as 0 g.
  double? _optNum(TextEditingController c) {
    if (c.text.trim().isEmpty) return null;
    return double.tryParse(c.text.replaceAll(',', '.'));
  }

  String? _optText(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _num(_kcal) <= 0) return;

    final servingG = _optNum(_servingG);

    Navigator.of(context).pop(
      CustomFoodDraft(
        name: name,
        brand: _optText(_brand),
        measure: _measure,
        nutrients: Nutrients(
          kcal: _num(_kcal),
          proteinG: _num(_protein),
          carbsG: _num(_carbs),
          fatG: _num(_fat),
          sugarG: _optNum(_sugar),
          fiberG: _optNum(_fiber),
          satFatG: _optNum(_satFat),
          saltG: _optNum(_salt),
        ),
        // A serving only counts when it has a weight; the unit noun defaults to
        // "Portion" so "50 g" alone still logs as "1× Portion (50 g)".
        servingG: (servingG != null && servingG > 0) ? servingG : null,
        servingUnit: (servingG != null && servingG > 0)
            ? (_optText(_servingUnit) ??
                  AppLocalizations.of(context).servingDefaultUnit)
            : null,
        barcode: widget.initialBarcode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final barcode = widget.initialBarcode;
    final per = _measure.suffix;
    return _SheetFrame(
      title: l10n.createFoodTitle.toUpperCase(),
      subtitle: barcode == null
          ? l10n.createFoodSubtitle(per)
          : l10n.createFoodSubtitleBarcode(barcode),
      children: [
        _Field(controller: _name, label: l10n.fieldName, autofocus: true),
        const SizedBox(height: 12),
        _Field(controller: _brand, label: l10n.fieldBrandOptional),
        const SizedBox(height: 14),
        _GroupLabel(l10n.fieldUnit),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: BoldChip(
                label: l10n.measureSolid,
                selected: !_measure.isLiquid,
                onTap: () => setState(() => _measure = MeasureUnit.grams),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BoldChip(
                label: l10n.measureDrink,
                selected: _measure.isLiquid,
                onTap: () =>
                    setState(() => _measure = MeasureUnit.milliliters),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _kcal,
          label: l10n.fieldCalories,
          suffix: 'kcal',
          number: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _carbs,
                label: l10n.macroCarbsShort,
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _protein,
                label: l10n.macroProteinShort,
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _fat,
                label: l10n.macroFatShort,
                suffix: 'g',
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GroupLabel(l10n.createFoodMoreNutrients),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _sugar,
                label: l10n.fieldSugar,
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _fiber,
                label: l10n.nutrientFiber,
                suffix: 'g',
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _satFat,
                label: l10n.fieldSatFat,
                suffix: 'g',
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Field(
                controller: _salt,
                label: l10n.nutrientSalt,
                suffix: 'g',
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GroupLabel(l10n.createFoodPortion),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _Field(
                controller: _servingUnit,
                label: _measure.isLiquid
                    ? l10n.fieldServingExampleDrink
                    : l10n.fieldServingExampleSolid,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _Field(
                controller: _servingG,
                label: _measure.isLiquid ? l10n.fieldAmount : l10n.fieldWeight,
                suffix: per,
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: l10n.commonSave.toUpperCase(),
          icon: Icons.check_circle,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// A small all-caps group heading inside the create sheet.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: AppText.grotesk(
      size: 11,
      weight: 700,
      color: AppColors.textMute,
      letterSpacing: 0.8,
    ),
  );
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
    // Scrollable so the create form's extra fields stay reachable above the
    // keyboard instead of overflowing.
    return SingleChildScrollView(
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
