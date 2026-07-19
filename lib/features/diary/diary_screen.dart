import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/ui/app_theme.dart';
import '../../domain/day_summary.dart';
import '../search/food_search_screen.dart';
import 'widgets/day_header.dart';
import 'widgets/meal_section.dart';
import 'widgets/portion_sheet.dart';

/// The day view: four meals, running totals and the remaining budget.
class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final summary = ref.watch(daySummaryProvider(day));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tagebuch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Heute',
            onPressed: () => ref.read(selectedDayProvider.notifier).goToToday(),
          ),
        ],
      ),
      body: switch (summary) {
        AsyncData(:final value) => _DayView(summary: value),
        AsyncError(:final error) => Center(child: Text('Fehler: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        DayHeader(summary: summary),
        const SizedBox(height: 8),
        for (final meal in MealType.values) ...[
          MealSection(
            meal: meal,
            entries: summary.entriesFor(meal),
            nutrients: summary.nutrientsFor(meal),
            onAdd: () => _addFood(context, ref, meal),
            onDelete: (entryId) =>
                ref.read(diaryRepositoryProvider).deleteEntry(entryId),
          ),
          const SizedBox(height: 8),
        ],
        _WaterCard(summary: summary),
      ],
    );
  }

  Future<void> _addFood(
    BuildContext context,
    WidgetRef ref,
    MealType meal,
  ) async {
    final day = ref.read(selectedDayProvider);
    final repository = ref.read(diaryRepositoryProvider);

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          meal: meal,
          onPicked: (food) async {
            final navigator = Navigator.of(context);
            final portion = await showPortionSheet(context, food);
            if (portion == null) return;

            await repository.addEntry(
              day: day,
              meal: meal,
              food: food,
              amountG: portion.grams,
              servingLabel: portion.label,
              servingCount: portion.count,
            );
            navigator.pop();
          },
        ),
      ),
    );
  }
}

class _WaterCard extends ConsumerWidget {
  const _WaterCard({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goal = summary.target.waterMl;
    final progress = goal == 0 ? 0.0 : (summary.waterMl / goal).clamp(0.0, 1.0);
    final repository = ref.read(diaryRepositoryProvider);
    final day = ref.watch(selectedDayProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, color: MacroColors.water),
                const SizedBox(width: 8),
                Text('Wasser', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${summary.waterMl} / $goal ml',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: MacroColors.water,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final ml in const [200, 330, 500])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () =>
                          repository.addWater(day: day, amountMl: ml),
                      child: Text('+$ml'),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Letzte Eingabe rückgängig',
                  onPressed: summary.waterMl == 0
                      ? null
                      : () => repository.undoLastWater(day),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
