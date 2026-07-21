import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The 44x44 outlined icon button used in every screen header.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconSize = 24,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.iconButton),
          side: const BorderSide(color: AppColors.strokeButton, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Icon(icon, size: iconSize, color: AppColors.lime),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// A screen header: back/prev button, centred overline + Anton title, trailing
/// slot. The trailing slot is padded to the button width even when empty so the
/// title stays optically centred.
class BoldHeader extends StatelessWidget {
  const BoldHeader({
    required this.title,
    this.overline,
    this.leading,
    this.trailing,
    this.titleSize = 28,
    super.key,
  });

  final String title;
  final String? overline;
  final Widget? leading;
  final Widget? trailing;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        12,
        AppTheme.screenPadding,
        4,
      ),
      child: Row(
        children: [
          leading ?? const SizedBox(width: 44, height: 44),
          Expanded(
            child: Column(
              children: [
                if (overline != null)
                  Text(
                    overline!,
                    style: AppText.overline(),
                    textAlign: TextAlign.center,
                  ),
                // German meal names are far longer than the English ones the
                // design was drawn with ("FRÜHSTÜCK" vs "BREAKFAST"), so the
                // Anton title shrinks rather than wrapping or clipping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: AppText.anton(
                      size: titleSize,
                      color: AppColors.text,
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox(width: 44, height: 44),
        ],
      ),
    );
  }
}

/// An Anton section heading, optionally with a muted caption on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.trailing,
    this.size = 16,
    this.color = AppColors.textBright,
    this.padding = const EdgeInsets.fromLTRB(
      AppTheme.screenPadding,
      14,
      AppTheme.screenPadding,
      6,
    ),
    super.key,
  });

  final String title;
  final Widget? trailing;
  final double size;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppText.section(size: size, color: color),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The full-width lime call to action ("SPEICHERN", "ZU FRÜHSTÜCK").
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 54,
    this.radius = AppRadii.button,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  /// Corner radius. Defaults to the square-ish button radius; the profile
  /// preview's ÜBERNEHMEN uses the rounder [AppRadii.fab] to echo the nav FAB.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      child: Material(
        color: enabled ? AppColors.lime : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 22,
                    color: enabled ? AppColors.bg : AppColors.textFaint,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(
                      size: 15,
                      weight: 700,
                      color: enabled ? AppColors.bg : AppColors.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The outlined counterpart to [PrimaryButton] ("FERTIG").
class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          side: const BorderSide(color: AppColors.strokeDashed, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: AppColors.lime),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppText.grotesk(
                    size: 15,
                    weight: 700,
                    color: AppColors.lime,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable pill: search tabs and activity-type chips.
class BoldChip extends StatelessWidget {
  const BoldChip({
    required this.label,
    required this.selected,
    this.icon,
    this.onTap,
    this.radius = AppRadii.tab,
    super.key,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.lime : AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: icon == null ? 16 : 14,
            vertical: icon == null ? 8 : 9,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 19,
                  color: selected ? AppColors.bg : AppColors.textMute2,
                ),
                const SizedBox(width: 7),
              ],
              // Flexible + ellipsis so a chip placed in an Expanded slot (the
              // goal row uses three across) shrinks a long German label instead
              // of overflowing. In an unconstrained row it sizes to content.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppText.grotesk(
                    size: 13,
                    weight: selected ? 700 : 600,
                    color: selected ? AppColors.bg : AppColors.textMute2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed-border quick action ("Schnell-Eintrag", "Lebensmittel anlegen").
class DashedActionChip extends StatelessWidget {
  const DashedActionChip({
    required this.label,
    required this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(radius: AppRadii.chip),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: AppColors.lime),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppText.grotesk(
                    size: 13,
                    weight: 600,
                    color: AppColors.lime,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed rectangle stroke. Flutter has no dashed [BorderSide], and the design
/// uses one for every "nothing here yet" affordance.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({this.radius = 0});

  final double radius;

  static const color = AppColors.strokeDashed;
  static const strokeWidth = 1.5;
  static const dash = 5.0;
  static const gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            strokeWidth / 2,
            strokeWidth / 2,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

/// Wraps a child in the dashed border used by empty states.
class DashedBox extends StatelessWidget {
  const DashedBox({required this.child, this.radius = 0, super.key});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorderPainter(radius: radius),
    child: child,
  );
}

/// The 42x42 rounded icon tile that stands in for a food photo.
class TileIcon extends StatelessWidget {
  const TileIcon({
    required this.icon,
    this.color = AppColors.lime,
    this.size = 42,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

/// A settings/menu row: icon, label, optional value, optional chevron.
class BoldListRow extends StatelessWidget {
  const BoldListRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = true,
    this.highlight = false,
    this.highlightColor = AppColors.lime,
    this.iconColor = AppColors.lime,
    this.labelColor = AppColors.text,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  /// Draws the selected treatment: lifted background plus a 3px left border in
  /// [highlightColor]. The design uses it to mark a row that stands out —
  /// [AppColors.lime] by default, coral for the safety-factor row.
  final bool highlight;
  final Color highlightColor;
  final Color iconColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight ? AppColors.selectedRow : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: highlight
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: highlightColor, width: 3),
                  ),
                )
              : null,
          padding: EdgeInsets.fromLTRB(highlight ? 11 : 14, 12, 14, 12),
          child: Row(
            children: [
              Icon(icon, size: 21, color: iconColor),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.grotesk(
                        size: 14,
                        weight: 600,
                        color: labelColor,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: AppText.rowSubtitle()),
                      ),
                  ],
                ),
              ),
              // Flexible, not bare: a Row lays non-flex children out at their
              // natural width, so a long value ("Metrisch · g, kg, ml") pushes
              // the row past the screen edge instead of yielding space.
              if (value != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppText.grotesk(
                        size: 13,
                        weight: 700,
                        color: AppColors.textMute,
                      ),
                    ),
                  ),
                ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: trailing!,
                ),
              if (chevron)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 19,
                    color: AppColors.chevron,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 44x26 switch. Cupertino/Material switches cannot be squared off to this
/// geometry, and the design's on-state uses the lime accent as the track.
class BoldToggle extends StatelessWidget {
  const BoldToggle({required this.value, this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? AppColors.lime : AppColors.strokeDashed,
            borderRadius: BorderRadius.circular(AppRadii.toggle),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? AppColors.bg : AppColors.textFaint,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A stat tile with a coloured left border: the macro blocks on the diary and
/// the three tiles on the profile.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.accent,
    this.suffix,
    this.valueSize = 24,
    super.key,
  });

  final String label;
  final String value;
  final String? suffix;
  final Color accent;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.grotesk(
              size: 10,
              weight: 700,
              color: AppColors.textMute,
              letterSpacing: 1.2,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: AppText.anton(size: valueSize, height: 1.1)),
                if (suffix != null)
                  Text(
                    suffix!,
                    style: AppText.grotesk(
                      size: 12,
                      weight: 600,
                      color: AppColors.textUnit,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
