// Renders the redesigned screens at phone dimensions against a real (in-memory)
// user database.
//
// The point is layout and wiring, not arithmetic: a RenderFlex overflow or a
// failed CustomPaint surfaces as a thrown exception during pump, and nothing
// else in the suite exercises these widgets. The surface is sized to a phone
// because the design is drawn for a 380px-wide frame — at the 800x600 test
// default, overflows that would show on the device simply do not happen.
//
// Two rules apply to every test here, both learned the hard way:
//
//  - Never `pumpAndSettle`. The loading state is a CircularProgressIndicator,
//    whose animation never settles, so it hangs until the 10-minute timeout.
//  - Never close the database from a widget test, and always unmount the tree
//    before the test ends. Drift schedules a zero-duration timer when its query
//    streams are cancelled; if the tree is still mounted when the test body
//    returns, that timer trips the "timer still pending" assertion, and calling
//    close() inside the fake-async zone never completes at all.

import 'package:easytrack/core/di/providers.dart';
import 'package:easytrack/core/nutrition/food_ref.dart';
import 'package:easytrack/core/nutrition/nutrients.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/core/ui/app_theme.dart';
import 'package:easytrack/core/ui/widgets/bold_controls.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/food/food_item.dart';
import 'package:easytrack/data/repositories/diary_repository.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:easytrack/domain/tdee.dart';
import 'package:easytrack/features/diary/diary_screen.dart';
import 'package:easytrack/features/diary/meal_detail_screen.dart';
import 'package:easytrack/features/profile/profile_edit_screen.dart';
import 'package:easytrack/features/profile/profile_screen.dart';
import 'package:easytrack/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late UserDatabase user;
  late DiaryRepository diary;
  late SettingsRepository settings;

  setUpAll(() => initializeDateFormatting('de'));

  setUp(() {
    user = UserDatabase.forTesting();
    settings = SettingsRepository(user);
    diary = DiaryRepository(user, settings);
  });

  Widget boot(Widget screen) => ProviderScope(
    overrides: [userDatabaseProvider.overrideWithValue(user)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: screen),
    ),
  );

  /// Bounded stand-in for pumpAndSettle. See the file comment.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Mounts a screen at phone dimensions and lets its streams deliver.
  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2340); // a common Android size
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(boot(screen));
    await settle(tester);
  }

  /// Unmounts the tree while the binding can still run drift's cleanup timer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  final oats = FoodItem(
    ref: const FoodRef(FoodSourceType.bls, 'C133000'),
    name: 'Hafer Flocken',
    nutrients: const Nutrients(
      kcal: 348,
      proteinG: 13.2,
      carbsG: 58.7,
      fatG: 7,
    ),
  );

  Future<void> logOats(double grams, MealType meal) => diary.addEntry(
    day: DayKey.today(),
    meal: meal,
    food: oats,
    amountG: grams,
  );

  group('diary', () {
    testWidgets('an empty day renders the whole dashboard', (tester) async {
      await show(tester, const DiaryScreen());

      expect(find.text('HEUTE'), findsOneWidget);
      // Nothing eaten, so the fallback 2000 kcal target is entirely available.
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('ÜBRIG'), findsOneWidget);
      expect(find.text('WASSER'), findsOneWidget);
      // All four meals sit in their empty state.
      expect(find.text('Zum Hinzufügen wischen oder tippen'), findsNWidgets(4));
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('a logged entry moves the gauge and the meal row', (
      tester,
    ) async {
      await logOats(100, MealType.breakfast);
      await show(tester, const DiaryScreen());

      // 2000 - 348 remaining, shown in the gauge.
      expect(find.text('1652'), findsOneWidget);
      // 348 appears twice: the "gegessen" stat and the breakfast row.
      expect(find.text('348'), findsNWidgets(2));
      expect(find.text('Hafer Flocken'), findsOneWidget);
      expect(find.text('Zum Hinzufügen wischen oder tippen'), findsNWidgets(3));
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('tapping a water bar fills up to it', (tester) async {
      await show(tester, const DiaryScreen());

      // The third of eight bars against a 2000 ml goal is 750 ml.
      await tester.tap(find.bySemanticsLabel('750 ml'));
      await settle(tester);

      expect(find.text('0,75'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('over budget reads as an excess, not a negative', (
      tester,
    ) async {
      await logOats(1000, MealType.dinner); // 3480 kcal against 2000
      await show(tester, const DiaryScreen());

      expect(find.text('ZU VIEL'), findsOneWidget);
      expect(find.text('1480'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('meal detail', () {
    testWidgets('lists the meal and its macro split', (tester) async {
      await logOats(100, MealType.breakfast);
      await show(tester, const MealDetailScreen(meal: MealType.breakfast));

      expect(find.text('FRÜHSTÜCK'), findsOneWidget);
      expect(find.text('1 EINTRAG'), findsOneWidget);
      expect(find.text('Hafer Flocken'), findsOneWidget);
      expect(find.text('MAHLZEIT GESAMT'), findsOneWidget);
      // Carbohydrate dominates oats by energy.
      expect(find.text('59 g'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('an empty meal says so rather than drawing a false chart', (
      tester,
    ) async {
      await show(tester, const MealDetailScreen(meal: MealType.dinner));

      expect(find.text('Noch nichts eingetragen'), findsOneWidget);
      expect(find.text('0 EINTRÄGE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('settings', () {
    testWidgets('renders every group', (tester) async {
      await show(tester, const SettingsScreen());

      expect(find.text('EINSTELLUNGEN'), findsOneWidget);
      expect(find.text('Sicherheitsfaktor'), findsOneWidget);
      expect(find.text('0,80'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('changing the safety factor persists', (tester) async {
      await show(tester, const SettingsScreen());

      await tester.tap(find.text('Sicherheitsfaktor'));
      await settle(tester);
      await tester.tap(find.text('0,90'));
      await settle(tester);

      // The row reads its value back through the profile stream, so seeing
      // 0,90 here is the full round trip through the database.
      expect(find.text('0,90'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('the activity toggle writes to the profile', (tester) async {
      await show(tester, const SettingsScreen());

      expect(tester.widget<BoldToggle>(find.byType(BoldToggle)).value, isTrue);

      await tester.tap(find.byType(BoldToggle));
      await settle(tester);

      // Re-read from the widget tree rather than the database: the toggle is
      // driven by the profile stream, so the flipped state is the write having
      // landed and come back.
      expect(tester.widget<BoldToggle>(find.byType(BoldToggle)).value, isFalse);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('profile', () {
    testWidgets('shows only real figures and distinct destinations', (
      tester,
    ) async {
      await show(tester, const ProfileScreen());

      expect(find.text('PROFIL'), findsOneWidget);
      expect(find.text('LOKAL · KEIN KONTO'), findsOneWidget);
      // Goal tiles are backed by the real target, not invented.
      expect(find.text('DEINE ZIELE'), findsOneWidget);
      expect(find.text('2.000'), findsOneWidget); // fallback kcal goal
      expect(find.text('0,80'), findsOneWidget); // default safety factor
      // The rows go to different places.
      expect(find.text('Körperdaten & Ziel'), findsOneWidget);
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Datenquellen & Lizenzen'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });

  group('profile edit (TDEE)', () {
    // The compute-and-persist path is covered end to end in
    // settings_repository_test; here the concern is the form wiring — that the
    // inputs reach the live preview, and that prefill does not crash.
    testWidgets('shows the computed target live as fields are filled', (
      tester,
    ) async {
      await show(tester, const ProfileEditScreen());

      // Before anything is entered the preview cannot compute.
      expect(find.text('—'), findsOneWidget);

      await tester.tap(find.text('Männlich'));
      await settle(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '30'); // Alter
      await tester.enterText(fields.at(1), '180'); // Größe
      await tester.enterText(fields.at(2), '80'); // Gewicht
      await settle(tester);

      // Moderate + maintain: 1780 BMR * 1.55 = 2759.
      expect(find.text('2.759'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('prefills from an existing profile without crashing', (
      tester,
    ) async {
      // Seed a profile first: this is the path that used to throw a
      // setState-during-build when the form filled its controllers.
      await settings.saveProfileAndTarget(
        sex: Sex.female,
        birthDate: DateTime(1994, 3, 1),
        heightCm: 168,
        weightKg: 62,
        activity: ActivityLevel.light,
        goal: WeightGoal.maintain,
        rateKgPerWeek: 0,
      );

      await show(tester, const ProfileEditScreen());

      expect(tester.takeException(), isNull);
      // The stored weight is back in its field, and the sex chip is selected.
      expect(find.text('62'), findsOneWidget);
      expect(find.text('168'), findsOneWidget);

      await unmount(tester);
    });
  });
}
