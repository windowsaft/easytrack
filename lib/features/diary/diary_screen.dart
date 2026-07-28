import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/number_format.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/time/day_key.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/day_picker.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../data/db/user_database.dart';
import '../../domain/day_summary.dart';
import '../../l10n/app_localizations.dart';
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
            AppLocalizations.of(context).diaryLoadError(error.toString()),
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
    final l10n = AppLocalizations.of(context);

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
          title: l10n.diaryMeals.toUpperCase(),
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
                l10n.diarySwipe.toUpperCase(),
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
        SectionHeader(
          title: l10n.commonActivity.toUpperCase(),
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
    final l10n = AppLocalizations.of(context);

    return BoldHeader(
      titleSize: 30,
      overline: DateFormat('E · d. MMM').format(date).toUpperCase(),
      title: _relativeName(l10n, day, date),
      onTitleTap: () => _pickDay(context, notifier, day),
      leading: SquareIconButton(
        icon: Icons.chevron_left,
        tooltip: l10n.diaryPreviousDay,
        onPressed: () => notifier.select(day.previous),
      ),
      trailing: SquareIconButton(
        icon: Icons.chevron_right,
        tooltip: l10n.diaryNextDay,
        onPressed: () => notifier.select(day.next),
      ),
    );
  }

  /// Tapping the date opens a calendar to jump to any day directly (with a
  /// Heute shortcut), rather than stepping there one chevron at a time. The
  /// chevrons can already have walked into the future, so that day is passed as
  /// the latest selectable one to keep it reachable.
  Future<void> _pickDay(
    BuildContext context,
    SelectedDay notifier,
    DayKey day,
  ) async {
    final picked = await showDayPicker(context, initial: day, last: day);
    if (picked != null) notifier.select(picked);
  }

  static String _relativeName(
    AppLocalizations l10n,
    DayKey day,
    DateTime date,
  ) {
    final today = DayKey.today();
    return switch (today.daysUntil(day)) {
      0 => l10n.commonToday.toUpperCase(),
      -1 => l10n.commonYesterday.toUpperCase(),
      1 => l10n.commonTomorrow.toUpperCase(),
      _ => DateFormat('EEEE').format(date).toUpperCase(),
    };
  }
}

