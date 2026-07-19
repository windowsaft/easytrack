import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/db/user_database.dart';
import '../../domain/day_summary.dart';
import '../activity/activity_types.dart';
import '../search/food_search_screen.dart';
import 'meal_detail_screen.dart';
import 'widgets/meal_row.dart';
import 'widgets/water_meter.dart';

/// Screen 2b — the day's dashboard: budget, macros, water, meals, activity.
class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final summary = ref.watch(daySummaryProvider(day));

    return switch (summary) {
      AsyncData(:final value) => _DayView(summary: value),
      AsyncError(:final error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Fehler beim Laden:\n$error',
            textAlign: TextAlign.center,
            style: AppText.grotesk(size: 14, color: AppColors.textMute),
          ),
        ),
      ),
      _ => const Center(
        child: CircularProgressIndicator(color: AppColors.lime),
      ),
    };
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consumed = summary.consumed;

    // Top-only: the diary lives inside the nav shell, so the bar owns the
    // bottom inset. Without this the date header rides under the status bar.
    return ListView(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        _DateHeader(day: summary.day),
        const SizedBox(height: 8),
        _GaugeRow(summary: summary),
        const SizedBox(height: 12),
        _MacroBlocks(summary: summary, consumed: consumed),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: WaterMeter(
            currentMl: summary.waterMl,
            goalMl: summary.target.waterMl,
            cupMl: ref.watch(waterCupMlProvider),
            onSet: (ml) => ref
                .read(diaryRepositoryProvider)
                .setWater(day: summary.day, amountMl: ml),
          ),
        ),
        SectionHeader(
          title: 'MAHLZEITEN',
          size: 18,
          color: AppColors.text,
          padding: const EdgeInsets.fromLTRB(
            AppTheme.screenPadding,
            14,
            AppTheme.screenPadding,
            6,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swipe_left,
                size: 14,
                color: AppColors.textFaint,
              ),
              const SizedBox(width: 3),
              Text(
                'WISCHEN',
                style: AppText.grotesk(
                  size: 10,
                  weight: 600,
                  color: AppColors.textFaint,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          child: Column(
            children: [
              for (final meal in MealType.values) ...[
                if (meal != MealType.values.first)
                  const SizedBox(height: AppTheme.rowGap),
                MealRow(
                  meal: meal,
                  entries: summary.entriesFor(meal),
                  kcal: summary.nutrientsFor(meal).kcal,
                  onOpen: () => _openMeal(context, ref, meal),
                  onAdd: () => _addToMeal(context, ref, meal),
                ),
              ],
            ],
          ),
        ),
        // Activity is added through the centre nav button's chooser, so the
        // section is just a heading over the day's entries.
        const SectionHeader(
          title: 'AKTIVITÄT',
          size: 18,
          color: AppColors.text,
        ),
        _ActivityList(day: summary.day),
      ],
    );
  }

  Future<void> _openMeal(BuildContext context, WidgetRef ref, MealType meal) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => MealDetailScreen(meal: meal)),
      );

  /// The swipe/empty-tap add action jumps straight to search, so backing out
  /// returns to the diary rather than dropping onto the meal-detail screen the
  /// user never asked to see.
  Future<void> _addToMeal(BuildContext context, WidgetRef ref, MealType meal) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => FoodSearchScreen(meal: meal)),
      );
}

/// Date navigation. The overline carries the exact date so the Anton title can
/// stay relative ("HEUTE") without the user losing track of which day they are
/// looking at.
class _DateHeader extends ConsumerWidget {
  const _DateHeader({required this.day});

  final DayKey day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedDayProvider.notifier);
    final date = day.toDateTime();

    return BoldHeader(
      titleSize: 30,
      overline: DateFormat('E · d. MMM', 'de').format(date).toUpperCase(),
      title: _relativeName(day, date),
      leading: SquareIconButton(
        icon: Icons.chevron_left,
        tooltip: 'Vorheriger Tag',
        onPressed: () => notifier.select(day.previous),
      ),
      trailing: SquareIconButton(
        icon: Icons.chevron_right,
        tooltip: 'Nächster Tag',
        onPressed: () => notifier.select(day.next),
      ),
    );
  }

  static String _relativeName(DayKey day, DateTime date) {
    final today = DayKey.today();
    return switch (today.daysUntil(day)) {
      0 => 'HEUTE',
      -1 => 'GESTERN',
      1 => 'MORGEN',
      _ => DateFormat('EEEE', 'de').format(date).toUpperCase(),
    };
  }
}

