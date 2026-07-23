// Generates the EasyTrack launcher-icon PNGs from code, so the mark stays in
// sync with the splash (lib/features/splash/splash_screen.dart): a lime ring on
// a deep-green field — the calorie ring that is the heart of the app, and the
// same ring mark used on the landing page.
//
// Run from the repo root:  dart run tool/gen_icon.dart
// Then:                    dart run flutter_launcher_icons
//
// Outputs:
//   assets/icon/icon.png            1024² full-bleed green + lime ring (iOS + legacy)
//   assets/icon/icon_foreground.png 1024² transparent, ring in the safe zone
//
// package:image and flutter_launcher_icons are dev-only dependencies.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Brand palette — must match AppColors in lib/core/ui/app_theme.dart.
final _lime = img.ColorRgb8(0xC6, 0xFF, 0x3A);
final _green = img.ColorRgb8(0x0E, 0x3B, 0x23);

/// Draws an antialiased lime ring centred on ([cx], [cy]) with the given outer
/// radius and stroke width.
///
/// When [transparent] the ring is laid onto transparency with straight alpha
/// (for the adaptive foreground); otherwise each pixel is composited over the
/// colour already there (the full-bleed green field of the master icon).
void _drawRing(
  img.Image image, {
  required double cx,
  required double cy,
  required double outerR,
  required double stroke,
  bool transparent = false,
}) {
  final innerR = outerR - stroke;
  final x0 = (cx - outerR - 1).floor().clamp(0, image.width - 1);
  final x1 = (cx + outerR + 1).ceil().clamp(0, image.width - 1);
  final y0 = (cy - outerR - 1).floor().clamp(0, image.height - 1);
  final y1 = (cy + outerR + 1).ceil().clamp(0, image.height - 1);
  const aa = 1.0; // edge feather, in pixels

  double cov(double d) {
    final outer = ((outerR - d) / aa + 0.5).clamp(0.0, 1.0);
    final inner = ((d - innerR) / aa + 0.5).clamp(0.0, 1.0);
    return outer * inner;
  }

  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final dx = x + 0.5 - cx;
      final dy = y + 0.5 - cy;
      final c = cov(math.sqrt(dx * dx + dy * dy));
      if (c <= 0) continue;
      if (transparent) {
        // Straight-alpha lime over transparency.
        image.setPixelRgba(x, y, _lime.r, _lime.g, _lime.b, (c * 255).round());
      } else {
        final base = image.getPixel(x, y);
        int mix(num lime, num bg) => (lime * c + bg * (1 - c)).round();
        image.setPixelRgba(
          x,
          y,
          mix(_lime.r, base.r),
          mix(_lime.g, base.g),
          mix(_lime.b, base.b),
          255,
        );
      }
    }
  }
}

void main() {
  Directory('assets/icon').createSync(recursive: true);

  // Master icon: full-bleed deep green with a bold lime ring. The OS masks the
  // outer corners to a circle/squircle on both platforms.
  final master = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(master, color: _green);
  _drawRing(master, cx: 512, cy: 512, outerR: 348, stroke: 112);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(master));

  // Adaptive foreground: the ring only, on transparency, shrunk into the ~66%
  // safe zone so no launcher mask clips it. The green comes from the adaptive
  // background colour in pubspec.
  final foreground = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(foreground, color: img.ColorRgba8(0, 0, 0, 0));
  _drawRing(
    foreground,
    cx: 512,
    cy: 512,
    outerR: 300,
    stroke: 96,
    transparent: true,
  );
  File(
    'assets/icon/icon_foreground.png',
  ).writeAsBytesSync(img.encodePng(foreground));

  stdout.writeln('Wrote assets/icon/icon.png and icon_foreground.png');
}
