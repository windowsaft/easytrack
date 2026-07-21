import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../core/ui/widgets/calorie_gauge.dart';
import '../../core/ui/widgets/edit_sheets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/nutrients_targets.dart';
import '../../domain/tdee.dart';

/// Screen 11a ⇄ 11b — the calculator, in two views.
///
/// **View 1 (ANGABEN)** gathers body stats; **view 2 (ZIELE)** shows the computed
/// targets and lets each be overridden before ÜBERNEHMEN writes them. Reached
/// only from the Kalorien-Sheet's "neu berechnen" row (one home for computing
/// targets). Mifflin-St Jeor drives the calorie figure.
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

  // View-2 overrides. Null until the user changes one; otherwise the computed /
  // current value is shown and used.
  double? _kcalOverride;
  int? _waterMl;
  int? _cupMl;
  double? _factor;

  final _pager = PageController();
  int _page = 0;
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
    _pager.dispose();
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
      // The "weitere Ziele" start from what is currently set.
      final target = ref.read(currentTargetProvider).value;
      _waterMl = target?.waterMl ?? SettingsRepository.defaultWaterMl;
      _cupMl = ref.read(waterCupMlProvider);
      _factor = ref.read(safetyFactorProvider);
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

  double? get _computedKcal {
    final inputs = _inputs;
    return inputs == null ? null : recommendedCalorieTarget(inputs);
  }

  double? get _finalKcal => _kcalOverride ?? _computedKcal;

  void _goToPage(int page) {
    _pager.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _save() async {
    final inputs = _inputs;
    final kcal = _finalKcal;
    if (inputs == null || kcal == null) return;

    final navigator = Navigator.of(context);
    final settings = ref.read(settingsRepositoryProvider);

    await settings.saveProfileAndTarget(
      sex: inputs.sex,
      birthDate: _birthDateFor(inputs.age),
      heightCm: inputs.heightCm,
      weightKg: inputs.weightKg,
      activity: inputs.activity,
      goal: inputs.goal,
      rateKgPerWeek: inputs.rateKgPerWeek,
    );

    // Write the final target deterministically — a manual kcal override wins and
    // marks the target non-auto; otherwise the computed value stands.
    final macros = defaultMacrosFor(kcal);
    await settings.setTarget(
      kcal: kcal.roundToDouble(),
      proteinG: macros.proteinG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
      waterMl: _waterMl,
      isAuto: _kcalOverride == null,
    );
    if (_cupMl != null) await settings.setWaterCupMl(_cupMl!);
    if (_factor != null) await settings.setSafetyFactor(_factor!);

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userProfileProvider, (_, _) => _maybePrefill());
    ref.listen(latestWeightProvider, (_, _) => _maybePrefill());

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
            _StepTabs(
              current: _page,
              canAdvance: _inputs != null,
              onSelect: _goToPage,
            ),
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (p) => setState(() => _page = p),
                // Only allow swiping forward once the inputs compute.
                physics: _inputs == null
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                children: [_angabenView(), _zieleView()],
              ),
            ),
            _page == 0 ? _angabenBar() : _zieleBar(),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────── view 1: inputs

  Widget _angabenView() {
    return ListView(
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
              if (goal != WeightGoal.values.first) const SizedBox(width: 8),
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
    );
  }

  Widget _angabenBar() {
    final kcal = _computedKcal;
    return _BottomBar(
      leading: Column(
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
                  kcal == null ? '—' : 'Ergibt ${formatKcal(kcal)}',
                  style: AppText.anton(size: 22, height: 1),
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
            'VORAUSSICHTLICHES ZIEL',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.grotesk(
              size: 10,
              weight: 600,
              color: AppColors.textMute,
              letterSpacing: 0.66,
            ),
          ),
        ],
      ),
      button: PrimaryButton(
        label: 'ZIELE →',
        height: 52,
        radius: AppRadii.fab,
        onPressed: kcal == null ? null : () => _goToPage(1),
      ),
    );
  }

  // ─────────────────────────────────────────────────── view 2: computed goals

  Widget _zieleView() {
    final kcal = _finalKcal;
    if (kcal == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Fülle zuerst die Angaben aus.',
            textAlign: TextAlign.center,
            style: AppText.grotesk(size: 14, color: AppColors.textMute),
          ),
        ),
      );
    }
    final macros = defaultMacrosFor(kcal);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        10,
        AppTheme.screenPadding,
        24,
      ),
      children: [
        Text(
          'Aus deinen Angaben berechnet · antippen zum Überschreiben',
          style: AppText.grotesk(
            size: 12,
            weight: 500,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 12),
        _ComputedHero(kcal: kcal, macros: macros, onEdit: _overrideKcal),
        const SectionHeader(
          title: 'WEITERE ZIELE',
          padding: EdgeInsets.only(top: 14, bottom: 6),
        ),
        BoldListRow(
          icon: Icons.water_drop,
          label: 'Wasserziel',
          value: '${_waterMl ?? SettingsRepository.defaultWaterMl} ml',
          onTap: () async {
            final v = await promptNumber(
              context,
              title: 'Wasserziel',
              suffix: 'ml',
              initial: (_waterMl ?? SettingsRepository.defaultWaterMl)
                  .toDouble(),
            );
            if (v != null) setState(() => _waterMl = v.round());
          },
        ),
        const SizedBox(height: AppTheme.rowGap),
        BoldListRow(
          icon: Icons.local_drink,
          label: 'Glasgröße',
          value: '${_cupMl ?? SettingsRepository.defaultWaterCupMl} ml',
          onTap: () async {
            final v = await promptNumber(
              context,
              title: 'Glasgröße',
              suffix: 'ml',
              initial: (_cupMl ?? SettingsRepository.defaultWaterCupMl)
                  .toDouble(),
            );
            if (v != null) setState(() => _cupMl = v.round());
          },
        ),
        const SizedBox(height: AppTheme.rowGap),
        BoldListRow(
          icon: Icons.shield,
          label: 'Sicherheitsfaktor',
          iconColor: AppColors.coral,
          trailing: Text(
            (_factor ?? SettingsRepository.defaultSafetyFactor)
                .toStringAsFixed(2)
                .replaceAll('.', ','),
            style: AppText.anton(size: 18, color: AppColors.coral),
          ),
          onTap: () async {
            final v = await promptFactor(
              context,
              initial: _factor ?? SettingsRepository.defaultSafetyFactor,
            );
            if (v != null) setState(() => _factor = v);
          },
        ),
      ],
    );
  }

  Future<void> _overrideKcal() async {
    final v = await promptNumber(
      context,
      title: 'Tageskalorien',
      suffix: 'kcal',
      initial: _finalKcal ?? SettingsRepository.defaultKcal,
    );
    if (v != null) setState(() => _kcalOverride = v);
  }

  Widget _zieleBar() {
    return _BottomBar(
      leading: Text(
        _kcalOverride == null ? 'Berechnet' : 'Manuell angepasst',
        style: AppText.grotesk(
          size: 13,
          weight: 600,
          color: AppColors.textMute,
        ),
      ),
      button: PrimaryButton(
        label: 'ÜBERNEHMEN',
        icon: Icons.check_circle,
        height: 52,
        radius: AppRadii.fab,
        onPressed: _finalKcal == null ? null : _save,
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

/// The two underline step-tabs. Not pills — pills read as form inputs.
class _StepTabs extends StatelessWidget {
  const _StepTabs({
    required this.current,
    required this.canAdvance,
    required this.onSelect,
  });

  final int current;
  final bool canAdvance;
  final ValueChanged<int> onSelect;

  static const _titles = ['1  ANGABEN', '2  ZIELE'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        4,
        AppTheme.screenPadding,
        0,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _titles.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (i == 1 && !canAdvance) ? null : () => onSelect(i),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        _titles[i],
                        style: AppText.grotesk(
                          size: 12,
                          weight: 700,
                          color: current == i
                              ? AppColors.lime
                              : (i == 1 && !canAdvance
                                    ? AppColors.textFaint
                                    : AppColors.textMute),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Container(
                      height: 2,
                      color: current == i
                          ? AppColors.lime
                          : AppColors.strokeDashed,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The computed calorie hero on view 2 — lime here (vs. white on the Ziele-Seite).
class _ComputedHero extends StatelessWidget {
  const _ComputedHero({
    required this.kcal,
    required this.macros,
    required this.onEdit,
  });

  final double kcal;
  final MacroTargets macros;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final total = macros.carbsG + macros.proteinG + macros.fatG;
    int flex(double g) =>
        total <= 0 ? 1 : (g / total * 1000).round().clamp(1, 1000);

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                                style: AppText.anton(
                                  size: 46,
                                  height: 1,
                                  color: AppColors.lime,
                                ),
                              ),
                              Text(
                                ' kcal',
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
                  ),
                  const Icon(Icons.edit, size: 20, color: AppColors.textMute),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Expanded(
                      flex: flex(macros.carbsG),
                      child: Container(height: 12, color: AppColors.carbs),
                    ),
                    Expanded(
                      flex: flex(macros.proteinG),
                      child: Container(height: 12, color: AppColors.protein),
                    ),
                    Expanded(
                      flex: flex(macros.fatG),
                      child: Container(height: 12, color: AppColors.fat),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'KH ${macros.carbsG.round()} g · EW ${macros.proteinG.round()} g '
                '· F ${macros.fatG.round()} g',
                style: AppText.grotesk(
                  size: 11,
                  weight: 600,
                  color: AppColors.textMute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sticky footer shared by both views.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.leading, required this.button});

  final Widget leading;
  final Widget button;

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
      child: Row(
        children: [
          Flexible(child: leading),
          const SizedBox(width: 14),
          Expanded(child: button),
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
