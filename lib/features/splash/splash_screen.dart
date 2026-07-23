import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/app_theme.dart';
import '../onboarding/onboarding_gate.dart';

/// The launch screen: the ring brand mark draws itself in like a calorie ring
/// filling, the wordmark fades up under it, then it hands off to the onboarding
/// gate (which shows first-run setup or drops straight into the diary).
///
/// Purely cosmetic — the app's data opens lazily through its providers, so this
/// is a fixed-length flourish rather than a loading gate. It matches the app
/// icon (deep-green field, lime ring) so the cold start reads as one product.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // The mark pops in, the ring sweeps closed, and the wordmark arrives last —
  // each on its own slice of the timeline.
  late final Animation<double> _pop;
  late final Animation<double> _sweep;
  late final Animation<double> _word;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    Animation<double> slice(double begin, double end, Curve curve) =>
        CurvedAnimation(
          parent: _controller,
          curve: Interval(begin, end, curve: curve),
        );

    _pop = slice(0.0, 0.4, Curves.easeOutBack);
    _sweep = slice(0.15, 0.9, Curves.easeOutCubic);
    _word = slice(0.6, 1.0, Curves.easeOut);

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) unawaited(_goHome());
    });
  }

  Future<void> _goHome() async {
    // A short hold on the finished mark before the cross-fade, so it does not
    // snap away the instant the ring closes.
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, _, _) => const OnboardingGate(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Deep-green launch field, matching the app icon, before the cross-fade
      // into the near-black diary.
      backgroundColor: AppColors.brandGreen,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pop = _pop.value.clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.7 + 0.3 * pop,
                  child: Opacity(
                    opacity: pop,
                    child: CustomPaint(
                      size: const Size(120, 120),
                      painter: _RingMarkPainter(
                        sweep: _sweep.value.clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Opacity(
                  opacity: _word.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - _word.value.clamp(0.0, 1.0))),
                    child: Text(
                      'EASYTRACK',
                      style: AppText.anton(
                        size: 30,
                        letterSpacing: 0.08,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Draws the app-icon mark at any sweep progress: a faint lime track ring with
/// a bright lime arc closing over it from the top, clockwise — the calorie ring
/// filling.
class _RingMarkPainter extends CustomPainter {
  _RingMarkPainter({required this.sweep});

  /// 0 → 1: how much of the ring has drawn in.
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.width * 0.14;
    final radius = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.lime.withValues(alpha: 0.16);
    canvas.drawCircle(center, radius, track);

    if (sweep <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.lime;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * sweep, false, arc);
  }

  @override
  bool shouldRepaint(_RingMarkPainter old) => old.sweep != sweep;
}
