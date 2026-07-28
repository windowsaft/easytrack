import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/i18n/number_format.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../l10n/app_localizations.dart';
import 'activity_types.dart';

/// Screen 5a — log burned calories by typing them.
///
/// Duration and intensity are intentionally out of scope: the app never
/// estimates a burn, so a duration would be decoration next to a number the
/// user typed themselves.
class AddActivityScreen extends ConsumerStatefulWidget {
  const AddActivityScreen({super.key});

  @override
  ConsumerState<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends ConsumerState<AddActivityScreen> {
  ActivityType _type = ActivityType.bike;
  String _input = '';

  int get _entered => int.tryParse(_input) ?? 0;

  void _press(String digit) {
    // Four digits is 9999 kcal — past any real session, and it keeps the Anton
    // display from having to shrink to fit.
    if (_input.length >= 4) return;
    setState(() => _input = (_input + digit).replaceFirst(RegExp(r'^0+'), ''));
  }

  void _backspace() {
    if (_input.isEmpty) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  Future<void> _save(double factor) async {
    final day = ref.read(selectedDayProvider);
    final navigator = Navigator.of(context);

    await ref
        .read(diaryRepositoryProvider)
        .addActivity(
          day: day,
          label: _type.label(AppLocalizations.of(context)),
          kcalBurned: _entered.toDouble(),
          safetyFactor: factor,
        );

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final factor = ref.watch(safetyFactorProvider);
    final logged = (_entered * factor).round();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              overline: l10n.activityOverline.toUpperCase(),
              title: l10n.commonActivity.toUpperCase(),
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: l10n.commonBack,
                onPressed: Navigator.of(context).pop,
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.screenPadding,
                  14,
                  AppTheme.screenPadding,
                  4,
                ),
                itemCount: ActivityType.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final type = ActivityType.values[index];
                  return BoldChip(
                    label: type.label(l10n),
                    icon: type.icon,
                    radius: AppRadii.chip,
                    selected: type == _type,
                    onTap: () => setState(() => _type = type),
                  );
                },
              ),
            ),
            _ManualDisplay(value: _entered),
            _SafetyFactorCard(factor: factor, logged: logged),
            Expanded(
              child: _Keypad(onDigit: _press, onBackspace: _backspace),
            ),
            _SaveBar(onSave: _entered <= 0 ? null : () => _save(factor)),
          ],
        ),
      ),
    );
  }
}

class _ManualDisplay extends StatelessWidget {
  const _ManualDisplay({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        22,
        AppTheme.screenPadding,
        14,
      ),
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context).activityBurnedManual.toUpperCase(),
            style: AppText.grotesk(
              size: 11,
              weight: 700,
              color: AppColors.textMute,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value.toString(),
                style: AppText.anton(
                  size: 72,
                  color: AppColors.textHi,
                  height: 0.85,
                ),
              ),
              const SizedBox(width: 6),
              // Stands in for a text cursor: the number is edited by the
              // keypad below, so there is no real field to focus.
              Container(
                width: 3,
                height: 48,
                margin: const EdgeInsets.only(bottom: 4),
                color: AppColors.lime,
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'kcal',
                  style: AppText.grotesk(
                    size: 18,
                    weight: 700,
                    color: AppColors.textMute,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetyFactorCard extends StatelessWidget {
  const _SafetyFactorCard({required this.factor, required this.logged});

  final double factor;
  final int logged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.lime, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(13, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.shield, size: 24, color: AppColors.lime),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.activityFactorLabel(
                          formatFixed(factor, 2),
                        ),
                        style: AppText.grotesk(size: 13, weight: 700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.textMute,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.settingsTitle.toUpperCase(),
                        style: AppText.grotesk(
                          size: 9,
                          weight: 700,
                          color: AppColors.bg,
                          letterSpacing: 0.72,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.activityFactorHint,
                  style: AppText.rowSubtitle(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                logged.toString(),
                style: AppText.anton(
                  size: 24,
                  color: AppColors.lime,
                  height: 1,
                ),
              ),
              Text(
                l10n.activityBooked.toUpperCase(),
                style: AppText.grotesk(
                  size: 9,
                  weight: 700,
                  color: AppColors.textMute,
                  letterSpacing: 0.54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        16,
        AppTheme.screenPadding,
        0,
      ),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: AppTheme.rowGap,
        crossAxisSpacing: AppTheme.rowGap,
        childAspectRatio: 2.0,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        children: [
          for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
            _Key(label: digit, onTap: () => onDigit(digit)),
          const _Key(label: null),
          _Key(label: '0', onTap: () => onDigit('0')),
          _Key(icon: Icons.backspace_outlined, onTap: onBackspace),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFiller = label == null && icon == null;

    return Material(
      color: isFiller || icon != null ? AppColors.bar : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 26, color: AppColors.lime)
              : label == null
              ? null
              : Text(label!, style: AppText.anton(size: 26)),
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onSave});

  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bar,
        border: Border(top: BorderSide(color: AppColors.stroke, width: 1.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        14,
        AppTheme.screenPadding,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: PrimaryButton(
        label: AppLocalizations.of(context).activitySave.toUpperCase(),
        icon: Icons.check_circle,
        onPressed: onSave,
      ),
    );
  }
}
