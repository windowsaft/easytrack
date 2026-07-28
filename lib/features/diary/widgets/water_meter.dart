import 'package:flutter/material.dart';

import '../../../core/i18n/number_format.dart';
import '../../../core/ui/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// The bar-based water meter.
///
/// Each bar is a fixed physical pour ([cupMl], 250 ml by default and set in
/// Settings), not a fraction of the goal — a glass is the same size whatever
/// today's target is. Bars are laid out eight to a row, and the grid grows
/// purely with what has been drunk: there is always exactly one empty row below
/// the last poured cup, so completing a row reveals a fresh one to keep pouring
/// into, and dropping back below a row's worth makes that empty row disappear.
/// Tapping an empty bar fills up to it; tapping the topmost filled bar clears it,
/// so a mistaken tap is undoable without any separate control.
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

    // One row per eight cups drunk, plus one always-empty row to pour the next
    // glass into. `filled ~/ cupsPerRow` is the number of *completed* rows, so
    // +1 is the row currently being filled (or a fresh empty one when the last
    // row just completed). Reducing the level shrinks this straight back.
    final rows = ((filled ~/ cupsPerRow) + 1).clamp(1, _maxRows);

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
                AppLocalizations.of(context).diaryWater.toUpperCase(),
                style: AppText.grotesk(
                  size: 12,
                  weight: 700,
                  letterSpacing: 1.68,
                ),
              ),
              // Expanded + scale-down so a wider reading ("1,75 / 2 L") shrinks
              // rather than clipping.
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

  /// 1250 -> "1,25", 2000 -> "2". Locale decimal separator, trailing zeros cut.
  static String _formatLitres(int ml) =>
      formatDecimal(ml / 1000, maxDecimals: 2);
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
