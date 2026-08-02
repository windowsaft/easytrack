// Renders the Verlauf screen at phone dimensions against a real (in-memory)
// user database. Same rules as diary_screen_test.dart: never pumpAndSettle,
// never close the database, always unmount before returning.

import 'package:easytrack/core/di/providers.dart';
import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/core/time/week_start.dart';
import 'package:easytrack/core/ui/app_theme.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/repositories/diary_repository.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:easytrack/features/history/history_screen.dart';
import 'package:easytrack/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late UserDatabase user;
  late DiaryRepository diary;

  setUp(() {
    // Pin the week convention: it otherwise follows the language, which would
    // make the range the back chevron lands on depend on the test environment.
    SharedPreferences.setMockInitialValues({
      'app_locale_v1': 'de',
      'week_start_v1': 'monday',
    });
    user = UserDatabase.forTesting();
    diary = DiaryRepository(user, SettingsRepository(user));
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

  final oats = FoodItem(
    ref: const FoodRef(FoodSourceType.bls, 'C133000'),
    name: 'Hafer',
    nutrients: const Nutrients(
      kcal: 348,
      proteinG: 13.2,
      carbsG: 58.7,
      fatG: 7,
    ),
  );

  testWidgets('an empty history shows the empty state', (tester) async {
    await show(tester, const HistoryScreen());

    expect(find.text('VERLAUF'), findsOneWidget);
    expect(find.text('Noch keine Auswertung'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('logged days render the analytics without overflow', (
    tester,
  ) async {
    final today = DayKey.today();
    for (final day in [today.addDays(-2), today.addDays(-1), today]) {
      await diary.addEntry(
        day: day,
        meal: MealType.breakfast,
        food: oats,
        amountG: 200,
      );
      await diary.addWater(day: day, amountMl: 1500);
    }

    await show(tester, const HistoryScreen());

    expect(find.text('KALORIEN'), findsOneWidget);
    expect(find.text('ÜBERBLICK'), findsOneWidget);
    expect(find.text('ZIEL-TREUE'), findsOneWidget);
    expect(find.text('MAKRO-SPLIT Ø'), findsOneWidget);
    expect(find.text('Gewicht verwalten'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('stepping back reaches a day the rolling window cannot', (
    tester,
  ) async {
    // The start of the previous calendar week is always at least 7 days ago,
    // whatever today's weekday — so it can never fall inside "last 7 days", and
    // only the back chevron can bring it into view.
    final today = DayKey.today();
    final lastWeek = WeekStart.monday.startOfWeek(today).addDays(-7);
    await diary.addEntry(
      day: lastWeek,
      meal: MealType.breakfast,
      food: oats,
      amountG: 200,
    );

    await show(tester, const HistoryScreen());

    expect(find.text('LETZTE 7 TAGE'), findsOneWidget);
    expect(find.text('Noch keine Auswertung'), findsOneWidget);

    await tester.tap(find.byTooltip('Vorheriger Zeitraum'));
    await settle(tester);

    expect(find.text('LETZTE 7 TAGE'), findsNothing);
    expect(find.text('KALORIEN'), findsOneWidget);

    // And forward returns to the rolling window it started from.
    await tester.tap(find.byTooltip('Nächster Zeitraum'));
    await settle(tester);

    expect(find.text('LETZTE 7 TAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });
}
