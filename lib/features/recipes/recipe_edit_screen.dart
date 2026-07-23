import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../data/food/food_item.dart';
import '../../domain/recipe.dart';
import '../diary/widgets/portion_sheet.dart';
import '../search/food_search_screen.dart';

/// Phase 10 — build or edit a recipe from weighed ingredients.
///
/// Each ingredient is a food picked from search plus the weight used; the rows
/// sum to a batch, and an optional cooked weight lets a dish that lost water on
/// the stove scale honestly. The finished recipe is saved as a food, so it logs
/// through the same portion picker as anything else.
class RecipeEditScreen extends ConsumerStatefulWidget {
  const RecipeEditScreen({this.recipeId, super.key});

  /// The recipe being edited, or null to create a new one.
  final String? recipeId;

  bool get isNew => recipeId == null;

  @override
  ConsumerState<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends ConsumerState<RecipeEditScreen> {
  final _name = TextEditingController();
  final _cookedWeight = TextEditingController();
  final _portionSize = TextEditingController();
  final _components = <RecipeComponent>[];
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _loaded = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _cookedWeight.dispose();
    _portionSize.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    final detail = await ref
        .read(recipeRepositoryProvider)
        .getRecipe(widget.recipeId!);
    if (!mounted) return;
    setState(() {
      if (detail != null) {
        _name.text = detail.recipe.name;
        final cooked = detail.recipe.cookedWeightG;
        if (cooked != null) _cookedWeight.text = _trim(cooked);
        final portion = detail.recipe.portionSizeG;
        if (portion != null) _portionSize.text = _trim(portion);
        _components
          ..clear()
          ..addAll(detail.components);
      }
      _loaded = true;
    });
  }

  double? get _cookedWeightG {
    final value = double.tryParse(_cookedWeight.text.replaceAll(',', '.'));
    return (value != null && value > 0) ? value : null;
  }

  double? get _portionSizeG {
    final value = double.tryParse(_portionSize.text.replaceAll(',', '.'));
    return (value != null && value > 0) ? value : null;
  }

  RecipeScaling get _scaling => RecipeScaling.of(
    _components,
    cookedWeightG: _cookedWeightG,
    portionSizeG: _portionSizeG,
  );

  bool get _canSave => _name.text.trim().isNotEmpty && _components.isNotEmpty;

  /// Live feedback under the portion field: how many portions the current yield
  /// makes at the entered size, and the kcal in one of them.
  String get _portionHint {
    final scaling = _scaling;
    final count = scaling.portionCount;
    if (count == null || scaling.isEmpty) {
      return 'Teile das Gericht in gleich große Portionen. Beim Eintragen '
          'kannst du dann "1 Portion" wählen.';
    }
    final kcal = scaling.forPortion(scaling.portionSizeG!).kcal.round();
    return 'Ergibt ≈ $count Portionen · $kcal kcal pro Portion.';
  }

  /// Picks a food, then its weight, and stages it as an ingredient.
  Future<void> _addIngredient() async {
    final food = await Navigator.of(context).push<FoodItem>(
      MaterialPageRoute(builder: (_) => const FoodSearchScreen.pick()),
    );
    if (food == null || !mounted) return;

    final portion = await showPortionSheet(context, food);
    if (portion == null) return;

    setState(() {
      _components.add(
        RecipeComponent(
          ref: food.ref,
          name: food.name,
          amountG: portion.grams,
          nutrients: food.nutrients.forGrams(portion.grams),
        ),
      );
    });
  }

  /// Reopens the weight picker for an ingredient already in the recipe.
  Future<void> _editWeight(int index) async {
    final component = _components[index];
    // Rebuild a per-100 g food from the ingredient's own snapshot, so the
    // picker rescales from what was stored rather than re-reading the source.
    final food = FoodItem(
      ref: component.ref,
      name: component.name,
      nutrients: component.per100g,
    );

    final portion = await showPortionSheet(
      context,
      food,
      initialGrams: component.amountG,
    );
    if (portion == null) return;

    setState(() => _components[index] = component.withAmount(portion.grams));
  }

  void _removeIngredient(int index) =>
      setState(() => _components.removeAt(index));

  Future<void> _save() async {
    if (!_canSave) return;
    final navigator = Navigator.of(context);
    final repository = ref.read(recipeRepositoryProvider);
    final name = _name.text.trim();

    if (widget.isNew) {
      await repository.createRecipe(
        name: name,
        components: _components,
        cookedWeightG: _cookedWeightG,
        portionSizeG: _portionSizeG,
      );
    } else {
      await repository.updateRecipe(
        id: widget.recipeId!,
        name: name,
        components: _components,
        cookedWeightG: _cookedWeightG,
        portionSizeG: _portionSizeG,
      );
    }
    navigator.pop();
  }

