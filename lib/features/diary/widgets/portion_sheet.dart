import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/i18n/enum_labels.dart';
import '../../../core/i18n/number_format.dart';
import '../../../core/nutrition/food_ref.dart';
import '../../../core/nutrition/nutrients.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/widgets/bold_controls.dart';
import '../../../data/food/food_item.dart';
import '../../../l10n/app_localizations.dart';

/// What the user chose to log.
class PickedPortion {
  const PickedPortion({required this.grams, this.label, this.count});

  final double grams;

  /// The serving that was picked, kept so reopening the entry shows the user's
  /// own choice instead of a bare gram figure.
  final String? label;
  final double? count;
}

/// Asks how much of [food] to log, showing live nutrients for the amount.
///
/// [initialGrams] pre-fills the amount when reopening a portion that already has
/// a weight — reworking a recipe ingredient rather than adding a fresh one. It
/// only applies in grams mode; a serving-based food still defaults to one
/// serving.
/// [allowFavorite] shows a star in the header that pins/unpins the food. Set
/// when logging a food (search, scan, a recipe portion) — the natural moment to
/// mark it a favourite — and left off when the sheet is only picking a recipe
/// ingredient's weight, where favouriting makes no sense.
Future<PickedPortion?> showPortionSheet(
  BuildContext context,
  FoodItem food, {
  double? initialGrams,
  bool allowFavorite = false,
}) {
  return showModalBottomSheet<PickedPortion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PortionSheet(
        food: food,
        initialGrams: initialGrams,
        allowFavorite: allowFavorite,
      ),
    ),
  );
}

class _PortionSheet extends ConsumerStatefulWidget {
  const _PortionSheet({
    required this.food,
    this.initialGrams,
    this.allowFavorite = false,
  });

  final FoodItem food;
  final double? initialGrams;
  final bool allowFavorite;

