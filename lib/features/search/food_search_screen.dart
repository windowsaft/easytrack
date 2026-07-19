import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/nutrition/food_ref.dart';
import '../../data/food/food_item.dart';
import '../../data/food/search_orchestrator.dart';

/// Food search. Results stream in from local sources first.
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key, this.meal, this.onPicked});

  /// Meal being logged into, when opened from the diary.
  final MealType? meal;

  /// Called with the picked food. When null the screen is browse-only.
  final void Function(FoodItem item)? onPicked;

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(foodSearchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.meal == null
              ? 'Suche'
              : '${widget.meal!.displayLabel} hinzufügen',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Lebensmittel suchen …',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
      ),
      body: switch (search) {
        AsyncData(:final value) => _Results(
          state: value,
          query: _query,
          onPicked: widget.onPicked,
        ),
        AsyncError(:final error) => _Message(
          icon: Icons.error_outline,
          text: 'Suche fehlgeschlagen:\n$error',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state, required this.query, this.onPicked});

  final SearchState state;
  final String query;
  final void Function(FoodItem item)? onPicked;

  @override
  Widget build(BuildContext context) {
    final results = state.results;

    if (query.trim().isEmpty) {
      return const _Message(
        icon: Icons.search,
        text:
            'Tippe, um über 7.000 Lebensmittel zu durchsuchen.\n'
            'Funktioniert auch offline.',
      );
    }

    if (results.isEmpty) {
      return _Message(
        icon: Icons.no_food,
        text: 'Nichts gefunden für "$query".',
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = results[index];
        return _FoodTile(
          item: result.item,
          onTap: onPicked == null ? null : () => onPicked!(result.item),
        );
      },
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.item, this.onTap});

  final FoodItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = item.nutrients;

    return ListTile(
      title: Text(item.displayTitle, maxLines: 2),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${n.kcal.round()} kcal · '
          'E ${n.proteinG.toStringAsFixed(1)} g · '
          'KH ${n.carbsG.toStringAsFixed(1)} g · '
          'F ${n.fatG.toStringAsFixed(1)} g'
          '  (pro 100 g)',
          style: theme.textTheme.bodySmall,
        ),
      ),
      trailing: onTap == null ? null : const Icon(Icons.add_circle_outline),
      onTap: onTap,
      isThreeLine: false,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
