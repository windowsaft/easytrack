// Renders the recipe screens at phone dimensions against a real (in-memory)
// user database. Follows the same rules as diary_screen_test.dart: never
// pumpAndSettle, never close the database, always unmount before returning.

import 'package:easytrack/core/di/providers.dart';
import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/ui/app_theme.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/repositories/recipe_repository.dart';
import 'package:easytrack/domain/recipe.dart';
import 'package:easytrack/features/recipes/recipe_edit_screen.dart';
import 'package:easytrack/features/recipes/recipes_screen.dart';
import 'package:easytrack/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase user;
  late RecipeRepository recipes;

  setUp(() {
    user = UserDatabase.forTesting();
    recipes = RecipeRepository(user);
  });

  Widget boot(Widget screen) => ProviderScope(
    overrides: [userDatabaseProvider.overrideWithValue(user)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: screen),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(boot(screen));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  RecipeComponent component(String name, double g, double kcal) =>
      RecipeComponent(
        ref: FoodRef(FoodSourceType.bls, name),
        name: name,
        amountG: g,
        nutrients: Nutrients(kcal: kcal, proteinG: 0, carbsG: 0, fatG: 0),
      );

  group('recipes list', () {
    testWidgets('an empty book shows the empty state and a create action', (
      tester,
    ) async {
      await show(tester, const RecipesScreen());

      expect(find.text('REZEPTE'), findsOneWidget);
      expect(find.text('Noch keine Rezepte'), findsOneWidget);
      expect(find.text('Erstes Rezept anlegen'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('a saved recipe shows its name and per-100 g energy', (
      tester,
    ) async {
      await recipes.createRecipe(
        name: 'Chili con Carne',
        components: [
          component('Hackfleisch', 500, 1050),
          component('Kidneybohnen', 400, 380),
          component('Tomaten passiert', 500, 175),
        ],
      );

      await show(tester, const RecipesScreen());

      expect(find.text('Chili con Carne'), findsOneWidget);
      // 1605 kcal over the 1400 g raw batch → 115 kcal / 100 g (114.64 rounded).
      expect(find.textContaining('3 Zutaten'), findsOneWidget);
      expect(find.textContaining('115 kcal / 100 g'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('recipe editor', () {
    testWidgets('a new recipe renders the empty builder', (tester) async {
      await show(tester, const RecipeEditScreen());

      expect(find.text('NEUES REZEPT'), findsOneWidget);
      expect(find.text('ZUTATEN'), findsOneWidget);
      expect(find.text('Noch keine Zutaten'), findsOneWidget);
      expect(find.text('Zutat hinzufügen'), findsOneWidget);
      expect(find.text('SPEICHERN'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });
}
