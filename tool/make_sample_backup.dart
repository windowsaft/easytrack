// Generates a sample EasyTrack backup zip for testing the import flow.
//
// Not part of the test suite (it lives outside test/). Run it explicitly:
//   "C:/dev/flutter/bin/flutter.bat" test tool/make_sample_backup.dart
// It seeds a fresh database with a profile, a target and a week of diary /
// water / activity / weight data dated relative to today, then runs the real
// BackupService.exportToZip and copies the result to
//   build/easytrack-sample-backup.zip
// Push that onto the phone and import it via Einstellungen → DATENSICHERUNG or
// the onboarding restore card.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/data/backup/backup_service.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/repositories/recipe_repository.dart';
import 'package:easytrack/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('write sample backup to build/', () async {
    final db = UserDatabase.forTesting();
    addTearDown(db.close);

    await _seed(db);

    // Guard against silently shipping an empty section: confirm the data the
    // import screens read is actually there before we bundle it.
    final recipes = await RecipeRepository(db).watchRecipes().first;
    expect(recipes, hasLength(1), reason: 'recipe must be seeded');
    expect(recipes.single.ingredients, hasLength(5));

    final tmp = await Directory.systemTemp.createTemp('et-sample');
    addTearDown(() => tmp.delete(recursive: true));

    final service = BackupService(
      db: db,
      documentsDirectory: () async => tmp,
      temporaryDirectory: () async => tmp,
      appVersion: '1.0.0+1',
      schemaVersion: db.schemaVersion,
    );

    final zip = await service.exportToZip();
    final out = File(p.join('build', 'easytrack-sample-backup.zip'));
    await out.parent.create(recursive: true);
    await zip.copy(out.path);

    // ignore: avoid_print
    print('Sample backup written to ${out.absolute.path} '
        '(${await out.length()} bytes)');
    expect(out.existsSync(), isTrue);
  });
}

