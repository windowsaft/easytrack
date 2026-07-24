import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/nutrition/food_ref.dart';
import '../../data/food/barcode_resolver.dart';
import '../../data/food/food_item.dart';
import '../../l10n/app_localizations.dart';
import '../diary/widgets/portion_sheet.dart';
import '../search/food_forms.dart';
import 'barcode_scanner_screen.dart';

/// Opens the camera scanner and returns the scanned barcode, or null if the
/// user backed out.
Future<String?> scanBarcode(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));

/// Turns a scanned barcode into a loggable food.
///
/// Resolves it through the source chain; on a miss, offers to create the product
/// manually (prefilled with the barcode) so the next scan finds it. Returns null
/// if nothing was found and the user declined to create it.
Future<FoodItem?> resolveScannedBarcode(
  BuildContext context,
  WidgetRef ref,
  String barcode,
) async {
  final outcome = await ref.read(barcodeResolverProvider).resolve(barcode);
  if (!context.mounted) return null;

  switch (outcome) {
    case BarcodeFound(:final item):
      return item;
    case BarcodeUnknown(:final barcode):
      final draft = await showCreateFoodSheet(context, initialBarcode: barcode);
      if (draft == null || !context.mounted) return null;
      final food = await ref
          .read(customFoodRepositoryProvider)
          .create(
            name: draft.name,
            brand: draft.brand,
            nutrients: draft.nutrients,
            servingG: draft.servingG,
            servingLabel: draft.servingUnit,
            measure: draft.measure,
            barcode: draft.barcode,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).searchCreatedFood(food.name),
            ),
          ),
        );
      }
      return food;
  }
}

/// The full "scan a product and log it" flow for a meal: scan → resolve (or
/// create) → pick a portion → write the diary entry. Shared by the meal detail
/// screen and the search screen so the logic lives in one place.
Future<void> scanBarcodeIntoMeal(
  BuildContext context,
  WidgetRef ref,
  MealType meal,
) async {
  final barcode = await scanBarcode(context);
  if (barcode == null || !context.mounted) return;

  final food = await resolveScannedBarcode(context, ref, barcode);
  if (food == null || !context.mounted) return;

  final portion = await showPortionSheet(context, food, allowFavorite: true);
  if (portion == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  await ref
      .read(diaryRepositoryProvider)
      .addEntry(
        day: ref.read(selectedDayProvider),
        meal: meal,
        food: food,
        amountG: portion.grams,
        servingLabel: portion.label,
        servingCount: portion.count,
      );
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.searchAddedFood(food.name))),
  );
}
