import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../core/nutrition/food_ref.dart';
import '../../../core/ui/app_theme.dart';
import '../../../data/db/user_database.dart';

const mealIcons = {
  MealType.breakfast: Icons.bakery_dining,
  MealType.lunch: Icons.lunch_dining,
  MealType.dinner: Icons.dinner_dining,
  MealType.snacks: Icons.cookie,
};

/// One meal on the diary: a summary row that opens the meal, with a swipe
/// action that jumps straight into adding food to it.
///
/// Every row — empty or not — carries the meal's own icon and the swipe-to-add
/// action, so the affordance is consistent regardless of whether anything has
/// been logged yet. An empty meal only differs in a dashed border and muted
/// text.
class MealRow extends StatelessWidget {
  const MealRow({
    required this.meal,
    required this.entries,
    required this.kcal,
    required this.onOpen,
    required this.onAdd,
    super.key,
  });

  final MealType meal;
  final List<DiaryEntry> entries;
  final double kcal;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final isEmpty = entries.isEmpty;

    return Slidable(
      key: ValueKey(meal.wireName),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.4,
        // Swipe far enough and the search opens on its own — no second tap on
        // the revealed button, the way a queue-swipe works. The pane snaps back
        // rather than dismissing (the row is permanent), so the action runs from
        // confirmDismiss, which then declines the actual dismissal.
        dismissible: DismissiblePane(
          dismissThreshold: 0.4,
          closeOnCancel: true,
          confirmDismiss: () async {
            onAdd();
            return false;
          },
          onDismissed: () {},
        ),
        children: [
          CustomSlidableAction(
            onPressed: (_) => onAdd(),
            backgroundColor: AppColors.lime,
            foregroundColor: AppColors.bg,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 26, color: AppColors.bg),
                const SizedBox(height: 2),
                Text(
                  'HINZUFÜGEN',
                  style: AppText.grotesk(
                    size: 9,
                    weight: 700,
                    color: AppColors.bg,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // The dashed empty state cannot use a Material fill, so its border is
      // painted underneath the transparent InkWell.
      child: CustomPaint(
        painter: isEmpty ? const _DashedRowBorder() : null,
        child: Material(
          color: isEmpty ? Colors.transparent : AppColors.surface,
          child: InkWell(
            // Empty rows open the add flow directly; filled rows open the meal.
            onTap: isEmpty ? onAdd : onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(mealIcons[meal], size: 24, color: AppColors.lime),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meal.displayLabel,
                          style: AppText.rowTitle(
                            color: isEmpty
                                ? AppColors.textMute2
                                : AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEmpty
                              ? 'Zum Hinzufügen wischen oder tippen'
                              : _foodSummary(entries),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowSubtitle(
                            color: isEmpty
                                ? AppColors.textFaint
                                : AppColors.textFaint2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    kcal.round().toString(),
                    style: AppText.rowValue(
                      color: isEmpty ? AppColors.textFaint : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Haferflocken · Banane · Kaffee" — the row is a glance, not a list, so it
  /// caps at three names and lets the ellipsis carry the rest.
  static String _foodSummary(List<DiaryEntry> entries) {
    final names = entries.take(3).map((e) => e.nameSnapshot);
    final suffix = entries.length > 3 ? ' · +${entries.length - 3}' : '';
    return '${names.join(' · ')}$suffix';
  }
}

/// The dashed border for an empty meal row. Flutter has no dashed [BorderSide],
/// and a solid one would read as a filled row.
class _DashedRowBorder extends CustomPainter {
  const _DashedRowBorder();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.strokeDashed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..addRect(Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRowBorder oldDelegate) => false;
}
