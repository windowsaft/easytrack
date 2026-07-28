import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/enum_labels.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/nutrition/nutrients.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/db/user_database.dart';
import '../../data/food/food_item.dart';
import '../../data/food/search_orchestrator.dart';
import '../../l10n/app_localizations.dart';
import '../diary/widgets/portion_sheet.dart';
import '../scan/barcode_flow.dart';
import 'food_forms.dart';

/// Screen 4b — search foods and add them to a meal.
///
/// Two ways to add, matching how portioning actually works: the `+` control
/// quick-adds a food at its default portion into a selection tray, while
/// tapping the row opens the portion picker for anything that is not a default
/// amount. The row always shows the portion the `+` would log, so the fast path
/// is never a guess.
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key, this.meal}) : pick = false;

  /// Ingredient-picker mode: tapping a food pops the screen with that
  /// [FoodItem] instead of logging it, so the recipe builder can reuse the whole
  /// search surface without duplicating it. The multi-select tray, quick-add and
  /// favourite stars are all hidden — none apply when the caller just wants one
  /// food back.
  const FoodSearchScreen.pick({super.key}) : meal = null, pick = true;

  /// Meal being logged into. Without one the screen is browse-only (or, in
  /// [pick] mode, returns the tapped food).
  final MealType? meal;

  final bool pick;

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

