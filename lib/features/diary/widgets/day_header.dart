import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../../core/time/day_key.dart';
import '../../../core/ui/app_theme.dart';
import '../../../domain/day_summary.dart';

/// Date navigation plus the day's headline numbers.
class DayHeader extends ConsumerWidget {
  const DayHeader({required this.summary, super.key});

  final DaySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final consumed = summary.consumed;
    final remaining = summary.remainingKcal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => ref
                      .read(selectedDayProvider.notifier)
                      .select(summary.day.previous),
                ),
                Expanded(
                  child: Text(
                    _formatDay(summary.day),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => ref
                      .read(selectedDayProvider.notifier)
                      .select(summary.day.next),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Stat(
                  label: 'Gegessen',
                  value: consumed.kcal.round().toString(),
                  unit: 'kcal',
                ),
                _Stat(
                  label: 'Budget',
                  value: summary.budgetKcal.round().toString(),
                  unit: 'kcal',
                ),
                _Stat(
                  label: summary.isOverBudget ? 'Darüber' : 'Übrig',
                  value: remaining.abs().round().toString(),
                  unit: 'kcal',
                  color: summary.isOverBudget
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ],
            ),
            if (summary.activityKcalAdjusted > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    size: 16,
                    color: MacroColors.activity,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+${summary.activityKcalAdjusted.round()} kcal durch Aktivität',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _MacroBar(
                  label: 'Eiweiß',
                  grams: consumed.proteinG,
                  target: summary.target.proteinG,
                  color: MacroColors.protein,
                ),
                _MacroBar(
                  label: 'Kohlenh.',
                  grams: consumed.carbsG,
                  target: summary.target.carbsG,
                  color: MacroColors.carbs,
                ),
                _MacroBar(
                  label: 'Fett',
                  grams: consumed.fatG,
                  target: summary.target.fatG,
                  color: MacroColors.fat,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDay(DayKey day) {
    if (day.isToday) return 'Heute';
    if (day.value == DayKey.today().previous.value) return 'Gestern';
    if (day.value == DayKey.today().next.value) return 'Morgen';
    return DateFormat('EEEE, d. MMMM', 'de').format(day.toDateTime());
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(unit, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.grams,
    required this.color,
    this.target,
  });

  final String label;
  final double grams;
  final double? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Without a macro target there is no meaningful fraction to show, so the
    // bar stays empty rather than inventing a denominator.
    final progress = target == null || target == 0
        ? 0.0
        : (grams / target!).clamp(0.0, 1.0);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              target == null
                  ? '${grams.round()} g'
                  : '${grams.round()} / ${target!.round()} g',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
