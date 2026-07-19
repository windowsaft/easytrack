import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../domain/tdee.dart';

/// Phase 7 — the profile form that computes a calorie target from body stats.
///
/// Feeds Mifflin-St Jeor: sex, age, height, weight, activity and goal in; a
/// recommended daily target out, written to the target history as an automatic
/// value. A live preview shows the number update as the fields change, so the
/// effect of, say, a more active lifestyle is visible before saving.
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
    // The profile arrives asynchronously; try once the first frame is up, and
    // again whenever the streams deliver (handled by ref.listen in build).
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

  /// Fills the form from the stored profile the first time data is available.
  ///
  /// Runs outside the build phase — from a post-frame callback and from
  /// [ref.listen] — because it writes to the controllers, which notifies their
  /// listeners; doing that during build would be a setState-in-build error.
  void _maybePrefill() {
    if (_prefilled || !mounted) return;
    final profileAsync = ref.read(userProfileProvider);
    final weightAsync = ref.read(latestWeightProvider);
    // Wait until *both* streams have delivered, not just one. They emit
    // independently, and prefilling on the profile alone would leave the weight
    // field blank when the weight stream lags a frame behind. Either value may
    // legitimately be null (a user who has never filled the form or weighed in).
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
      if (profile?.heightCm != null) {
        _height.text = _trim(profile!.heightCm!);
      }
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
    final messenger = ScaffoldMessenger.of(context);

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

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Ziel aktualisiert: '
          '${formatKcal(recommendedCalorieTarget(inputs))} kcal',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Prefill when the profile or weight streams first deliver. ref.listen
    // fires after build, so writing to the controllers here is safe.
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
                        child: _NumberField(
                          controller: _age,
                          label: 'Alter',
                          suffix: 'Jahre',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumberField(
                          controller: _height,
                          label: 'Größe',
                          suffix: 'cm',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NumberField(
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
                    _ActivityRow(
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
                    _NumberField(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    kcal == null ? '—' : formatKcal(kcal),
                    style: AppText.anton(size: 26, height: 1),
                  ),
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
              Text(
                'EMPFOHLENES ZIEL',
                style: AppText.grotesk(
                  size: 11,
                  weight: 600,
                  color: AppColors.textMute,
                  letterSpacing: 0.66,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: PrimaryButton(
              label: 'ÜBERNEHMEN',
              icon: Icons.check_circle,
              height: 52,
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final ActivityLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selectedRow : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: selected
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.lime, width: 3),
                  ),
                )
              : null,
          padding: EdgeInsets.fromLTRB(selected ? 11 : 14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.label,
                      style: AppText.grotesk(size: 14, weight: 600),
                    ),
                    const SizedBox(height: 2),
                    Text(level.hint, style: AppText.rowSubtitle()),
                  ],
                ),
              ),
              Text(
                '×${level.factor}',
                style: AppText.anton(
                  size: 16,
                  color: selected ? AppColors.lime : AppColors.textMute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: AppText.grotesk(size: 16, weight: 600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.grotesk(
          size: 13,
          weight: 500,
          color: AppColors.textMute,
        ),
        suffixText: suffix,
        suffixStyle: AppText.grotesk(
          size: 12,
          weight: 600,
          color: AppColors.textMute,
        ),
        isDense: true,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.strokeDashed),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lime, width: 2),
        ),
      ),
    );
  }
}