enum _Tab { all, recent, favorites, mine }

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  _Tab _tab = _Tab.all;

  /// Foods staged for adding, keyed by [FoodRef] so tapping `+` twice on the
  /// same food toggles rather than double-logging.
  final _selected = <FoodRef, FoodItem>{};

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  double get _selectedKcal => _selected.values.fold(
    0,
    (sum, food) => sum + food.nutrients.forGrams(food.defaultGrams).kcal,
  );

  /// Whether the meal being logged into has no entries yet. Reads the loaded
  /// day summary (warm from the diary), so a filled meal never offers repeat.
  bool get _mealIsEmpty {
    final meal = widget.meal;
    if (meal == null) return false;
    final day = ref.watch(selectedDayProvider);
    final summary = ref.watch(daySummaryProvider(day)).value;
    return summary != null && summary.entriesFor(meal).isEmpty;
  }

  void _toggle(FoodItem food) {
    setState(() {
      if (_selected.remove(food.ref) == null) _selected[food.ref] = food;
    });
  }

  /// Commits the tray: every staged food at its default portion.
  Future<void> _commit() async {
    final meal = widget.meal;
    if (meal == null || _selected.isEmpty) return;

    final navigator = Navigator.of(context);
    final repository = ref.read(diaryRepositoryProvider);
    final day = ref.read(selectedDayProvider);

    for (final food in _selected.values) {
      final serving = food.defaultServing;
      await repository.addEntry(
        day: day,
        meal: meal,
        food: food,
        amountG: serving.defaultGrams,
        // A bare gram amount is the fallback, not a choice the user made, so it
        // is not recorded as a named serving.
        servingLabel: serving.isRaw ? null : serving.label,
        servingCount: serving.isRaw ? null : 1,
      );
    }

    navigator.pop();
  }

  /// Opens the portion picker and logs the result immediately, bypassing the
  /// tray — the user has already made a per-food decision at that point.
  Future<void> _pickPortion(FoodItem food) async {
    final meal = widget.meal;
    if (meal == null) return;

    final day = ref.read(selectedDayProvider);
    final repository = ref.read(diaryRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    final portion = await showPortionSheet(context, food, allowFavorite: true);
    if (portion == null) return;

    await repository.addEntry(
      day: day,
      meal: meal,
      food: food,
      amountG: portion.grams,
      servingLabel: portion.label,
      servingCount: portion.count,
    );

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.searchAddedFood(food.name))),
    );
  }

  Future<void> _relog(DiaryEntry entry) async {
    final meal = widget.meal;
    if (meal == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await ref
        .read(diaryRepositoryProvider)
        .relogEntry(
          source: entry,
          day: ref.read(selectedDayProvider),
          meal: meal,
        );

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.searchAddedFood(entry.nameSnapshot))),
    );
  }

  /// Pick mode: hand the tapped food back to the caller (the recipe builder).
  void _returnFood(FoodItem food) => Navigator.of(context).pop(food);

  /// Pick mode for the "Zuletzt" tab, whose rows are diary entries. Recovers a
  /// per-100 g [FoodItem] from the entry's stored snapshot so an ingredient can
  /// be re-added at any weight, not just the one it was last logged at.
  void _returnEntry(DiaryEntry entry) {
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

    Navigator.of(context).pop(
      FoodItem(
        ref: FoodRef(FoodSourceType.fromWire(entry.sourceType), entry.sourceId),
        name: entry.nameSnapshot,
        brand: entry.brandSnapshot,
        nutrients: per100g,
      ),
    );
  }

  Future<void> _scan() async {
    // Pick mode (recipe ingredient): hand the scanned food straight back.
    if (widget.pick) {
      final barcode = await scanBarcode(context);
      if (barcode == null || !mounted) return;
      final food = await resolveScannedBarcode(context, ref, barcode);
      if (food != null && mounted) _returnFood(food);
      return;
    }

    final meal = widget.meal;
    if (meal != null) {
      await scanBarcodeIntoMeal(context, ref, meal);
      return;
    }

    // Browse-only: no meal to log into, so just report what was scanned.
    final barcode = await scanBarcode(context);
    if (barcode == null || !mounted) return;
    final food = await resolveScannedBarcode(context, ref, barcode);
    if (food != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).searchFound(food.name)),
        ),
      );
    }
  }

  /// Copies the most recent earlier day's version of this meal onto the day
  /// being logged into. Surfaced here because adding from the diary jumps
  /// straight to search, past the meal screen where repeat otherwise lives — so
  /// "repeat my usual breakfast" would be unreachable for an empty meal.
  Future<void> _repeat() async {
    final meal = widget.meal;
    if (meal == null) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final count = await ref
        .read(diaryRepositoryProvider)
        .repeatMeal(to: ref.read(selectedDayProvider), meal: meal);
    if (!mounted) return;

    if (count == 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.mealDetailNoEarlier(meal.label(l10n)))),
      );
      return;
    }

    // The meal is filled now, so leave search and show the result underneath.
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mealDetailEntriesCopied(count))),
    );
  }

  /// Quick calorie entry: logged straight into the meal, not saved as a food.
  Future<void> _quickAdd() async {
    final meal = widget.meal;
    final food = await showQuickAddSheet(context);
    if (food == null || meal == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await ref
        .read(diaryRepositoryProvider)
        .addEntry(
          day: ref.read(selectedDayProvider),
          meal: meal,
          food: food,
          amountG: food.defaultServing.defaultGrams,
          servingLabel: food.defaultServing.isRaw
              ? null
              : food.defaultServing.label,
          servingCount: food.defaultServing.isRaw ? null : 1,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.searchAddedFood(food.name))),
    );
  }

  /// Creates a reusable custom food, then offers to log it.
  Future<void> _createFood() async {
    final draft = await showCreateFoodSheet(context);
    if (draft == null || !mounted) return;

    final food = await ref
        .read(customFoodRepositoryProvider)
        .create(
          name: draft.name,
          brand: draft.brand,
          nutrients: draft.nutrients,
          servingG: draft.servingG,
          servingLabel: draft.servingUnit,
          measure: draft.measure,
        );

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).searchCreatedFood(food.name)),
      ),
    );
    // Land on the tab where the new food now lives.
    setState(() => _tab = _Tab.mine);
    if (widget.meal != null) await _pickPortion(food);
  }

  @override
  Widget build(BuildContext context) {
    final logging = widget.meal != null;
    final picking = widget.pick;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SearchHeader(
              controller: _controller,
              focusNode: _focus,
              onChanged: (value) => setState(() => _query = value),
              onClear: () {
                _controller.clear();
                setState(() => _query = '');
              },
              onScan: _scan,
            ),
            _Tabs(current: _tab, onSelect: (t) => setState(() => _tab = t)),
            if (logging)
              _QuickActions(
                onQuickAdd: _quickAdd,
                onCreate: _createFood,
                // Repeat is a starting point for an empty meal only.
                onRepeat: _mealIsEmpty ? _repeat : null,
              ),
            Expanded(child: _body(logging, picking)),
            if (_selected.isNotEmpty && logging)
              _SelectionTray(
                count: _selected.length,
                kcal: _selectedKcal,
                meal: widget.meal!,
                onCommit: _commit,
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(bool logging, bool picking) {
    final l10n = AppLocalizations.of(context);
    // In pick mode every food row simply returns; otherwise a tap opens the
    // portion picker, and only when a meal is being logged into.
    final onFood = picking ? _returnFood : (logging ? _pickPortion : null);

    switch (_tab) {
      case _Tab.all:
        return _SearchResults(
          query: _query,
          selected: _selected.keys.toSet(),
          onToggle: _toggle,
          onOpen: onFood,
          picking: picking,
        );
      case _Tab.recent:
        return _RecentList(
          onPick: picking ? _returnEntry : (logging ? _relog : null),
        );
      case _Tab.favorites:
        final foods = ref.watch(favoritesProvider).value ?? const [];
        return _FoodItemList(
          foods: foods,
          emptyIcon: Icons.star_border,
          emptyText: l10n.searchFavoritesEmpty,
          onPick: onFood,
          // Nothing to favourite while picking an ingredient.
          pinnable: !picking,
        );
      case _Tab.mine:
        final foods = ref.watch(myFoodsProvider).value ?? const [];
        return _FoodItemList(
          foods: foods,
          emptyIcon: Icons.restaurant_menu,
          emptyText: l10n.searchMineEmpty,
          onPick: onFood,
          pinnable: !picking,
        );
    }
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onScan,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Row(
        children: [
          SquareIconButton(
            icon: Icons.arrow_back,
            tooltip: l10n.searchBack,
            onPressed: Navigator.of(context).pop,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ListenableBuilder(
              listenable: focusNode,
              builder: (context, _) => Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.iconButton),
                  border: Border.all(
                    // The lime border is the design's focus state.
                    color: focusNode.hasFocus
                        ? AppColors.lime
                        : AppColors.strokeButton,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 21,
                      color: focusNode.hasFocus
                          ? AppColors.lime
                          : AppColors.textMute,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: onChanged,
                        style: AppText.grotesk(size: 15, weight: 600),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: l10n.searchHint,
                          hintStyle: AppText.grotesk(
                            size: 15,
                            weight: 500,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: controller,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : GestureDetector(
                              onTap: onClear,
                              child: const Icon(
                                Icons.close,
                                size: 20,
                                color: AppColors.textMute,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SquareIconButton(
            icon: Icons.qr_code_scanner,
            iconSize: 23,
            tooltip: l10n.searchScanBarcode,
            onPressed: onScan,
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onSelect});

  final _Tab current;
  final ValueChanged<_Tab> onSelect;

  static String _label(AppLocalizations l10n, _Tab tab) => switch (tab) {
    _Tab.all => l10n.searchTabAll,
    _Tab.recent => l10n.searchTabRecent,
    _Tab.favorites => l10n.searchTabFavorites,
    _Tab.mine => l10n.searchTabMine,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        children: [
          for (final tab in _Tab.values) ...[
            if (tab != _Tab.values.first) const SizedBox(width: 8),
            BoldChip(
              label: _label(l10n, tab),
              selected: current == tab,
              onTap: () => onSelect(tab),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onQuickAdd,
    required this.onCreate,
    this.onRepeat,
  });

  final VoidCallback onQuickAdd;
  final VoidCallback onCreate;

  /// Fills an empty meal from its last earlier day. Null once the meal has food,
  /// where rebuilding it wholesale no longer makes sense.
  final VoidCallback? onRepeat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
      child: Row(
        children: [
          Expanded(
            child: DashedActionChip(
              label: l10n.searchQuickEntry,
              icon: Icons.bolt,
              onTap: onQuickAdd,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DashedActionChip(
              label: l10n.searchCreate,
              icon: Icons.restaurant_menu,
              onTap: onCreate,
            ),
          ),
          if (onRepeat != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: DashedActionChip(
                label: l10n.searchRepeat,
                icon: Icons.replay,
                onTap: onRepeat!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
    this.picking = false,
  });

  final String query;
  final Set<FoodRef> selected;
  final ValueChanged<FoodItem> onToggle;
  final ValueChanged<FoodItem>? onOpen;
  final bool picking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (query.trim().isEmpty) {
      return _Message(
        icon: Icons.search,
        text: l10n.searchEmptyHint,
      );
    }

    final search = ref.watch(foodSearchProvider(query));

    return switch (search) {
      AsyncData(:final value) => _ResultList(
        state: value,
        query: query,
        selected: selected,
        onToggle: onToggle,
        onOpen: onOpen,
        picking: picking,
      ),
      AsyncError(:final error) => _Message(
        icon: Icons.error_outline,
        text: l10n.searchFailed(error.toString()),
      ),
      _ => const Center(
        child: CircularProgressIndicator(color: AppColors.lime),
      ),
    };
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.state,
    required this.query,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
    this.picking = false,
  });

  final SearchState state;
  final String query;
  final Set<FoodRef> selected;
  final ValueChanged<FoodItem> onToggle;
  final ValueChanged<FoodItem>? onOpen;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = state.results;

    if (results.isEmpty) {
      return _Message(
        icon: Icons.no_food,
        text: l10n.searchNoResults(query),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.rowGap),
      itemBuilder: (context, index) {
        if (index == 0) {
          return SectionHeader(
            title: l10n.searchHits.toUpperCase(),
            padding: const EdgeInsets.only(bottom: 6),
            trailing: Text(
              l10n.searchHitsCount(results.length).toUpperCase(),
              style: AppText.grotesk(
                size: 11,
                weight: 600,
                color: AppColors.textFaint,
                letterSpacing: 0.66,
              ),
            ),
          );
        }

        final item = results[index - 1].item;
        return _ResultRow(
          item: item,
          selected: selected.contains(item.ref),
          onToggle: () => onToggle(item),
          onOpen: onOpen == null ? null : () => onOpen!(item),
          picking: picking,
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
    this.picking = false,
  });

  final FoodItem item;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    final serving = item.defaultServing;
    final kcal = item.nutrients.forGrams(serving.defaultGrams).kcal;
    final l10n = AppLocalizations.of(context);

    return Material(
      color: selected ? AppColors.selectedRow : AppColors.surface,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: selected
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.lime, width: 3),
                  ),
                )
              : null,
          padding: EdgeInsets.fromLTRB(selected ? 9 : 12, 11, 12, 11),
          child: Row(
            children: [
              TileIcon(
                icon: item.isLiquid ? Icons.local_drink : Icons.restaurant,
                color: selected ? AppColors.lime : AppColors.textMute,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle(),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${serving.portionLabel} · ${item.ref.source.label(l10n)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowSubtitle(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _KcalColumn(kcal: kcal),
              const SizedBox(width: 10),
              // While picking an ingredient the row itself selects, so the
              // multi-select toggle would be a second, confusing target.
              if (picking)
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AppColors.chevron,
                )
              else
                _AddToggle(selected: selected, onTap: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class _KcalColumn extends StatelessWidget {
  const _KcalColumn({required this.kcal});

  final double kcal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          kcal.round().toString(),
          style: AppText.anton(size: 18, height: 1),
        ),
        Text(
          'KCAL',
          style: AppText.grotesk(
            size: 9,
            weight: 600,
            color: AppColors.textFaint,
            letterSpacing: 0.72,
          ),
        ),
      ],
    );
  }
}

class _AddToggle extends StatelessWidget {
  const _AddToggle({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: selected ? l10n.commonSelected : l10n.commonAdd,
      child: Material(
        color: selected ? AppColors.lime : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          side: selected
              ? BorderSide.none
              : const BorderSide(color: AppColors.strokeDashed, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              selected ? Icons.check : Icons.add,
              size: 22,
              color: selected ? AppColors.bg : AppColors.lime,
            ),
          ),
        ),
      ),
    );
  }
}

/// Previously logged foods, re-logged with one tap at the portion they were
/// last eaten in.
class _RecentList extends ConsumerWidget {
  const _RecentList({required this.onPick});

  final ValueChanged<DiaryEntry>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentFoodsProvider).value ?? const [];

    if (recent.isEmpty) {
      return _Message(
        icon: Icons.history,
        text: AppLocalizations.of(context).searchRecentEmpty,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      itemCount: recent.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.rowGap),
      itemBuilder: (context, index) {
        final entry = recent[index];
        return Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: onPick == null ? null : () => onPick!(entry),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                children: [
                  const TileIcon(icon: Icons.history),
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
                        Text(
                          '${entry.amountG.round()} g',
                          style: AppText.rowSubtitle(),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    entry.kcal.round().toString(),
                    style: AppText.anton(size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.add, size: 22, color: AppColors.lime),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Favoriten and Meine tabs: a flat list of the user's own foods.
class _FoodItemList extends StatelessWidget {
  const _FoodItemList({
    required this.foods,
    required this.emptyIcon,
    required this.emptyText,
    required this.onPick,
    this.pinnable = false,
  });

  final List<FoodItem> foods;
  final IconData emptyIcon;
  final String emptyText;
  final ValueChanged<FoodItem>? onPick;

  /// Whether rows carry a star that toggles the favourite state.
  final bool pinnable;

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return _Message(icon: emptyIcon, text: emptyText);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      itemCount: foods.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.rowGap),
      itemBuilder: (context, index) {
        final food = foods[index];
        final serving = food.defaultServing;
        final kcal = food.nutrients.forGrams(serving.defaultGrams).kcal;

        return Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: onPick == null ? null : () => onPick!(food),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                children: [
                  TileIcon(
                    icon: food.isLiquid
                        ? Icons.local_drink
                        : Icons.restaurant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          food.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle(),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          serving.portionLabel,
                          style: AppText.rowSubtitle(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _KcalColumn(kcal: kcal),
                  if (pinnable)
                    _PinStar(food: food)
                  else
                    const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Toggles a food's favourite state, whatever its source. A custom food uses
/// its own `isFavorite` flag; anything else is pinned. The icon reflects the
/// unified [favoriteRefsProvider], so taps show immediately.
class _PinStar extends ConsumerWidget {
  const _PinStar({required this.food});

  final FoodItem food;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavourite = ref.watch(favoriteRefsProvider).contains(food.ref);

    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(
        isFavourite ? Icons.star : Icons.star_border,
        size: 22,
        color: isFavourite ? AppColors.lime : AppColors.chevron,
      ),
      tooltip: isFavourite
          ? AppLocalizations.of(context).searchRemoveFavorite
          : AppLocalizations.of(context).searchAddFavorite,
      onPressed: () => _toggle(ref, isFavourite),
    );
  }

  void _toggle(WidgetRef ref, bool isFavourite) {
    if (food.ref.source == FoodSourceType.custom) {
      ref
          .read(customFoodRepositoryProvider)
          .setFavorite(food.ref.id, value: !isFavourite);
    } else {
      ref.read(pinnedFoodsRepositoryProvider).toggle(food);
    }
  }
}

class _SelectionTray extends StatelessWidget {
  const _SelectionTray({
    required this.count,
    required this.kcal,
    required this.meal,
    required this.onCommit,
  });

  final int count;
  final double kcal;
  final MealType meal;
  final VoidCallback onCommit;

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
                l10n.searchSelectedCount(count).toUpperCase(),
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
            child: PrimaryButton(
              label: l10n.searchAddToMeal(meal.label(l10n)).toUpperCase(),
              icon: Icons.check_circle,
              height: 52,
              onPressed: onCommit,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.chevron),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppText.grotesk(size: 14, color: AppColors.textMute),
            ),
          ],
        ),
      ),
    );
  }
}
