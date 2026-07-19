import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/nutrition/food_ref.dart';
import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/app_bottom_nav.dart';
import '../activity/add_activity_screen.dart';
import '../diary/diary_screen.dart';
import '../diary/meal_detail_screen.dart';
import '../diary/widgets/meal_row.dart';
import '../profile/profile_screen.dart';

/// Bottom-navigation shell. The diary is the landing screen because logging is
/// the action the user opens the app to perform.
///
/// The centre button is not a tab: it drops straight into adding food to
/// whichever meal the time of day implies, which is the design's whole premise
/// for raising it above the bar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DiaryScreen(),
          _Placeholder(
            title: 'Rezepte',
            icon: Icons.menu_book,
            note: 'Rezepte mit Portionsrechnung folgen in Phase 10.',
          ),
          _Placeholder(
            title: 'Verlauf',
            icon: Icons.insights,
            note: 'Auswertungen folgen, sobald mehr Tage erfasst sind.',
          ),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onSelect: (i) => setState(() => _index = i),
        onAdd: _quickAdd,
      ),
    );
  }

  /// Asks what to log — a meal or an activity — before diving in.
  ///
  /// The centre button used to jump straight into the meal the clock suggested,
  /// which was wrong as often as it was right and gave no way to log activity.
  /// The chooser costs one tap and removes both problems; the time-of-day guess
  /// survives only as the pre-highlighted meal.
  Future<void> _quickAdd() async {
    // Move to the diary first: returning from the add flow to another tab would
    // leave the user somewhere they did not navigate to.
    setState(() => _index = 0);
    ref.read(selectedDayProvider.notifier).goToToday();

    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      builder: (_) => _AddSheet(suggested: mealForTimeOfDay(TimeOfDay.now())),
    );
    if (choice == null || !mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => switch (choice) {
          _AddMeal(:final meal) => MealDetailScreen(
            meal: meal,
            openSearch: true,
          ),
          _AddActivity() => const AddActivityScreen(),
        },
      ),
    );
  }
}

/// What the add-sheet returns.
sealed class _AddChoice {
  const _AddChoice();
}

class _AddMeal extends _AddChoice {
  const _AddMeal(this.meal);
  final MealType meal;
}

class _AddActivity extends _AddChoice {
  const _AddActivity();
}

/// The chooser shown by the centre nav button: the four meals plus activity.
class _AddSheet extends StatelessWidget {
  const _AddSheet({required this.suggested});

  /// Pre-highlighted so the time-of-day guess still saves a moment.
  final MealType suggested;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.screenPadding,
          20,
          AppTheme.screenPadding,
          12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EINTRAGEN', style: AppText.section(size: 18)),
            const SizedBox(height: 14),
            for (final meal in MealType.values) ...[
              _AddOption(
                icon: mealIcons[meal] ?? Icons.restaurant,
                label: meal.displayLabel,
                highlight: meal == suggested,
                onTap: () => Navigator.of(context).pop(_AddMeal(meal)),
              ),
              const SizedBox(height: AppTheme.rowGap),
            ],
            const SizedBox(height: 6),
            _AddOption(
              icon: Icons.local_fire_department,
              iconColor: AppColors.coral,
              label: 'Aktivität',
              onTap: () => Navigator.of(context).pop(const _AddActivity()),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = AppColors.lime,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight ? AppColors.selectedRow : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: highlight
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.lime, width: 3),
                  ),
                )
              : null,
          padding: EdgeInsets.fromLTRB(highlight ? 11 : 14, 14, 14, 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: AppText.grotesk(size: 15, weight: 600),
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

/// Which meal a time of day belongs to.
///
/// The boundaries are generous rather than precise — the point is to guess
/// right often enough that the user rarely has to correct it, and the meal can
/// always be changed on the next screen.
MealType mealForTimeOfDay(TimeOfDay now) => switch (now.hour) {
  >= 5 && < 11 => MealType.breakfast,
  >= 11 && < 15 => MealType.lunch,
  >= 17 && < 22 => MealType.dinner,
  _ => MealType.snacks,
};

/// Stand-in until each feature lands in its own phase.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.icon,
    required this.note,
  });

  final String title;
  final IconData icon;
  final String note;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.chevron),
              const SizedBox(height: 14),
              Text(title.toUpperCase(), style: AppText.section(size: 20)),
              const SizedBox(height: 6),
              Text(
                note,
                textAlign: TextAlign.center,
                style: AppText.grotesk(size: 13, color: AppColors.textMute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
