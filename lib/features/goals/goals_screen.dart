import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../core/ui/widgets/edit_sheets.dart';
import '../../data/db/user_database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/nutrients_targets.dart';
import '../../domain/tdee.dart';
import '../profile/profile_edit_screen.dart';

/// Screen 12b — the Ziele-Seite: the one place to *view* the targets and the
/// entry into editing them. Kalorien opens a sheet (manual or recalculate);
/// water, cup and factor each open their own editor.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(currentTargetProvider).value;
    final factor = ref.watch(safetyFactorProvider);
    final cupMl = ref.watch(waterCupMlProvider);
    final settings = ref.read(settingsRepositoryProvider);

    final kcal = target?.kcal ?? SettingsRepository.defaultKcal;
    final waterMl = target?.waterMl ?? SettingsRepository.defaultWaterMl;
    final macros = _macrosOf(target, kcal);
    final isAuto = target?.isAuto ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            BoldHeader(
              title: 'DEINE ZIELE',
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Zurück',
                onPressed: Navigator.of(context).pop,
              ),
            ),
            const SizedBox(height: 8),
            _KcalHero(
              kcal: kcal,
              macros: macros,
              isAuto: isAuto,
              onEdit: () => _editKcal(context, ref, kcal),
            ),
            const SectionHeader(title: 'WEITERE ZIELE'),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.screenPadding,
              ),
              child: Column(
                children: [
                  BoldListRow(
                    icon: Icons.water_drop,
                    label: 'Wasserziel',
                    value: '$waterMl ml',
                    onTap: () async {
                      final v = await promptNumber(
                        context,
                        title: 'Wasserziel',
                        suffix: 'ml',
                        initial: waterMl.toDouble(),
                      );
                      if (v != null) {
                        await settings.setTarget(waterMl: v.round());
                      }
                    },
                  ),
                  const SizedBox(height: AppTheme.rowGap),
                  BoldListRow(
                    icon: Icons.local_drink,
                    label: 'Glasgröße',
                    value: '$cupMl ml',
                    onTap: () async {
                      final v = await promptNumber(
                        context,
                        title: 'Glasgröße',
                        suffix: 'ml',
                        initial: cupMl.toDouble(),
                      );
                      if (v != null) {
                        await settings.setWaterCupMl(v.round());
                      }
                    },
                  ),
                  const SizedBox(height: AppTheme.rowGap),
                  BoldListRow(
                    icon: Icons.shield,
                    label: 'Sicherheitsfaktor',
                    subtitle: 'Skaliert manuell erfasste Aktivität',
                    iconColor: AppColors.coral,
                    trailing: Text(
                      factor.toStringAsFixed(2).replaceAll('.', ','),
                      style: AppText.anton(size: 18, color: AppColors.coral),
                    ),
                    onTap: () async {
                      final v = await promptFactor(context, initial: factor);
                      if (v != null) {
                        await settings.setSafetyFactor(v);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editKcal(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final outcome = await _showKcalSheet(context, current);
    if (outcome == null || !context.mounted) return;

    switch (outcome) {
      case _ManualKcal(:final kcal):
        // A manual figure re-derives a balanced macro split from it, so the
        // hero's bar stays consistent, and marks the target no longer auto.
        final macros = defaultMacrosFor(kcal);
        await ref
            .read(settingsRepositoryProvider)
            .setTarget(
              kcal: kcal,
              proteinG: macros.proteinG,
              carbsG: macros.carbsG,
              fatG: macros.fatG,
              isAuto: false,
            );
      case _Recalculate():
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
        );
    }
  }

  static MacroTargets _macrosOf(TargetRow? target, double kcal) {
    if (target?.proteinG != null &&
        target?.carbsG != null &&
        target?.fatG != null) {
      return MacroTargets(
        proteinG: target!.proteinG!,
        carbsG: target.carbsG!,
        fatG: target.fatG!,
      );
    }
    return defaultMacrosFor(kcal);
  }
}

/// The tappable calorie hero with its macro split (→ Kalorien-Sheet).
class _KcalHero extends StatelessWidget {
  const _KcalHero({
    required this.kcal,
    required this.macros,
    required this.isAuto,
    required this.onEdit,
  });

  final double kcal;
  final MacroTargets macros;
  final bool isAuto;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPadding,
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TAGESKALORIEN',
                          style: AppText.grotesk(
                            size: 11,
                            weight: 700,
                            color: AppColors.textMute,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                formatKcal(kcal),
                                style: AppText.anton(size: 56, height: 1),
                              ),
                              Text(
                                ' kcal',
                                style: AppText.grotesk(
                                  size: 13,
                                  weight: 600,
                                  color: AppColors.textUnit,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _ChangePill(),
                ],
              ),
              const SizedBox(height: 16),
              _MacroBar(macros: macros),
              const SizedBox(height: 12),
              Text(
                isAuto
                    ? 'Zuletzt aus deinen Körperdaten berechnet · manuell '
                          'überschreibbar'
                    : 'Manuell gesetzt · antippen zum Ändern',
                style: AppText.grotesk(
                  size: 11,
                  weight: 500,
                  color: AppColors.textFaint,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: AppColors.lime, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.edit, size: 15, color: AppColors.lime),
          const SizedBox(width: 6),
          Text(
            'ÄNDERN',
            style: AppText.grotesk(
              size: 11,
              weight: 700,
              color: AppColors.lime,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// A stacked carbs/protein/fat bar plus the three gram values.
class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.macros});

  final MacroTargets macros;

  @override
  Widget build(BuildContext context) {
    final total = macros.carbsG + macros.proteinG + macros.fatG;
    int flex(double g) =>
        total <= 0 ? 1 : (g / total * 1000).round().clamp(1, 1000);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              Expanded(
                flex: flex(macros.carbsG),
                child: Container(height: 14, color: AppColors.carbs),
              ),
              Expanded(
                flex: flex(macros.proteinG),
                child: Container(height: 14, color: AppColors.protein),
              ),
              Expanded(
                flex: flex(macros.fatG),
                child: Container(height: 14, color: AppColors.fat),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MacroValue('Kohlenh.', AppColors.carbs, macros.carbsG),
            _MacroValue('Eiweiß', AppColors.protein, macros.proteinG),
            _MacroValue('Fett', AppColors.fat, macros.fatG),
          ],
        ),
      ],
    );
  }
}

class _MacroValue extends StatelessWidget {
  const _MacroValue(this.label, this.color, this.grams);

  final String label;
  final Color color;
  final double grams;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.grotesk(
                    size: 10,
                    weight: 600,
                    color: AppColors.textMute,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${grams.round()} g', style: AppText.anton(size: 16)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────── Kalorien bottom-sheet (12c)

sealed class _KcalOutcome {
  const _KcalOutcome();
}

class _ManualKcal extends _KcalOutcome {
  const _ManualKcal(this.kcal);
  final double kcal;
}

class _Recalculate extends _KcalOutcome {
  const _Recalculate();
}

Future<_KcalOutcome?> _showKcalSheet(BuildContext context, double current) {
  return showModalBottomSheet<_KcalOutcome>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _KcalSheet(initial: current),
    ),
  );
}

class _KcalSheet extends StatefulWidget {
  const _KcalSheet({required this.initial});

  final double initial;

  @override
  State<_KcalSheet> createState() => _KcalSheetState();
}

class _KcalSheetState extends State<_KcalSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial.round().toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_controller.text.replaceAll(',', '.'));
    return (v != null && v > 0) ? v : null;
  }

  void _step(int delta) {
    final base = _value ?? widget.initial;
    final next = (base + delta).clamp(500, 8000).round();
    setState(() => _controller.text = next.toString());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          4,
          AppTheme.screenPadding,
          20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TAGESKALORIEN ANPASSEN', style: AppText.section(size: 18)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: AppText.anton(size: 38),
                    decoration: const InputDecoration(
                      isDense: true,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.strokeDashed),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.lime, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'kcal',
                  style: AppText.grotesk(
                    size: 14,
                    weight: 600,
                    color: AppColors.textMute,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final step in const [-100, -50, 50, 100]) ...[
                  if (step != -100) const SizedBox(width: 8),
                  Expanded(
                    child: _StepChip(step: step, onTap: () => _step(step)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.stroke)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'ODER',
                    style: AppText.grotesk(
                      size: 11,
                      weight: 700,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.stroke)),
              ],
            ),
            const SizedBox(height: 12),
            _RecalculateRow(
              onTap: () => Navigator.of(context).pop(const _Recalculate()),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'SPEICHERN',
              icon: Icons.check_circle,
              radius: AppRadii.fab,
              onPressed: _value == null
                  ? null
                  : () => Navigator.of(context).pop(_ManualKcal(_value!)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.step, required this.onTap});

  final int step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              '${step > 0 ? '+' : '−'}${step.abs()}',
              style: AppText.grotesk(size: 14, weight: 700),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecalculateRow extends StatelessWidget {
  const _RecalculateRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.lime, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
          child: Row(
            children: [
              const Icon(
                Icons.calculate_outlined,
                size: 22,
                color: AppColors.lime,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aus Körperdaten neu berechnen',
                      style: AppText.grotesk(size: 14, weight: 600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Alter, Größe, Gewicht, Aktivität & Ziel',
                      style: AppText.rowSubtitle(),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.chevron,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
