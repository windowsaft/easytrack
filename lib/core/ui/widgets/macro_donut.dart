import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Energy share of the three macros, as a ring with the meal's kcal in the hole.
///
/// The slices are shares of *calories*, not of grams: 58 g of carbs and 6 g of
/// fat are nearly the same amount of energy, so a gram-based split would tell
/// the user something untrue about where their calories came from.
class MacroDonut extends StatelessWidget {
  const MacroDonut({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.kcal,
    this.size = 98,
    super.key,
  });

  final double proteinG;
  final double carbsG;
  final double fatG;
  final double kcal;
  final double size;

  /// Atwater factors: 4 kcal/g for protein and carbohydrate, 9 for fat.
  static MacroShares sharesOf({
    required double proteinG,
    required double carbsG,
    required double fatG,
  }) {
    final carbsKcal = carbsG * 4;
    final proteinKcal = proteinG * 4;
    final fatKcal = fatG * 9;
    final total = carbsKcal + proteinKcal + fatKcal;

    if (total <= 0) return const MacroShares(carbs: 0, protein: 0, fat: 0);
    return MacroShares(
      carbs: carbsKcal / total,
      protein: proteinKcal / total,
      fat: fatKcal / total,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shares = sharesOf(proteinG: proteinG, carbsG: carbsG, fatG: fatG);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(shares: shares),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kcal.round().toString(),
                style: AppText.anton(size: size * 0.225, height: 1),
              ),
              Text(
                'KCAL',
                style: AppText.grotesk(
                  size: 8,
                  weight: 700,
                  color: AppColors.textMute,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fractions of total energy, summing to 1 (or all zero for an empty meal).
class MacroShares {
  const MacroShares({
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  final double carbs;
  final double protein;
  final double fat;

  bool get isEmpty => carbs == 0 && protein == 0 && fat == 0;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.shares});

  final MacroShares shares;

  @override
  void paint(Canvas canvas, Size size) {
    // Ring geometry from the handoff: 98px outer, 60px hole.
    final outer = size.width / 2;
    final inner = size.width * 60 / 98 / 2;
    final width = outer - inner;
    final rect = Rect.fromCircle(
      center: Offset(outer, outer),
      radius: (outer + inner) / 2,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;

    if (shares.isEmpty) {
      canvas.drawCircle(
        Offset(outer, outer),
        (outer + inner) / 2,
        paint..color = AppColors.surfaceAlt,
      );
      return;
    }

    // Starts at 12 o'clock and runs clockwise, matching the CSS conic-gradient.
    var start = -math.pi / 2;
    for (final (share, color) in [
      (shares.carbs, AppColors.carbs),
      (shares.protein, AppColors.protein),
      (shares.fat, AppColors.fat),
    ]) {
      if (share <= 0) continue;
      final sweep = share * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, false, paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.shares.carbs != shares.carbs ||
      oldDelegate.shares.protein != shares.protein ||
      oldDelegate.shares.fat != shares.fat;
}

/// One "■ Kohlenhydrate 58g 69%" line beside the donut.
class MacroLegendRow extends StatelessWidget {
  const MacroLegendRow({
    required this.label,
    required this.color,
    required this.grams,
    required this.share,
    super.key,
  });

  final String label;
  final Color color;
  final double grams;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.grotesk(
              size: 13,
              weight: 600,
              color: AppColors.textBright,
            ),
          ),
        ),
        Text('${grams.round()} g', style: AppText.anton(size: 16)),
        SizedBox(
          width: 38,
          child: Text(
            '${(share * 100).round()} %',
            textAlign: TextAlign.right,
            style: AppText.grotesk(
              size: 12,
              weight: 700,
              color: AppColors.textMute,
            ),
          ),
        ),
      ],
    );
  }
}
