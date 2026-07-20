import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/repositories/recipe_repository.dart';
import '../diary/widgets/portion_sheet.dart';
import 'recipe_edit_screen.dart';

/// Screen 5 — the recipe book: dishes the user built from weighed ingredients,
/// each loggable as a portion straight into a meal.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider).value ?? const <RecipeDetail>[];

    return ListView(
      // Top-only inset: the shell owns the bottom nav bar.
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24,
      ),
      children: [
        // No header add button: on this tab the centre nav button (the FAB)
        // creates a recipe. The empty state still offers an explicit action.
        const BoldHeader(title: 'REZEPTE'),
        const SizedBox(height: 8),
        if (recipes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.screenPadding,
            ),
            child: Column(
              children: [
                const _EmptyState(),
                const SizedBox(height: 14),
                DashedActionChip(
                  label: 'Erstes Rezept anlegen',
                  icon: Icons.add,
                  onTap: () => _openEdit(context),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.screenPadding,
            ),
            child: Column(
              children: [
                for (final detail in recipes) ...[
                  if (detail != recipes.first)
                    const SizedBox(height: AppTheme.rowGap),
                  _RecipeRow(
                    detail: detail,
                    onOpen: () => _openEdit(context, detail.recipe.id),
                    onLog: () => _logRecipe(context, ref, detail),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static Future<void> _openEdit(BuildContext context, [String? id]) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => RecipeEditScreen(recipeId: id)),
      );

  /// Choose a meal, pick a portion weight, log it into the selected day.
  Future<void> _logRecipe(
    BuildContext context,
    WidgetRef ref,
    RecipeDetail detail,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (detail.scaling.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Dieses Rezept hat noch keine Zutaten.')),
      );
      return;
    }

    final meal = await _pickMeal(context);
    if (meal == null || !context.mounted) return;

    final food = detail.toFoodItem();
    final portion = await showPortionSheet(context, food, allowFavorite: true);
    if (portion == null) return;

    await ref
        .read(diaryRepositoryProvider)
        .addEntry(
          day: ref.read(selectedDayProvider),
          meal: meal,
          food: food,
          amountG: portion.grams,
          servingLabel: portion.label,
          servingCount: portion.count,
        );
    messenger.showSnackBar(
      SnackBar(content: Text('${detail.recipe.name} eingetragen')),
    );
  }

  Future<MealType?> _pickMeal(BuildContext context) {
    return showModalBottomSheet<MealType>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.screenPadding,
            20,
            AppTheme.screenPadding,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IN WELCHE MAHLZEIT?', style: AppText.section(size: 18)),
              const SizedBox(height: 14),
              for (final meal in MealType.values) ...[
                Material(
                  color: AppColors.surface,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(meal),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.restaurant,
                            size: 22,
                            color: AppColors.lime,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              meal.displayLabel,
                              style: AppText.grotesk(size: 15, weight: 600),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: AppColors.chevron,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.rowGap),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.detail,
    required this.onOpen,
    required this.onLog,
  });

  final RecipeDetail detail;
  final VoidCallback onOpen;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final count = detail.ingredients.length;
    final per100 = detail.scaling.per100g.kcal.round();

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              const TileIcon(icon: Icons.menu_book),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.recipe.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle(),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count ${count == 1 ? 'Zutat' : 'Zutaten'} · '
                      '$per100 kcal / 100 g',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowSubtitle(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _LogButton(onTap: onLog),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lime "log a portion" control on a recipe row.
class _LogButton extends StatelessWidget {
  const _LogButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Portion eintragen',
      child: Material(
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.add, size: 24, color: AppColors.bg),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.menu_book, size: 44, color: AppColors.chevron),
            const SizedBox(height: 12),
            Text(
              'Noch keine Rezepte',
              style: AppText.grotesk(size: 15, weight: 700),
            ),
            const SizedBox(height: 4),
            Text(
              'Baue ein Gericht aus gewogenen Zutaten. Die Portionsrechnung '
              'skaliert Kalorien und Nährwerte auf den Teller, den du wirklich '
              'isst.',
              textAlign: TextAlign.center,
              style: AppText.grotesk(
                size: 13,
                color: AppColors.textMute,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
