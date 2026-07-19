import 'package:flutter/material.dart';

import '../../../core/nutrition/food_ref.dart';
import '../../../core/nutrition/nutrients.dart';
import '../../../data/db/user_database.dart';

/// One meal: its entries, its subtotal, and a way to add to it.
class MealSection extends StatelessWidget {
  const MealSection({
    required this.meal,
    required this.entries,
    required this.nutrients,
    required this.onAdd,
    required this.onDelete,
    super.key,
  });

  final MealType meal;
  final List<DiaryEntry> entries;
  final Nutrients nutrients;
  final VoidCallback onAdd;
  final void Function(String entryId) onDelete;

  static const _icons = {
    MealType.breakfast: Icons.bakery_dining,
    MealType.lunch: Icons.lunch_dining,
    MealType.dinner: Icons.dinner_dining,
    MealType.snacks: Icons.cookie,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(_icons[meal], color: theme.colorScheme.primary),
            title: Text(meal.displayLabel, style: theme.textTheme.titleMedium),
            subtitle: entries.isEmpty
                ? null
                : Text('${nutrients.kcal.round()} kcal'),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '${meal.displayLabel} hinzufügen',
              onPressed: onAdd,
            ),
            onTap: onAdd,
          ),
          if (entries.isNotEmpty) ...[
            const Divider(height: 1),
            for (final entry in entries)
              Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: theme.colorScheme.errorContainer,
                  child: Icon(
                    Icons.delete,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) => onDelete(entry.id),
                child: _EntryTile(entry: entry),
              ),
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show what the user picked ("2 Scheiben") rather than the gram count they
    // never typed, falling back to grams when there was no serving.
    final amount = entry.servingLabel != null && entry.servingCount != null
        ? '${_trim(entry.servingCount!)} × ${entry.servingLabel}'
        : '${_trim(entry.amountG)} g';

    return ListTile(
      dense: true,
      title: Text(entry.nameSnapshot, maxLines: 1),
      subtitle: Text(
        '$amount · E ${entry.proteinG.round()} g · '
        'KH ${entry.carbsG.round()} g · F ${entry.fatG.round()} g',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${entry.kcal.round()} kcal',
        style: theme.textTheme.labelLarge,
      ),
    );
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}
