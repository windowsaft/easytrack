import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/body_data_fields.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../domain/tdee.dart';

/// Screen 11a — the calculator: body stats in, a recommended calorie target out.
///
/// A single page. Reached only from the Ziele-Seite's Kalorien-Sheet ("neu
/// berechnen"); ÜBERNEHMEN saves the computed target and pops straight back to
/// the Ziele-Seite the user came from. Water / cup / safety-factor are edited on
/// the Ziele-Seite itself, so they are not repeated here.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  Sex? _sex;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _rate;
  ActivityLevel _activity = ActivityLevel.moderate;
  WeightGoal _goal = WeightGoal.maintain;
  var _prefilled = false;

  @override
  void initState() {
    super.initState();
    _age = TextEditingController()..addListener(_onChanged);
    _height = TextEditingController()..addListener(_onChanged);
    _weight = TextEditingController()..addListener(_onChanged);
    _rate = TextEditingController(text: '0.5')..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrefill());
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [_age, _height, _weight, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  void _maybePrefill() {
    if (_prefilled || !mounted) return;
    final profileAsync = ref.read(userProfileProvider);
    final weightAsync = ref.read(latestWeightProvider);
    if (!profileAsync.hasValue || !weightAsync.hasValue) return;
    final profile = profileAsync.value;
    final weight = weightAsync.value;
    _prefilled = true;

    setState(() {
      _sex = Sex.fromWire(profile?.sex);
      _activity = ActivityLevel.fromWire(profile?.activityLevel);
      _goal = WeightGoal.fromWire(profile?.goal);
      if (profile?.birthDate != null) {
        _age.text = _ageFrom(profile!.birthDate!).toString();
      }
      if (profile?.heightCm != null) _height.text = _trim(profile!.heightCm!);
      if (weight != null) _weight.text = _trim(weight);
      if ((profile?.rateKgPerWeek ?? 0) > 0) {
        _rate.text = _trim(profile!.rateKgPerWeek);
      }
    });
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  TdeeInputs? get _inputs {
    final sex = _sex;
    final age = int.tryParse(_age.text) ?? 0;
    if (sex == null) return null;
    final inputs = TdeeInputs(
      sex: sex,
      age: age,
      heightCm: _num(_height),
      weightKg: _num(_weight),
      activity: _activity,
      goal: _goal,
      rateKgPerWeek: _goal == WeightGoal.maintain ? 0 : _num(_rate),
    );
    return inputs.isComplete ? inputs : null;
  }

  Future<void> _save() async {
    final inputs = _inputs;
    if (inputs == null) return;
    final navigator = Navigator.of(context);

    await ref
        .read(settingsRepositoryProvider)
        .saveProfileAndTarget(
          sex: inputs.sex,
          birthDate: _birthDateFor(inputs.age),
          heightCm: inputs.heightCm,
          weightKg: inputs.weightKg,
          activity: inputs.activity,
          goal: inputs.goal,
          rateKgPerWeek: inputs.rateKgPerWeek,
        );

    // Back to the Ziele-Seite the user came from; it reflects the new target.
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userProfileProvider, (_, _) => _maybePrefill());
    ref.listen(latestWeightProvider, (_, _) => _maybePrefill());

    final inputs = _inputs;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: 'DEIN KÖRPER',
              leading: SquareIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Zurück',
                onPressed: Navigator.of(context).pop,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.screenPadding,
                  8,
                  AppTheme.screenPadding,
                  24,
                ),
                children: [
                  _label('GESCHLECHT'),
                  Row(
                    children: [
                      for (final sex in Sex.values) ...[
                        if (sex != Sex.values.first) const SizedBox(width: 8),
                        BoldChip(
                          label: sex.label,
                          selected: _sex == sex,
                          onTap: () => setState(() => _sex = sex),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: LabeledNumberField(
                          controller: _age,
                          label: 'Alter',
                          suffix: 'Jahre',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LabeledNumberField(
                          controller: _height,
                          label: 'Größe',
                          suffix: 'cm',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LabeledNumberField(
                          controller: _weight,
                          label: 'Gewicht',
                          suffix: 'kg',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _label('AKTIVITÄT'),
                  for (final level in ActivityLevel.values) ...[
                    if (level != ActivityLevel.values.first)
                      const SizedBox(height: AppTheme.rowGap),
                    ActivityLevelRow(
                      level: level,
                      selected: _activity == level,
                      onTap: () => setState(() => _activity = level),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _label('ZIEL'),
                  Row(
                    children: [
                      for (final goal in WeightGoal.values) ...[
                        if (goal != WeightGoal.values.first)
                          const SizedBox(width: 8),
                        Expanded(
                          child: BoldChip(
                            label: goal.label,
                            selected: _goal == goal,
                            onTap: () => setState(() => _goal = goal),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_goal != WeightGoal.maintain) ...[
                    const SizedBox(height: 12),
                    LabeledNumberField(
                      controller: _rate,
                      label: _goal == WeightGoal.lose
                          ? 'Abnehmen pro Woche'
                          : 'Zunehmen pro Woche',
                      suffix: 'kg',
                    ),
                  ],
                ],
              ),
            ),
            _PreviewBar(inputs: inputs, onSave: inputs == null ? null : _save),
          ],
        ),
      ),
    );
  }

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(text, style: AppText.section(size: 14)),
  );

  static int _ageFrom(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age -= 1;
    }
    return age;
  }

  static DateTime _birthDateFor(int age) {
    final now = DateTime.now();
    return DateTime(now.year - age, now.month, now.day);
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}

/// The sticky footer: the live recommended target and ÜBERNEHMEN.
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.inputs, required this.onSave});

  final TdeeInputs? inputs;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final kcal = inputs == null ? null : recommendedCalorieTarget(inputs!);

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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        kcal == null ? '—' : formatKcal(kcal),
                        style: AppText.anton(size: 26, height: 1),
                      ),
                      if (kcal != null)
                        Text(
                          ' kcal',
                          style: AppText.grotesk(
                            size: 12,
                            weight: 600,
                            color: AppColors.textMute,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'EMPFOHLENES ZIEL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 14),
          // Hugs the right edge (the preview eats the free space) rather than
          // stretching across the bar. IntrinsicWidth gives the button a bounded
          // width equal to its content, which its inner Center requires.
          IntrinsicWidth(
            child: PrimaryButton(
              label: 'ÜBERNEHMEN',
              icon: Icons.check_circle,
              height: 52,
              radius: AppRadii.fab,
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

