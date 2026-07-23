import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/body_data_fields.dart';
import '../../core/ui/widgets/bold_controls.dart';
import '../../domain/tdee.dart';
import '../backup/backup_flow.dart';
import '../shell/home_shell.dart';

/// The first-run setup. Walks a new user from a welcome through the same body
/// stats the Körperdaten calculator collects, so the app opens on a real,
/// personal calorie target instead of the 2000 kcal placeholder.
///
/// The steps mirror the calculator deliberately — one control per question,
/// the same TDEE math — but paced across pages with a progress bar, because a
/// first-time user meeting every field at once is the thing this replaces. It
/// stays skippable: the premise is a no-account personal app, so nobody is
/// forced to hand over their body stats to start logging.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, body, activity, goal, summary }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pager = PageController();
  var _step = _Step.welcome;

  Sex? _sex;
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _rate = TextEditingController(text: '0.5');
  var _activity = ActivityLevel.moderate;
  var _goal = WeightGoal.maintain;

  @override
  void initState() {
    super.initState();
    for (final c in [_age, _height, _weight, _rate]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    for (final c in [_age, _height, _weight, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  /// The collected inputs, or null while a required field is missing.
  TdeeInputs? get _inputs {
    final sex = _sex;
    if (sex == null) return null;
    final inputs = TdeeInputs(
      sex: sex,
      age: int.tryParse(_age.text) ?? 0,
      heightCm: _num(_height),
      weightKg: _num(_weight),
      activity: _activity,
      goal: _goal,
      rateKgPerWeek: _goal == WeightGoal.maintain ? 0 : _num(_rate),
    );
    return inputs.isComplete ? inputs : null;
  }

  bool get _bodyValid =>
      _sex != null &&
      (int.tryParse(_age.text) ?? 0) > 0 &&
      _num(_height) > 0 &&
      _num(_weight) > 0;

  bool get _goalValid => _goal == WeightGoal.maintain || _num(_rate) > 0;

  /// Whether the current step's primary action is allowed to advance.
  bool get _canAdvance => switch (_step) {
    _Step.welcome => true,
    _Step.body => _bodyValid,
    _Step.activity => true,
    _Step.goal => _goalValid,
    _Step.summary => _inputs != null,
  };

  void _goTo(_Step step) {
    setState(() => _step = step);
    _pager.animateToPage(
      step.index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_step == _Step.summary) {
      unawaited(_finish());
      return;
    }
    _goTo(_Step.values[_step.index + 1]);
  }

  void _back() {
    if (_step == _Step.welcome) return;
    _goTo(_Step.values[_step.index - 1]);
  }

  Future<void> _leaveTo(Widget screen) async {
    final navigator = Navigator.of(context);
    final service = await ref.read(onboardingServiceProvider.future);
    await service.markComplete();
    if (!navigator.mounted) return;
    unawaited(
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => screen),
      ),
    );
  }

  /// Skip setup and start on the default target; goals stay editable in Profil.
  Future<void> _skip() => _leaveTo(const HomeShell());

  Future<void> _finish() async {
    final inputs = _inputs;
    if (inputs == null) return;

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

    await _leaveTo(const HomeShell());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BoldHeader(
              title: _titles[_step]!,
              titleSize: 26,
              leading: _step == _Step.welcome
                  ? null
                  : SquareIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Zurück',
                      onPressed: _back,
                    ),
              trailing: SquareIconButton(
                icon: Icons.close,
                tooltip: 'Überspringen',
                onPressed: _skip,
              ),
            ),
            _ProgressBar(step: _step),
            Expanded(
              child: PageView(
                controller: _pager,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomeStep(onRestore: () => importBackup(context, ref)),
                  _BodyStep(
                    sex: _sex,
                    onSex: (s) => setState(() => _sex = s),
                    age: _age,
                    height: _height,
                    weight: _weight,
                  ),
                  _ActivityStep(
                    selected: _activity,
                    onSelect: (l) => setState(() => _activity = l),
                  ),
                  _GoalStep(
                    goal: _goal,
                    onGoal: (g) => setState(() => _goal = g),
                    rate: _rate,
                  ),
                  _SummaryStep(inputs: _inputs),
                ],
              ),
            ),
            _BottomBar(
              label: _step == _Step.summary ? 'LOSLEGEN' : 'WEITER',
              icon: _step == _Step.summary ? Icons.check_circle : null,
              onPressed: _canAdvance ? _next : null,
            ),
          ],
        ),
      ),
    );
  }

  static const _titles = {
    _Step.welcome: 'WILLKOMMEN',
    _Step.body: 'DEIN KÖRPER',
    _Step.activity: 'AKTIVITÄT',
    _Step.goal: 'DEIN ZIEL',
    _Step.summary: 'DEIN PLAN',
  };

  static DateTime _birthDateFor(int age) {
    final now = DateTime.now();
    return DateTime(now.year - age, now.month, now.day);
  }
}

