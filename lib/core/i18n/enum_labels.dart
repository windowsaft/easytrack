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