class _GaugeRow extends StatelessWidget {
  const _GaugeRow({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _EdgeStat(
            icon: Icons.restaurant,
            iconColor: AppColors.lime,
            value: summary.consumed.kcal.round().toString(),
            label: 'GEGESSEN',
          ),
          Flexible(
            child: CalorieGauge(
              consumedKcal: summary.consumed.kcal,
              budgetKcal: summary.budgetKcal,
            ),
          ),
          // Shows the credited figure, not the raw entry: this is the number
          // that actually moved the budget, and 5a already explained the
          // safety factor at the moment of entry.
          _EdgeStat(
            icon: Icons.local_fire_department,
            iconColor: AppColors.coral,
            value: summary.activityKcalAdjusted.round().toString(),
            label: 'VERBRANNT',
          ),
        ],
      ),
    );
  }
}

class _EdgeStat extends StatelessWidget {
  const _EdgeStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppText.anton(size: 28, height: 1)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppText.grotesk(
              size: 9,
              weight: 700,
              color: AppColors.textMute,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroBlocks extends StatelessWidget {
  const _MacroBlocks({required this.summary, required this.consumed});

  final DaySummary summary;
  final Nutrients consumed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              label: 'KOHLENH.',
              value: consumed.carbsG.round().toString(),
              suffix: _targetSuffix(summary.target.carbsG),
              accent: AppColors.carbs,
            ),
          ),
          const SizedBox(width: AppTheme.rowGap),
          Expanded(
            child: StatTile(
              label: 'EIWEISS',
              value: consumed.proteinG.round().toString(),
              suffix: _targetSuffix(summary.target.proteinG),
              accent: AppColors.protein,
            ),
          ),
          const SizedBox(width: AppTheme.rowGap),
          Expanded(
            child: StatTile(
              label: 'FETT',
              value: consumed.fatG.round().toString(),
              suffix: _targetSuffix(summary.target.fatG),
              accent: AppColors.fat,
            ),
          ),
        ],
      ),
    );
  }

  /// Without a macro target there is no honest denominator, so the block shows
  /// grams alone rather than inventing one.
  static String _targetSuffix(double? target) =>
      target == null ? ' g' : '/${target.round()}';
}

/// The day's logged activity. Read separately from the summary because the
/// summary only carries totals, and these rows need each entry.
class _ActivityList extends ConsumerWidget {
  const _ActivityList({required this.day});

  final DayKey day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityEntriesProvider(day)).value ?? const [];

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
        child: DashedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                const Icon(
                  Icons.directions_run,
                  size: 24,
                  color: AppColors.textFaint,
                ),
                const SizedBox(width: 13),
                Text(
                  'Keine Aktivität erfasst',
                  style: AppText.rowSubtitle(color: AppColors.textFaint),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Column(
        children: [
          for (final entry in entries) ...[
            if (entry != entries.first) const SizedBox(height: AppTheme.rowGap),
            _ActivityRow(entry: entry),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credited = entry.kcalBurnedRaw * entry.safetyFactor;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        color: AppColors.coral,
        child: const Icon(Icons.delete, color: AppColors.bg),
      ),
      onDismissed: (_) =>
          ref.read(diaryRepositoryProvider).deleteActivity(entry.id),
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(
              activityIconFor(entry.label),
              size: 24,
              color: AppColors.coral,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.label, style: AppText.rowTitle()),
                  const SizedBox(height: 2),
                  Text(_subtitle(entry), style: AppText.rowSubtitle()),
                ],
              ),
            ),
            Text(
              '−${credited.round()}',
              style: AppText.rowValue(color: AppColors.coral),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the raw entry next to the factor when they differ, so the credited
  /// figure in the trailing column is never unexplained.
  static String _subtitle(ActivityEntry entry) {
    final parts = <String>[
      if (entry.durationMin != null) '${entry.durationMin} min',
      if (entry.safetyFactor != 1.0)
        '${entry.kcalBurnedRaw.round()} kcal × '
            '${entry.safetyFactor.toStringAsFixed(2).replaceAll('.', ',')}',
    ];
    return parts.isEmpty ? 'Manuell erfasst' : parts.join(' · ');
  }
}