class _GaugeRow extends StatelessWidget {
  const _GaugeRow({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _EdgeStat(
            icon: Icons.restaurant,
            iconColor: AppColors.lime,
            value: summary.consumed.kcal.round().toString(),
            label: l10n.diaryEaten.toUpperCase(),
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
            label: l10n.diaryBurned.toUpperCase(),
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: Column(
        children: [
          // The tiles open the full breakdown (sugar, fibre, sat. fat, salt),
          // which has no room on the dashboard but is a tap away.
          InkWell(
            onTap: () => _showNutrientDetails(context, summary),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: l10n.macroCarbsShort.toUpperCase(),
                    value: consumed.carbsG.round().toString(),
                    suffix: _targetSuffix(summary.target.carbsG),
                    accent: AppColors.carbs,
                  ),
                ),
                const SizedBox(width: AppTheme.rowGap),
                Expanded(
                  child: StatTile(
                    label: l10n.macroProteinShort.toUpperCase(),
                    value: consumed.proteinG.round().toString(),
                    suffix: _targetSuffix(summary.target.proteinG),
                    accent: AppColors.protein,
                  ),
                ),
                const SizedBox(width: AppTheme.rowGap),
                Expanded(
                  child: StatTile(
                    label: l10n.macroFatShort.toUpperCase(),
                    value: consumed.fatG.round().toString(),
                    suffix: _targetSuffix(summary.target.fatG),
                    accent: AppColors.fat,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _showNutrientDetails(context, summary),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.diaryAllNutrients.toUpperCase(),
                      style: AppText.grotesk(
                        size: 10,
                        weight: 700,
                        color: AppColors.textFaint,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 15,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
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

/// The full nutrient breakdown for the day — the macros already on the
/// dashboard plus the sub-nutrients (sugar, fibre, saturated fat, salt) that do
/// not fit there. Unknown values read "—" rather than 0: a food that never
/// declared its salt has not been measured as salt-free.
Future<void> _showNutrientDetails(BuildContext context, DaySummary summary) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NutrientDetailsSheet(summary: summary),
  );
}

class _NutrientDetailsSheet extends StatelessWidget {
  const _NutrientDetailsSheet({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final c = summary.consumed;
    final t = summary.target;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          4,
          AppTheme.screenPadding,
          20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.diaryNutrientsToday.toUpperCase(),
              style: AppText.section(size: 18),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat(
                'EEEE, d. MMMM',
              ).format(summary.day.toDateTime()),
              style: AppText.grotesk(
                size: 12,
                weight: 500,
                color: AppColors.textMute,
              ),
            ),
            const SizedBox(height: 16),
            _NutrientRow(
              label: l10n.nutrientEnergy,
              value: '${c.kcal.round()}',
              unit: 'kcal',
              target: t.kcal.round().toString(),
              accent: AppColors.lime,
            ),
            const Divider(height: 18, color: AppColors.stroke),
            _NutrientRow(
              label: l10n.nutrientCarbs,
              value: _g(c.carbsG),
              unit: 'g',
              target: t.carbsG?.round().toString(),
              accent: AppColors.carbs,
            ),
            _NutrientRow(label: l10n.nutrientSugar, value: _gN(c.sugarG), sub: true),
            const SizedBox(height: 6),
            // Ballaststoffe are their own nutrient, not a "davon" of carbohydrate,
            // so they read as a top-level row with a dot rather than an indented
            // sub-line.
            _NutrientRow(
              label: l10n.nutrientFiber,
              value: _gN(c.fiberG),
              unit: 'g',
              accent: AppColors.fiber,
            ),
            const SizedBox(height: 6),
            _NutrientRow(
              label: l10n.nutrientProtein,
              value: _g(c.proteinG),
              unit: 'g',
              target: t.proteinG?.round().toString(),
              accent: AppColors.protein,
            ),
            const SizedBox(height: 6),
            _NutrientRow(
              label: l10n.nutrientFat,
              value: _g(c.fatG),
              unit: 'g',
              target: t.fatG?.round().toString(),
              accent: AppColors.fat,
            ),
            _NutrientRow(
              label: l10n.nutrientSaturated,
              value: _gN(c.satFatG),
              sub: true,
            ),
            const SizedBox(height: 6),
            _NutrientRow(
              label: l10n.nutrientSalt,
              value: _gN(c.saltG),
              unit: 'g',
              accent: AppColors.water,
            ),
          ],
        ),
      ),
    );
  }

  /// A known gram value: whole numbers from 10 up, otherwise up to one decimal
  /// with the locale separator for sub-gram amounts.
  static String _g(double v) =>
      v >= 10 ? formatInt(v) : formatDecimal(v, maxDecimals: 1);

  /// A nullable gram value: "—" when the food never declared it.
  static String _gN(double? v) => v == null ? '—' : _g(v);
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.label,
    required this.value,
    this.unit,
    this.target,
    this.accent,
    this.sub = false,
  });

  final String label;
  final String value;
  final String? unit;
  final String? target;
  final Color? accent;

  /// A "davon …" sub-nutrient: indented and muted under its parent.
  final bool sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: sub ? 14 : 0, top: sub ? 4 : 2, bottom: 2),
      // Centre the row so the dot lines up with the label. Only the value
      // cluster (number + unit + target) is baseline-aligned, internally — a
      // baseline row here would drop the dot, which has no text baseline.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (accent != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ] else if (!sub)
            const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: AppText.grotesk(
                size: sub ? 12 : 14,
                weight: sub ? 500 : 600,
                color: sub ? AppColors.textMute : AppColors.text,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: sub
                    ? AppText.grotesk(
                        size: 12,
                        weight: 600,
                        color: AppColors.textMute,
                      )
                    : AppText.anton(size: 18),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: AppText.grotesk(
                    size: 11,
                    weight: 600,
                    color: AppColors.textUnit,
                  ),
                ),
              ],
              if (target != null)
                Text(
                  ' / $target',
                  style: AppText.grotesk(
                    size: 12,
                    weight: 600,
                    color: AppColors.textUnit,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
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
                  AppLocalizations.of(context).diaryNoActivity,
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
    final l10n = AppLocalizations.of(context);

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
              activityIconFor(l10n, entry.label),
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
                  Text(_subtitle(l10n, entry), style: AppText.rowSubtitle()),
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
  static String _subtitle(AppLocalizations l10n, ActivityEntry entry) {
    final parts = <String>[
      if (entry.durationMin != null) l10n.diaryMinutesShort(entry.durationMin!),
      if (entry.safetyFactor != 1.0)
        l10n.diaryActivityBurnFactor(
          entry.kcalBurnedRaw.round(),
          formatFixed(entry.safetyFactor, 2),
        ),
    ];
    return parts.isEmpty ? l10n.diaryActivityManual : parts.join(' · ');
  }
}
