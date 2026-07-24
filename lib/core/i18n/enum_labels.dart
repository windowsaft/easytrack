import '../../data/pack/off_region.dart';
import '../../domain/tdee.dart';
import '../../l10n/app_localizations.dart';
import '../nutrition/food_ref.dart';

/// Localized display names for domain enums.
///
/// The enums themselves keep their stable `wireName` for persistence; their
/// user-facing labels live here so they translate with the rest of the UI
/// instead of being pinned to German in the model layer. Call as
/// `meal.label(AppLocalizations.of(context))`.
extension MealTypeLabel on MealType {
  String label(AppLocalizations l10n) => switch (this) {
    MealType.breakfast => l10n.mealBreakfast,
    MealType.lunch => l10n.mealLunch,
    MealType.dinner => l10n.mealDinner,
    MealType.snacks => l10n.mealSnacks,
  };
}

/// The data-source label shown on the attribution chip in search results and
/// the portion sheet. Data licences require this to be shown.
extension FoodSourceTypeLabel on FoodSourceType {
  String label(AppLocalizations l10n) => switch (this) {
    FoodSourceType.custom => l10n.sourceCustom,
    FoodSourceType.bls => l10n.sourceBls,
    FoodSourceType.offLocal || FoodSourceType.offOnline => l10n.sourceOff,
    FoodSourceType.usda => l10n.sourceUsda,
    FoodSourceType.recipe => l10n.sourceRecipe,
  };
}

/// Localized labels for the calorie-calculator enums (Mifflin-St Jeor inputs).
extension SexLabel on Sex {
  String label(AppLocalizations l10n) => switch (this) {
    Sex.male => l10n.sexMale,
    Sex.female => l10n.sexFemale,
  };
}

extension ActivityLevelLabel on ActivityLevel {
  String label(AppLocalizations l10n) => switch (this) {
    ActivityLevel.sedentary => l10n.activityLevelSedentary,
    ActivityLevel.light => l10n.activityLevelLight,
    ActivityLevel.moderate => l10n.activityLevelModerate,
    ActivityLevel.active => l10n.activityLevelActive,
    ActivityLevel.veryActive => l10n.activityLevelVeryActive,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    ActivityLevel.sedentary => l10n.activityLevelSedentaryHint,
    ActivityLevel.light => l10n.activityLevelLightHint,
    ActivityLevel.moderate => l10n.activityLevelModerateHint,
    ActivityLevel.active => l10n.activityLevelActiveHint,
    ActivityLevel.veryActive => l10n.activityLevelVeryActiveHint,
  };
}

extension WeightGoalLabel on WeightGoal {
  String label(AppLocalizations l10n) => switch (this) {
    WeightGoal.lose => l10n.goalLose,
    WeightGoal.maintain => l10n.goalMaintain,
    WeightGoal.gain => l10n.goalGain,
  };
}

/// Localized name and sub-label for the downloadable-pack region.
extension OffRegionLabel on OffRegion {
  String label(AppLocalizations l10n) => switch (this) {
    OffRegion.de => l10n.regionDe,
    OffRegion.dach => l10n.regionDach,
    OffRegion.world => l10n.regionWorld,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    OffRegion.de => l10n.regionDeHint,
    OffRegion.dach => l10n.regionDachHint,
    OffRegion.world => l10n.regionWorldHint,
  };
}