  @override
  ConsumerState<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends ConsumerState<_PortionSheet> {
  late ServingOption _serving;
  late TextEditingController _controller;
  double _count = 1;

  @override
  void initState() {
    super.initState();
    // Reopening an existing weight (editing a recipe ingredient) always lands in
    // raw mode with that exact amount; otherwise the first serving is picked at
    // its natural default (one unit, or 100 g/ml raw).
    final initial = widget.initialGrams;
    if (initial != null && initial > 0) {
      _serving = ServingOption.raw(widget.food.measure);
      _count = initial;
    } else {
      _serving = widget.food.servingChoices.first;
      _count = _serving.defaultAmount;
    }
    _controller = TextEditingController(text: _formatCount(_count));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// In raw mode the number typed is the amount (g/ml); otherwise a unit count.
  bool get _isRawMode => _serving.isRaw;

  /// The food's unit suffix — "g" for solids, "ml" for drinks.
  String get _suffix => widget.food.measure.suffix;

  double get _grams => _isRawMode ? _count : _count * _serving.grams;

  void _selectServing(ServingOption option) {
    setState(() {
      _serving = option;
      _count = option.defaultAmount;
      _controller.text = _formatCount(_count);
    });
  }

  void _setCount(double value) {
    setState(() {
      _count = value;
      _controller.text = _formatCount(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nutrients = widget.food.nutrients.forGrams(_grams);
    final choices = widget.food.servingChoices;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          0,
          AppTheme.screenPadding,
          20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.food.displayTitle,
                    style: AppText.grotesk(size: 17, weight: 700),
                  ),
                ),
                if (widget.allowFavorite) _FavoriteStar(food: widget.food),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              widget.food.ref.source.label(l10n),
              style: AppText.grotesk(
                size: 12,
                weight: 500,
                color: AppColors.textMute,
              ),
            ),
            const SizedBox(height: 16),
            // Serving units read as "Portion (30 g)", "Cookie (25 g)", "Gramm" —
            // one unit each, never "1 Portion …": the count field carries the
            // multiplier, so folding it into the label would double it.
            if (choices.length > 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in choices)
                    BoldChip(
                      label: option.isRaw
                          ? (option.measure.isLiquid
                                ? l10n.unitMilliliters
                                : l10n.unitGrams)
                          : option.label,
                      selected: option == _serving,
                      onTap: () => _selectServing(option),
                    ),
                ],
              ),
            if (choices.length > 1) const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: AppText.grotesk(size: 20, weight: 700),
                    decoration: InputDecoration(
                      labelText: _isRawMode
                          ? (widget.food.measure.isLiquid
                                ? l10n.unitMilliliters
                                : l10n.unitGrams)
                          : l10n.portionCount,
                      suffixText: _isRawMode ? _suffix : '×',
                      labelStyle: AppText.grotesk(
                        size: 13,
                        weight: 500,
                        color: AppColors.textMute,
                      ),
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
                    onChanged: (value) {
                      // German keyboards produce a decimal comma.
                      final parsed = double.tryParse(value.replaceAll(',', '.'));
                      setState(() => _count = parsed ?? 0);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                // In unit mode the resolved amount is not obvious, so show it.
                if (!_isRawMode)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '= ${_formatCount(_grams)} $_suffix',
                        style: AppText.grotesk(
                          size: 14,
                          weight: 600,
                          color: AppColors.textMute,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Quick multipliers for the common "one, two, three of them" case.
            if (!_isRawMode) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final n in const [1.0, 2.0, 3.0]) ...[
                    if (n != 1.0) const SizedBox(width: 8),
                    Expanded(
                      child: _CountChip(
                        label: '${n.round()}×',
                        selected: _count == n,
                        onTap: () => _setCount(n),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            _NutrientPreview(nutrients: nutrients),
            const SizedBox(height: 18),
            PrimaryButton(
              label: l10n.commonAdd,
              icon: Icons.check_circle,
              onPressed: _grams <= 0
                  ? null
                  : () => Navigator.of(context).pop(
                      PickedPortion(
                        grams: _grams,
                        label: _isRawMode ? null : _serving.label,
                        count: _isRawMode ? null : _count,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCount(double value) =>
      formatDecimal(value, maxDecimals: 1);
}

/// A selectable quick-count chip (1×, 2×, 3×).
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selectedRow : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      clipBehavior: Clip.antiAlias,
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
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Center(
            child: Text(
              label,
              style: AppText.grotesk(
                size: 15,
                weight: 700,
                color: selected ? AppColors.lime : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NutrientPreview extends StatelessWidget {
  const _NutrientPreview({required this.nutrients});

  final Nutrients nutrients;

  @override
  Widget build(BuildContext context) {
    final n = nutrients;
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      color: AppColors.surfaceAlt,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Value(
            label: 'KCAL',
            value: n.kcal.round().toString(),
            accent: AppColors.lime,
          ),
          _Value(
            label: l10n.macroProteinShort.toUpperCase(),
            value: n.proteinG.toStringAsFixed(0),
            accent: AppColors.protein,
          ),
          _Value(
            label: l10n.macroCarbsShort.toUpperCase(),
            value: n.carbsG.toStringAsFixed(0),
            accent: AppColors.carbs,
          ),
          _Value(
            label: l10n.macroFatShort.toUpperCase(),
            value: n.fatG.toStringAsFixed(0),
            accent: AppColors.fat,
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.anton(size: 22)),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.grotesk(
            size: 9,
            weight: 700,
            color: accent,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// Toggles a food's favourite state from the log sheet, whatever its source: a
/// custom food uses its own flag, anything else is pinned. State comes from the
/// unified [favoriteRefsProvider].
class _FavoriteStar extends ConsumerWidget {
  const _FavoriteStar({required this.food});

  final FoodItem food;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFavourite = ref.watch(favoriteRefsProvider).contains(food.ref);

    return IconButton(
      icon: Icon(isFavourite ? Icons.star : Icons.star_border),
      color: isFavourite
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant,
      tooltip: isFavourite
          ? AppLocalizations.of(context).searchRemoveFavorite
          : AppLocalizations.of(context).searchAddFavorite,
      onPressed: () {
        if (food.ref.source == FoodSourceType.custom) {
          ref
              .read(customFoodRepositoryProvider)
              .setFavorite(food.ref.id, value: !isFavourite);
        } else {
          ref.read(pinnedFoodsRepositoryProvider).toggle(food);
        }
      },
    );
  }
}
