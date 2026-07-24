import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../app_theme.dart';

/// The 270° calorie arc at the top of the diary.
///
/// The sweep shows how much of the day's budget is eaten; the centre shows what
/// is left. Those are two different framings of the same number on purpose —
/// the arc answers "how far through the day am I", the numeral answers "what
/// can I still eat".
class CalorieGauge extends StatelessWidget {
  const CalorieGauge({
    required this.consumedKcal,
    required this.budgetKcal,
    this.size = 210,
    super.key,
  });

  final double consumedKcal;
  final double budgetKcal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = budgetKcal - consumedKcal;
    final over = remaining < 0;
    final progress = budgetKcal <= 0
        ? 0.0
        : (consumedKcal / budgetKcal).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          progress: progress,
          fill: over ? AppColors.coral : AppColors.lime,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The remaining figure is the largest thing on the screen, so it
              // must never wrap or clip — five digits still fit at 62px only
              // because of this.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size * 0.16),
                  child: Text(
                    remaining.abs().round().toString(),
                    style: AppText.anton(
                      size: size * 0.24,
                      color: AppColors.textHi,
                      height: 0.9,
                    ),
                  ),
                ),
              ),
              Text(
                (over ? l10n.gaugeOver : l10n.gaugeLeft).toUpperCase(),
                style: AppText.grotesk(
                  size: 12,
                  weight: 700,
                  color: over ? AppColors.coral : AppColors.lime,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.gaugeOfGoal(formatKcal(budgetKcal)).toUpperCase(),
                style: AppText.grotesk(
                  size: 11,
                  weight: 600,
                  color: AppColors.textMute,
                  letterSpacing: 0.66,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// German thousands separator: 2100 -> "2.100".
String formatKcal(double value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.progress, required this.fill});

  final double progress;
  final Color fill;

  // 270° starting at the lower left, leaving the gap at the bottom.
  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    // The handoff's SVG is a 280-unit viewBox drawn at 210px, so the radius and
    // stroke are expressed as fractions of the rendered size rather than as the
    // raw 110/26 from the source.
    final radius = size.width * 110 / 280;
    final stroke = size.width * 26 / 280;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      // Butt caps, not round: the flat ends are what makes this the "bold"
      // variant rather than the softer 2a direction.
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      base..color = AppColors.surfaceAlt,
    );

    if (progress > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * progress,
        false,
        base..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.fill != fill;
}
