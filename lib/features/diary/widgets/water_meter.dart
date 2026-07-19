import 'package:flutter/material.dart';

import '../../../core/ui/app_theme.dart';

/// The bar-based water meter.
///
/// Each bar is a fixed physical pour ([cupMl], 250 ml by default and set in
/// Settings), not a fraction of the goal — a glass is the same size whatever
/// today's target is. The bar count is derived from the cup size and the goal:
/// enough bars to represent the goal, laid out eight to a row. Drink past the
/// goal and a fresh row appears, so overshooting is visible rather than clamped.
/// Tapping a bar sets the level to it; tapping the topmost filled bar clears it,
/// which makes a mistaken tap undoable without a separate affordance.
class WaterMeter extends StatelessWidget {
  const WaterMeter({
    required this.currentMl,
    required this.goalMl,
    required this.cupMl,
    required this.onSet,
    this.cupsPerRow = 8,
    super.key,
  });

  final int currentMl;
  final int goalMl;
  final int cupMl;
  final ValueChanged<int> onSet;
  final int cupsPerRow;

  /// A hard ceiling on rows so a runaway value cannot render an endless grid.
  static const _maxRows = 6;

  @override
  Widget build(BuildContext context) {
    final cup = cupMl <= 0 ? 250 : cupMl;
    // Round down: a bar lights only once it is actually full.
    final filled = currentMl ~/ cup;
    // Cups that represent the goal, rounded up so the goal is always reachable.
    final goalCups = goalMl <= 0 ? cupsPerRow : (goalMl / cup).ceil();

    // Show whichever is more rows: enough to display the goal, or enough to
    // hold what has actually been drunk. Growing strictly with `filled` — with
    // no padding cup — means a second row appears only once a glass is poured
    // *into* it, and vanishes again the moment the level drops back within the
    // first. Completing a row exactly does not, on its own, spawn an empty one.
    int rowsFor(int cups) => (cups + cupsPerRow - 1) ~/ cupsPerRow;
    final goalRows = rowsFor(goalCups);
    final filledRows = rowsFor(filled);
    final rows = (goalRows > filledRows ? goalRows : filledRows).clamp(
      1,
      _maxRows,
    );

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop, size: 18, color: AppColors.water),
              const SizedBox(width: 7),
              Text(
                'WASSER',
                style: AppText.grotesk(
                  size: 12,
                  weight: 700,
                  letterSpacing: 1.68,
                ),
              ),
              // Expanded + scale-down so a wider reading ("1,75 / 2 L") shrinks
              // rather than shoving the add button off the edge.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _formatLitres(currentMl),
                        style: AppText.anton(size: 20),
                      ),
                      Text(
                        ' / ${_formatLitres(goalMl)} L',
                        style: AppText.grotesk(
                          size: 12,
                          weight: 600,
                          color: AppColors.textUnit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Adds one glass regardless of the grid. The bars grow strictly
              // with what has been drunk, so once a row is exactly full there
              // is no empty bar to tap — this button is how the goal gets
              // exceeded without a permanently-parked empty row.
              _AddCupButton(onTap: () => onSet(currentMl + cup)),
            ],
          ),
          const SizedBox(height: 10),
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: 5),
            Row(
              children: [
                for (var col = 0; col < cupsPerRow; col++) ...[
                  if (col > 0) const SizedBox(width: 5),
                  Expanded(
                    child: _Bar(
                      key: ValueKey('water_bar_${row * cupsPerRow + col}'),
                      index: row * cupsPerRow + col,
                      filled: filled,
                      cupMl: cup,
                      onSet: onSet,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 1250 -> "1,25", 2000 -> "2". German decimal comma.
  static String _formatLitres(int ml) {
    final litres = ml / 1000;
    final text = litres == litres.roundToDouble()
        ? litres.round().toString()
        : litres.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return text.replaceAll('.', ',');
  }
}

/// The compact "add one glass" control in the meter header.
class _AddCupButton extends StatelessWidget {
  const _AddCupButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Glas hinzufügen',
      child: Material(
        color: AppColors.surfaceAlt2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          side: const BorderSide(color: AppColors.water, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('water_add_cup'),
          onTap: onTap,
          child: const SizedBox(
            width: 30,
            height: 26,
            child: Icon(Icons.add, size: 18, color: AppColors.water),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.index,
    required this.filled,
    required this.cupMl,
    required this.onSet,
    super.key,
  });

  final int index;
  final int filled;
  final int cupMl;
  final ValueChanged<int> onSet;

  @override
  Widget build(BuildContext context) {
    final isFilled = index < filled;

    return Semantics(
      button: true,
      label: '${(index + 1) * cupMl} ml',
      child: GestureDetector(
        // Tapping the topmost filled bar empties down to just below it, so a
        // stray tap is one tap to undo.
        onTap: () =>
            onSet(filled == index + 1 ? index * cupMl : (index + 1) * cupMl),
        child: Container(
          height: 30,
          decoration: BoxDecoration(
            color: isFilled ? AppColors.water : AppColors.surfaceAlt2,
            border: isFilled
                ? null
                : Border.all(color: AppColors.strokeDashed, width: 1.5),
          ),
        ),
      ),
    );
  }
}
