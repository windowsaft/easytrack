import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/nutrition/food_ref.dart';
import '../../../core/nutrition/nutrients.dart';
import '../../../data/food/food_item.dart';

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
    _serving = widget.food.servingChoices.first;
    // A serving defaults to one of it; grams default to a portion people
    // actually eat rather than a single gram.
    _count = _serving.grams == 100 ? 100 : 1;
    // Reopening an existing weight (editing a recipe ingredient): keep it, but
    // only in grams mode, where the number is grams rather than a serving count.
    final initial = widget.initialGrams;
    if (initial != null && initial > 0 && _isGramsMode) {
      _count = initial;
    }
    _controller = TextEditingController(text: _formatCount(_count));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// For the 100 g option the number typed is grams; otherwise it is a count
  /// of servings.
  bool get _isGramsMode => _serving.grams == 100 && _serving.label == '100 g';

  double get _grams => _isGramsMode ? _count : _count * _serving.grams;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nutrients = widget.food.nutrients.forGrams(_grams);
    final choices = widget.food.servingChoices;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.food.displayTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (widget.allowFavorite) _FavoriteStar(food: widget.food),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.food.sourceLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _isGramsMode ? 'Gramm' : 'Portionen',
                      suffixText: _isGramsMode ? 'g' : null,
                    ),
                    onChanged: (value) {
                      // German keyboards produce a decimal comma.
                      final parsed = double.tryParse(
                        value.replaceAll(',', '.'),
                      );
                      setState(() => _count = parsed ?? 0);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (choices.length > 1)
                  Expanded(
                    child: DropdownButtonFormField<ServingOption>(
                      initialValue: _serving,
                      decoration: const InputDecoration(labelText: 'Portion'),
                      items: [
                        for (final option in choices)
                          DropdownMenuItem(
                            value: option,
                            child: Text(option.label, maxLines: 1),
                          ),
                      ],
                      onChanged: (option) {
                        if (option == null) return;
                        setState(() {
                          _serving = option;
                          _count = option.grams == 100 ? 100 : 1;
                          _controller.text = _formatCount(_count);
                        });
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _NutrientPreview(grams: _grams, nutrients: nutrients),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Hinzufügen'),
                onPressed: _grams <= 0
                    ? null
                    : () => Navigator.of(context).pop(
                        PickedPortion(
                          grams: _grams,
                          label: _isGramsMode ? null : _serving.label,
                          count: _isGramsMode ? null : _count,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCount(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}

class _NutrientPreview extends StatelessWidget {
  const _NutrientPreview({required this.grams, required this.nutrients});

  final double grams;
  final Nutrients nutrients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = nutrients;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Value(label: 'kcal', value: n.kcal.round().toString()),
          _Value(label: 'Eiweiß', value: '${n.proteinG.toStringAsFixed(1)} g'),
          _Value(label: 'Kohlenh.', value: '${n.carbsG.toStringAsFixed(1)} g'),
          _Value(label: 'Fett', value: '${n.fatG.toStringAsFixed(1)} g'),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.labelSmall),
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
      tooltip: isFavourite ? 'Favorit entfernen' : 'Zu Favoriten',
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
