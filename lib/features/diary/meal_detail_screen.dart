import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/enum_labels.dart';
import '../../core/i18n/number_format.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/measure_unit.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/macro_donut.dart';
import '../../data/db/user_database.dart';
import '../../data/food/food_item.dart';
import '../../l10n/app_localizations.dart';
import '../scan/barcode_flow.dart';
import '../search/food_search_screen.dart';
import 'widgets/meal_row.dart';
import 'widgets/portion_sheet.dart';

/// Screen 4a — one meal: what is in it, how to add more, and its macro split.
class MealDetailScreen extends ConsumerStatefulWidget {
  const MealDetailScreen({
    required this.meal,
    this.openSearch = false,
    super.key,
  });

  final MealType meal;

  /// Opens the search screen immediately. Set when the user swiped "Hinzufügen"
  /// on the diary, where the intent was to add food, not to inspect the meal.
  final bool openSearch;

  @override
  ConsumerState<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends ConsumerState<MealDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.openSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSearch());
    }
  }

  Future<void> _openSearch() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => FoodSearchScreen(meal: widget.meal)),
    );
  }

  /// Reopens a logged entry to change how much of it was eaten. The portion
  /// sheet works on a [FoodItem], so the entry's stored snapshot is turned back
  /// into a per-100 g food; editing then rescales from that same snapshot rather
  /// than re-reading the source, keeping an old log stable.
  Future<void> _edit(DiaryEntry entry) async {
    final repository = ref.read(diaryRepositoryProvider);
    final portion = await showPortionSheet(
      context,
      _foodFromEntry(entry),
      initialGrams: entry.amountG,
    );
    if (portion == null) return;

    await repository.editEntry(
      entryId: entry.id,
      amountG: portion.grams,
      servingLabel: portion.label,
      servingCount: portion.count,
    );
  }

  /// Rebuilds a per-100 g [FoodItem] from an entry's stored snapshot, so its
  /// weight can be re-picked at any amount.
  static FoodItem _foodFromEntry(DiaryEntry entry) {
    final per100g = entry.amountG <= 0
        ? Nutrients.zero
        : Nutrients(
            kcal: entry.kcal,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            fatG: entry.fatG,
            sugarG: entry.sugarG,
            fiberG: entry.fiberG,
            satFatG: entry.satFatG,
            saltG: entry.saltG,
          ).scaled(100 / entry.amountG);

    return FoodItem(
      ref: FoodRef(FoodSourceType.fromWire(entry.sourceType), entry.sourceId),
      name: entry.nameSnapshot,
      brand: entry.brandSnapshot,
      nutrients: per100g,
      measure: MeasureUnit.fromWire(entry.unit),
    );
  }

  /// Copies the most recent earlier day's version of this meal onto the day
  /// being shown.
  Future<void> _repeat() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final day = ref.read(selectedDayProvider);
    final count = await ref
        .read(diaryRepositoryProvider)
        .repeatMeal(to: day, meal: widget.meal);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? l10n.mealDetailNoEarlier(widget.meal.label(l10n))
              : l10n.mealDetailEntriesCopied(count),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(selectedDayProvider);
    final summary = ref.watch(daySummaryProvider(day)).value;
    final entries = summary?.entriesFor(widget.meal) ?? const <DiaryEntry>[];
    final nutrients = summary?.nutrientsFor(widget.meal) ?? Nutrients.zero;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // No back button: the FERTIG action in the bottom bar is the one
            // way out, and the system back gesture still works.
            BoldHeader(
              overline: _dayLabel(day.toDateTime()),
              title: widget.meal.label(l10n).toUpperCase(),
            ),
            _EntryActions(
              onSearch: _openSearch,
              onScan: () => scanBarcodeIntoMeal(context, ref, widget.meal),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.screenPadding,
                0,
                AppTheme.screenPadding,
                4,
              ),
              child: DashedActionChip(
                label: l10n.mealDetailRepeat,
                icon: Icons.replay,
                onTap: _repeat,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  SectionHeader(
                    title: l10n.mealDetailInThisMeal.toUpperCase(),
                    trailing: Text(
                      l10n.mealDetailEntryCount(entries.length).toUpperCase(),
                      style: AppText.grotesk(
                        size: 11,
                        weight: 600,
                        color: AppColors.textMute,
                        letterSpacing: 0.66,
                      ),
                    ),
                  ),
                  if (entries.isEmpty)
                    const _EmptyMeal()
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.screenPadding,
                      ),
                      child: Column(
                        children: [
                          for (final entry in entries) ...[
                            if (entry != entries.first)
                              const SizedBox(height: AppTheme.rowGap),
                            _EntryRow(
                              entry: entry,
                              meal: widget.meal,
                              onEdit: () => _edit(entry),
                              onRemove: () => ref
                                  .read(diaryRepositoryProvider)
                                  .deleteEntry(entry.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                  SectionHeader(title: l10n.mealDetailNutrients.toUpperCase()),
                  _MacroSplit(nutrients: nutrients),
                ],
              ),
            ),
            _MealTotalBar(kcal: nutrients.kcal),
          ],
        ),
      ),
    );
  }

  static String _dayLabel(DateTime date) =>
      '${DateFormat.EEEE().format(date)} · ${DateFormat.MMMMd().format(date)}'
          .toUpperCase();
}

