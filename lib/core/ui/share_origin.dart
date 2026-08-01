import 'package:flutter/material.dart';

/// Anchor rectangle for the system share sheet, in global coordinates.
///
/// iPad presents `UIActivityViewController` as a popover, and UIKit requires a
/// rectangle to point it at: without one the sheet either lands in a corner or
/// the presentation fails outright, which is what happens on iPad when
/// `sharePositionOrigin` is left null. iPhone and Android ignore the value.
///
/// Pass the context of the screen the share was triggered from, and read this
/// *before* any `await` — the render object is gone once the widget unmounts.
Rect shareOrigin(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}