/// The four data steps as a segmented bar; the welcome step shows none filled.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        10,
        AppTheme.screenPadding,
        6,
      ),
      child: Row(
        children: [
          for (var i = 1; i < _Step.values.length; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                color: i <= step.index ? AppColors.lime : AppColors.surfaceAlt,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared scroll padding so every step's body lines up under the header.
const _stepPadding = EdgeInsets.fromLTRB(
  AppTheme.screenPadding,
  14,
  AppTheme.screenPadding,
  24,
);

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onRestore});

  /// Restore a backup instead of setting up fresh — for someone reinstalling or
  /// moving to a new phone. Succeeds into an app restart, so this step is torn
  /// down rather than advanced.
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _stepPadding,
      children: [
        const SizedBox(height: 8),
        Text(
          'Dein Kalorien- und Ernährungstagebuch — komplett auf deinem Gerät.',
          style: AppText.grotesk(size: 16, weight: 600, height: 1.4),
        ),
        const SizedBox(height: 28),
        const _FeatureRow(
          icon: Icons.wifi_off,
          title: 'Offline',
          body: 'Deutsche Lebensmittel-Datenbank ohne Internet.',
        ),
        const SizedBox(height: 16),
        const _FeatureRow(
          icon: Icons.person_off_outlined,
          title: 'Kein Konto',
          body: 'Keine Anmeldung, kein Abo, keine Cloud.',
        ),
        const SizedBox(height: 16),
        const _FeatureRow(
          icon: Icons.lock_outline,
          title: 'Deine Daten',
          body: 'Alles bleibt lokal auf deinem Handy.',
        ),
        const SizedBox(height: 28),
        Text(
          'Als Nächstes richten wir dein Kalorienziel ein. Das dauert eine '
          'Minute und lässt sich jederzeit ändern.',
          style: AppText.grotesk(
            size: 13,
            weight: 500,
            color: AppColors.textMute,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        DashedBox(
          radius: AppRadii.chip,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Schon EasyTrack genutzt?',
                  style: AppText.grotesk(size: 13, weight: 700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stelle deine Daten aus einer Sicherung wieder her.',
                  style: AppText.grotesk(
                    size: 12,
                    weight: 500,
                    color: AppColors.textMute,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                OutlineActionButton(
                  label: 'SICHERUNG WIEDERHERSTELLEN',
                  icon: Icons.settings_backup_restore,
                  onPressed: onRestore,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TileIcon(icon: icon),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.grotesk(size: 15, weight: 700)),
              const SizedBox(height: 2),
              Text(
                body,
                style: AppText.grotesk(
                  size: 13,
                  weight: 500,
                  color: AppColors.textMute,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BodyStep extends StatelessWidget {
  const _BodyStep({
    required this.sex,
    required this.onSex,
    required this.age,
    required this.height,
    required this.weight,
  });

  final Sex? sex;
  final ValueChanged<Sex> onSex;
  final TextEditingController age;
  final TextEditingController height;
  final TextEditingController weight;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _stepPadding,
      children: [
        _StepLabel('GESCHLECHT'),
        Row(
          children: [
            for (final option in Sex.values) ...[
              if (option != Sex.values.first) const SizedBox(width: 8),
              BoldChip(
                label: option.label,
                selected: sex == option,
                onTap: () => onSex(option),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: LabeledNumberField(
                controller: age,
                label: 'Alter',
                suffix: 'Jahre',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledNumberField(
                controller: height,
                label: 'Größe',
                suffix: 'cm',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledNumberField(
                controller: weight,
                label: 'Gewicht',
                suffix: 'kg',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Aus diesen Werten berechnen wir deinen Grundumsatz (Mifflin-St Jeor).',
          style: AppText.grotesk(
            size: 12,
            weight: 500,
            color: AppColors.textMute,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ActivityStep extends StatelessWidget {
  const _ActivityStep({required this.selected, required this.onSelect});

  final ActivityLevel selected;
  final ValueChanged<ActivityLevel> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _stepPadding,
      children: [
        _StepLabel('WIE AKTIV BIST DU?'),
        for (final level in ActivityLevel.values) ...[
          if (level != ActivityLevel.values.first)
            const SizedBox(height: AppTheme.rowGap),
          ActivityLevelRow(
            level: level,
            selected: selected == level,
            onTap: () => onSelect(level),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Trainingseinheiten trägst du später einzeln ein — wähle hier also '
          'eher niedriger, damit Bewegung nicht doppelt zählt.',
          style: AppText.grotesk(
            size: 12,
            weight: 500,
            color: AppColors.textMute,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({
    required this.goal,
    required this.onGoal,
    required this.rate,
  });

  final WeightGoal goal;
  final ValueChanged<WeightGoal> onGoal;
  final TextEditingController rate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _stepPadding,
      children: [
        _StepLabel('WAS MÖCHTEST DU?'),
        Row(
          children: [
            for (final option in WeightGoal.values) ...[
              if (option != WeightGoal.values.first) const SizedBox(width: 8),
              Expanded(
                child: BoldChip(
                  label: option.label,
                  selected: goal == option,
                  onTap: () => onGoal(option),
                ),
              ),
            ],
          ],
        ),
        if (goal != WeightGoal.maintain) ...[
          const SizedBox(height: 16),
          LabeledNumberField(
            controller: rate,
            label: goal == WeightGoal.lose
                ? 'Abnehmen pro Woche'
                : 'Zunehmen pro Woche',
            suffix: 'kg',
          ),
          const SizedBox(height: 10),
          Text(
            '0,5 kg pro Woche ist ein gesundes Tempo.',
            style: AppText.grotesk(
              size: 12,
              weight: 500,
              color: AppColors.textMute,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({required this.inputs});

  final TdeeInputs? inputs;

  @override
  Widget build(BuildContext context) {
    final data = inputs;
    if (data == null) {
      return ListView(
        padding: _stepPadding,
        children: [
          Text(
            'Es fehlen noch Angaben. Geh einen Schritt zurück und ergänze deine '
            'Körperdaten.',
            style: AppText.grotesk(size: 14, weight: 600, height: 1.4),
          ),
        ],
      );
    }

    final kcal = recommendedCalorieTarget(data);
    final macros = defaultMacrosFor(kcal);

    return ListView(
      padding: _stepPadding,
      children: [
        Text(
          'DEIN TAGESZIEL',
          style: AppText.overline(),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(kcal.round().toString(), style: AppText.anton(size: 64)),
              Text(
                ' kcal',
                style: AppText.grotesk(
                  size: 16,
                  weight: 600,
                  color: AppColors.textMute,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'EIWEISS',
                value: macros.proteinG.round().toString(),
                suffix: ' g',
                accent: AppColors.protein,
              ),
            ),
            const SizedBox(width: AppTheme.rowGap),
            Expanded(
              child: StatTile(
                label: 'KOHLENH.',
                value: macros.carbsG.round().toString(),
                suffix: ' g',
                accent: AppColors.carbs,
              ),
            ),
            const SizedBox(width: AppTheme.rowGap),
            Expanded(
              child: StatTile(
                label: 'FETT',
                value: macros.fatG.round().toString(),
                suffix: ' g',
                accent: AppColors.fat,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Vorgeschlagen aus deinen Angaben. Du kannst Ziel und Makros jederzeit '
          'unter Profil → Ziele anpassen.',
          style: AppText.grotesk(
            size: 13,
            weight: 500,
            color: AppColors.textMute,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: AppText.section(size: 14)),
  );
}

/// The sticky footer carrying the step's primary action.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

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
        label: label,
        icon: icon,
        radius: AppRadii.fab,
        onPressed: onPressed,
      ),
    );
  }
}