/// The two ways into the meal: search (primary) and barcode scan.
class _EntryActions extends StatelessWidget {
  const _EntryActions({required this.onSearch, required this.onScan});

  final VoidCallback onSearch;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        14,
        AppTheme.screenPadding,
        6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: AppColors.lime,
              borderRadius: BorderRadius.circular(AppRadii.button),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 24, color: AppColors.bg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.mealDetailSearchFood,
                          style: AppText.grotesk(
                            size: 15,
                            weight: 700,
                            color: AppColors.bg,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.bg,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            height: 56,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
                side: const BorderSide(
                  color: AppColors.strokeDashed,
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onScan,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner,
                      size: 24,
                      color: AppColors.lime,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.commonScan.toUpperCase(),
                      style: AppText.grotesk(
                        size: 8,
                        weight: 700,
                        color: AppColors.lime,
                        letterSpacing: 0.48,
                      ),
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
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.meal,
    required this.onEdit,
    required this.onRemove,
  });

  final DiaryEntry entry;
  final MealType meal;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Tapping the row reopens the portion sheet to change the weight; the close
    // button keeps its own tap target for removal.
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TileIcon(
                icon: entry.unit == 'ml'
                    ? Icons.local_drink
                    : (mealIcons[meal] ?? Icons.restaurant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.nameSnapshot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle(),
                    ),
                    const SizedBox(height: 2),
                    Text(_portionLabel(entry), style: AppText.rowSubtitle()),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.kcal.round().toString(),
                style: AppText.rowValue(size: 19),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.chevron,
                ),
                tooltip: AppLocalizations.of(context).commonRemove,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows what the user picked, with the gram weight it resolved to — the
  /// serving alone hides how much food that actually was.
  static String _portionLabel(DiaryEntry entry) {
    final amount = '${_trim(entry.amountG)} ${entry.unit}';
    if (entry.servingLabel == null || entry.servingCount == null) return amount;
    return '${_trim(entry.servingCount!)} × ${entry.servingLabel} · $amount';
  }

  static String _trim(double value) => formatDecimal(value, maxDecimals: 1);
}

class _EmptyMeal extends StatelessWidget {
  const _EmptyMeal();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      child: DashedBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Center(
            child: Text(
              AppLocalizations.of(context).mealDetailEmpty,
              style: AppText.rowSubtitle(color: AppColors.textFaint),
            ),
          ),
        ),
      ),
    );
  }
}

class _MacroSplit extends StatelessWidget {
  const _MacroSplit({required this.nutrients});

  final Nutrients nutrients;

  @override
  Widget build(BuildContext context) {
    final shares = MacroDonut.sharesOf(
      proteinG: nutrients.proteinG,
      carbsG: nutrients.carbsG,
      fatG: nutrients.fatG,
    );

    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          MacroDonut(
            proteinG: nutrients.proteinG,
            carbsG: nutrients.carbsG,
            fatG: nutrients.fatG,
            kcal: nutrients.kcal,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                MacroLegendRow(
                  label: l10n.nutrientCarbs,
                  color: AppColors.carbs,
                  grams: nutrients.carbsG,
                  share: shares.carbs,
                ),
                const SizedBox(height: 11),
                MacroLegendRow(
                  label: l10n.nutrientProtein,
                  color: AppColors.protein,
                  grams: nutrients.proteinG,
                  share: shares.protein,
                ),
                const SizedBox(height: 11),
                MacroLegendRow(
                  label: l10n.nutrientFat,
                  color: AppColors.fat,
                  grams: nutrients.fatG,
                  share: shares.fat,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealTotalBar extends StatelessWidget {
  const _MealTotalBar({required this.kcal});

  final double kcal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bar,
        border: Border(top: BorderSide(color: AppColors.stroke, width: 1.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        14,
        AppTheme.screenPadding,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    kcal.round().toString(),
                    style: AppText.anton(size: 26, height: 1),
                  ),
                  Text(
                    ' kcal',
                    style: AppText.grotesk(
                      size: 12,
                      weight: 600,
                      color: AppColors.textMute,
                    ),
                  ),
                ],
              ),
              Text(
                l10n.mealDetailTotal.toUpperCase(),
                style: AppText.grotesk(
                  size: 11,
                  weight: 600,
                  color: AppColors.textMute,
                  letterSpacing: 0.66,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: OutlineActionButton(
              label: l10n.commonDone.toUpperCase(),
              icon: Icons.done,
              onPressed: Navigator.of(context).pop,
            ),
          ),
        ],
      ),
    );
  }
}
