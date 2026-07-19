import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
Future<PickedPortion?> showPortionSheet(BuildContext context, FoodItem food) {
  return showModalBottomSheet<PickedPortion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PortionSheet(food: food),
    ),
  );
}

class _PortionSheet extends StatefulWidget {
  const _PortionSheet({required this.food});

  final FoodItem food;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
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
            Text(widget.food.displayTitle, style: theme.textTheme.titleLarge),
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
