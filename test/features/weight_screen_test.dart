// Renders the weight screen at phone dimensions against a real (in-memory)
// user database. Same rules as diary_screen_test.dart: never pumpAndSettle,
// never close the database, always unmount before returning.

import 'package:easytrack/core/di/providers.dart';
import 'package:easytrack/core/time/day_key.dart';
import 'package:easytrack/core/ui/app_theme.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/data/repositories/settings_repository.dart';
import 'package:easytrack/features/weight/weight_screen.dart';
import 'package:easytrack/l10n/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late UserDatabase user;
  late SettingsRepository settings;

  setUpAll(() => initializeDateFormatting('de'));

  setUp(() {
    user = UserDatabase.forTesting();
    settings = SettingsRepository(user);
  });

  Widget boot(Widget screen) => ProviderScope(
    overrides: [userDatabaseProvider.overrideWithValue(user)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: screen,
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

  group('weight screen', () {
    testWidgets('an empty log shows the empty state and a log action', (
      tester,
    ) async {
      await show(tester, const WeightScreen());

      expect(find.text('GEWICHT'), findsOneWidget);
      expect(find.text('Noch kein Gewicht erfasst'), findsOneWidget);
      expect(find.text('GEWICHT EINTRAGEN'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });

    testWidgets('a few readings render the summary, chart and entries', (
      tester,
    ) async {
      final today = DayKey.today();
      await settings.recordWeightOn(day: today.addDays(-2), kg: 81);
      await settings.recordWeightOn(day: today.addDays(-1), kg: 80.4);
      await settings.recordWeightOn(day: today, kg: 79.8);

      await show(tester, const WeightScreen());

      expect(find.text('AKTUELL'), findsOneWidget);
      // Latest weight, German decimal comma.
      expect(find.text('79,8'), findsOneWidget);
      expect(find.text('EINTRÄGE'), findsOneWidget);
      // Two points clear the threshold, so the trend chart draws.
      expect(find.byType(LineChart), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmount(tester);
    });
  });
}