  Future<void> _confirmDelete() async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Rezept löschen?',
          style: AppText.grotesk(size: 17, weight: 700),
        ),
        content: Text(
          'Das Rezept wird entfernt. Bereits eingetragene Portionen bleiben '
          'erhalten.',
          style: AppText.grotesk(size: 14, color: AppColors.textMute),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Löschen',
              style: AppText.grotesk(
                size: 14,
                weight: 600,
                color: AppColors.coral,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(recipeRepositoryProvider).deleteRecipe(widget.recipeId!);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.lime)),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: widget.isNew ? 'NEUES REZEPT' : 'REZEPT',
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Zurück',
                onPressed: Navigator.of(context).pop,
              ),
              trailing: widget.isNew
                  ? null
                  : SquareIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Rezept löschen',
                      onPressed: _confirmDelete,
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.screenPadding,
                  8,
                  AppTheme.screenPadding,
                  24,
                ),
                children: [
                  _label('NAME'),
                  _TextField(
                    controller: _name,
                    hint: 'z. B. Chili con Carne',
                    autofocus: widget.isNew,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  _IngredientsSection(
                    components: _components,
                    onEdit: _editWeight,
                    onRemove: _removeIngredient,
                    onAdd: _addIngredient,
                  ),
                  const SizedBox(height: 20),
                  _label('GEKOCHTES GEWICHT (OPTIONAL)'),
                  _TextField(
                    controller: _cookedWeight,
                    hint: _components.isEmpty
                        ? '—'
                        : 'roh ${_scaling.batchWeightG.round()} g',
                    suffix: 'g',
                    number: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wiegt das fertige Gericht weniger als die Summe der Zutaten '
                    '(z. B. weil Wasser verkocht ist), hier eintragen. Portionen '
                    'werden dann darauf bezogen.',
                    style: AppText.grotesk(
                      size: 12,
                      color: AppColors.textMute,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _label('PORTIONSGRÖSSE (OPTIONAL)'),
                  _TextField(
                    controller: _portionSize,
                    hint: _components.isEmpty
                        ? '—'
                        : 'z. B. ${(_scaling.yieldWeightG / 2).round()} g',
                    suffix: 'g',
                    number: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _portionHint,
                    style: AppText.grotesk(
                      size: 12,
                      color: AppColors.textMute,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            _SummaryBar(scaling: _scaling, onSave: _canSave ? _save : null),
          ],
        ),
      ),
    );
  }

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppText.section(size: 14)),
  );

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}

class _IngredientsSection extends StatelessWidget {
  const _IngredientsSection({
    required this.components,
    required this.onEdit,
    required this.onRemove,
    required this.onAdd,
  });

  final List<RecipeComponent> components;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('ZUTATEN', style: AppText.section(size: 14))),
            Text(
              '${components.length}',
              style: AppText.grotesk(
                size: 12,
                weight: 700,
                color: AppColors.textMute,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (components.isEmpty)
          DashedBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Noch keine Zutaten',
                  style: AppText.rowSubtitle(color: AppColors.textFaint),
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < components.length; i++) ...[
            if (i > 0) const SizedBox(height: AppTheme.rowGap),
            _IngredientRow(
              component: components[i],
              onEdit: () => onEdit(i),
              onRemove: () => onRemove(i),
            ),
          ],
        const SizedBox(height: AppTheme.rowGap),
        DashedActionChip(
          label: 'Zutat hinzufügen',
          icon: Icons.add,
          onTap: onAdd,
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.component,
    required this.onEdit,
    required this.onRemove,
  });

  final RecipeComponent component;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
          child: Row(
            children: [
              const TileIcon(icon: Icons.restaurant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      component.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle(),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_trim(component.amountG)} g · '
                      '${component.nutrients.kcal.round()} kcal',
                      style: AppText.rowSubtitle(),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.chevron,
                ),
                tooltip: 'Entfernen',
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
}

/// The sticky footer: batch total, per-100 g preview, and save.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.scaling, required this.onSave});

  final RecipeScaling scaling;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final per100 = scaling.per100g.kcal.round();

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
                    scaling.batchNutrients.kcal.round().toString(),
                    style: AppText.anton(size: 26, height: 1),
                  ),
                  Text(
                    ' kcal gesamt',
                    style: AppText.grotesk(
                      size: 12,
                      weight: 600,
                      color: AppColors.textMute,
                    ),
                  ),
                ],
              ),
              Text(
                scaling.isEmpty
                    ? 'Zutaten hinzufügen'
                    : '${scaling.yieldWeightG.round()} g · $per100 kcal / 100 g',
                style: AppText.grotesk(
                  size: 11,
                  weight: 600,
                  color: AppColors.textMute,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: PrimaryButton(
              label: 'SPEICHERN',
              icon: Icons.check_circle,
              height: 52,
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.suffix,
    this.number = false,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final bool number;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      style: AppText.grotesk(size: 16, weight: 600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.grotesk(
          size: 15,
          weight: 500,
          color: AppColors.textFaint,
        ),
        suffixText: suffix,
        suffixStyle: AppText.grotesk(
          size: 13,
          weight: 600,
          color: AppColors.textMute,
        ),
        isDense: true,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.strokeDashed),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lime, width: 2),
        ),
      ),
    );
  }
}