Future<void> _seed(UserDatabase db) async {
  final today = DayKey.today();

  // --- Profile + target ---------------------------------------------------
  await db
      .into(db.userProfile)
      .insert(
        UserProfileCompanion.insert(
          birthDate: Value(DateTime(1991, 5, 14)),
          sex: const Value('male'),
          heightCm: const Value(181),
          activityLevel: const Value('moderate'),
          goal: const Value('lose'),
          rateKgPerWeek: const Value(0.5),
          waterCupMl: const Value(250),
        ),
      );
  await db
      .into(db.targets)
      .insert(
        TargetsCompanion.insert(
          effectiveFrom: today.addDays(-30),
          kcal: 2100,
          proteinG: const Value(150),
          carbsG: const Value(210),
          fatG: const Value(70),
          waterMl: const Value(2500),
          isAuto: const Value(false),
        ),
      );

  // --- A custom food (also a favourite) -----------------------------------
  await db
      .into(db.customFoods)
      .insert(
        CustomFoodsCompanion.insert(
          name: 'Mein Protein-Shake',
          brand: const Value('Eigenmarke'),
          searchText: const Value('mein protein-shake eigenmarke'),
          kcal: 42,
          proteinG: 8,
          carbsG: 1.5,
          fatG: 0.5,
          unit: const Value('ml'),
          isFavorite: const Value(true),
          defaultServingG: const Value(300),
          defaultServingLabel: const Value('Shaker'),
        ),
      );

  // --- A recipe (favourite, with a cooked-weight yield + portion size) ----
  // Ingredient nutrients are absolute for each ingredient's weight, exactly as
  // the recipe editor snapshots them.
  await RecipeRepository(db).createRecipe(
    name: 'Chili con Carne',
    notes: 'Großer Topf für die Woche — hält sich gut.',
    cookedWeightG: 1300, // some water cooks off the 1450 g raw batch
    portionSizeG: 350,
    isFavorite: true,
    components: const [
      RecipeComponent(
        ref: FoodRef(FoodSourceType.bls, 'rinderhack'),
        name: 'Rinderhackfleisch',
        amountG: 400,
        nutrients: Nutrients(kcal: 1000, proteinG: 76, carbsG: 0, fatG: 80),
      ),
      RecipeComponent(
        ref: FoodRef(FoodSourceType.bls, 'kidneybohnen'),
        name: 'Kidneybohnen',
        amountG: 400,
        nutrients: Nutrients(
          kcal: 340,
          proteinG: 26.8,
          carbsG: 48,
          fatG: 2,
          fiberG: 24,
        ),
      ),
      RecipeComponent(
        ref: FoodRef(FoodSourceType.bls, 'tomaten'),
        name: 'Gehackte Tomaten',
        amountG: 400,
        nutrients: Nutrients(kcal: 80, proteinG: 4.8, carbsG: 14, fatG: 0.8),
      ),
      RecipeComponent(
        ref: FoodRef(FoodSourceType.bls, 'mais'),
        name: 'Mais',
        amountG: 150,
        nutrients: Nutrients(kcal: 129, proteinG: 4.8, carbsG: 28.5, fatG: 1.8),
      ),
      RecipeComponent(
        ref: FoodRef(FoodSourceType.bls, 'zwiebel'),
        name: 'Zwiebel',
        amountG: 100,
        nutrients: Nutrients(kcal: 40, proteinG: 1.1, carbsG: 9, fatG: 0.1),
      ),
    ],
  );

  // --- Diary: today, richly; the previous few days, lightly ---------------
  Future<void> log(
    DayKey day,
    String meal,
    String name,
    double amount, {
    required double kcal,
    required double protein,
    required double carbs,
    required double fat,
    String unit = 'g',
    String? brand,
    String? servingLabel,
    double? servingCount,
    double? fiber,
    double? sugar,
  }) {
    return db
        .into(db.diaryEntries)
        .insert(
          DiaryEntriesCompanion.insert(
            loggedOn: day,
            meal: meal,
            sourceType: 'bls',
            sourceId: 'S${name.hashCode.abs()}',
            nameSnapshot: name,
            brandSnapshot: Value(brand),
            amountG: amount,
            unit: Value(unit),
            servingLabel: Value(servingLabel),
            servingCount: Value(servingCount),
            kcal: kcal,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: Value(fiber),
            sugarG: Value(sugar),
          ),
        );
  }

  // Today.
  await log(today, 'breakfast', 'Haferflocken', 60,
      kcal: 220, protein: 8, carbs: 36, fat: 4, fiber: 6);
  await log(today, 'breakfast', 'Vollmilch 3,5%', 200,
      kcal: 128, protein: 6.8, carbs: 9.6, fat: 7, unit: 'ml',
      servingLabel: 'Glas', servingCount: 1);
  await log(today, 'breakfast', 'Banane', 120,
      kcal: 107, protein: 1.3, carbs: 25, fat: 0.4, sugar: 15);
  await log(today, 'lunch', 'Hähnchenbrustfilet', 150,
      kcal: 165, protein: 46, carbs: 0, fat: 2);
  await log(today, 'lunch', 'Basmatireis, gekocht', 200,
      kcal: 260, protein: 5, carbs: 56, fat: 0.6);
  await log(today, 'lunch', 'Brokkoli, gedünstet', 150,
      kcal: 51, protein: 4.2, carbs: 5, fat: 0.6, fiber: 4.5);
  await log(today, 'snacks', 'Kaffee, schwarz', 250,
      kcal: 5, protein: 0.5, carbs: 0, fat: 0, unit: 'ml',
      servingLabel: 'Tasse', servingCount: 1);
  await log(today, 'dinner', 'Vollkornbrot', 80,
      kcal: 190, protein: 7, carbs: 33, fat: 1.6, fiber: 6.4);
  await log(today, 'dinner', 'Gouda', 40,
      kcal: 145, protein: 10, carbs: 0, fat: 12, brand: 'Käserei');

  // Yesterday.
  await log(today.addDays(-1), 'breakfast', 'Joghurt natur', 250,
      kcal: 158, protein: 8.8, carbs: 12, fat: 8, unit: 'ml');
  await log(today.addDays(-1), 'lunch', 'Spaghetti Bolognese', 400,
      kcal: 560, protein: 26, carbs: 72, fat: 18);
  await log(today.addDays(-1), 'dinner', 'Gemischter Salat', 300,
      kcal: 180, protein: 6, carbs: 12, fat: 11, fiber: 5);

  // Two days ago.
  await log(today.addDays(-2), 'breakfast', 'Rührei (2 Eier)', 120,
      kcal: 196, protein: 14, carbs: 1, fat: 15);
  await log(today.addDays(-2), 'lunch', 'Linseneintopf', 450,
      kcal: 405, protein: 23, carbs: 60, fat: 6, fiber: 14);

  // --- Water: a few glasses today and yesterday ---------------------------
  for (final day in [today, today.addDays(-1)]) {
    for (var i = 0; i < 5; i++) {
      await db
          .into(db.waterLog)
          .insert(WaterLogCompanion.insert(loggedOn: day, amountMl: 250));
    }
  }

  // --- Activity today -----------------------------------------------------
  await db
      .into(db.activityEntries)
      .insert(
        ActivityEntriesCompanion.insert(
          loggedOn: today,
          label: 'Joggen',
          durationMin: const Value(35),
          kcalBurnedRaw: 380,
          safetyFactor: const Value(0.8),
        ),
      );

  // --- Weight trend: one per day for a week, drifting down ----------------
  var kg = 79.4;
  for (var d = 6; d >= 0; d--) {
    await db
        .into(db.weightLog)
        .insert(
          WeightLogCompanion.insert(
            measuredOn: today.addDays(-d),
            weightKg: double.parse(kg.toStringAsFixed(1)),
          ),
        );
    kg -= 0.15;
  }
}
