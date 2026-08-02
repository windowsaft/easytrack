// The week-start setting has to reach Flutter's own calendar grids, which read
// it from MaterialLocalizations rather than from any argument we pass. These
// tests pin the wiring: the delegate wins over the Global one it wraps, the
// index it reports is the Material convention (0 = Sunday), and the strings
// around it are still the real translation.

import 'package:easytrack/core/i18n/week_start_localizations.dart';
import 'package:easytrack/core/time/week_start.dart';
import 'package:easytrack/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps a MaterialApp wired the way the real app is, and hands back the
  /// MaterialLocalizations the widgets below it would resolve.
  Future<MaterialLocalizations> resolve(
    WidgetTester tester, {
    required Locale locale,
    required WeekStart weekStart,
  }) async {
    late MaterialLocalizations found;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          WeekStartMaterialLocalizationsDelegate(weekStart),
          ...AppLocalizations.localizationsDelegates,
        ],
        home: Builder(
          builder: (context) {
            found = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return found;
  }

  testWidgets('the wrapper beats the global delegate in both languages', (
    tester,
  ) async {
    for (final locale in [const Locale('en'), const Locale('de')]) {
      final sunday = await resolve(
        tester,
        locale: locale,
        weekStart: WeekStart.sunday,
      );
      // 0 is Sunday: narrowWeekdays[0] is the Sunday column.
      expect(
        sunday.firstDayOfWeekIndex,
        0,
        reason: 'Sunday should win in $locale',
      );

      final monday = await resolve(
        tester,
        locale: locale,
        weekStart: WeekStart.monday,
      );
      expect(
        monday.firstDayOfWeekIndex,
        1,
        reason: 'Monday should win in $locale',
      );
    }
  });

  testWidgets('everything other than the week start is the real translation', (
    tester,
  ) async {
    final german = await resolve(
      tester,
      locale: const Locale('de'),
      weekStart: WeekStart.sunday,
    );
    expect(german.okButtonLabel, 'OK');
    expect(german.cancelButtonLabel, 'Abbrechen');
    expect(german.formatMonthYear(DateTime(2026, 8, 5)), 'August 2026');
    expect(german.narrowWeekdays.first, 'S'); // Sonntag

    final english = await resolve(
      tester,
      locale: const Locale('en'),
      weekStart: WeekStart.monday,
    );
    expect(english.cancelButtonLabel, 'Cancel');
    expect(english.formatMonthYear(DateTime(2026, 8, 5)), 'August 2026');
  });

  testWidgets('changing the setting reloads the localizations', (tester) async {
    final before = await resolve(
      tester,
      locale: const Locale('de'),
      weekStart: WeekStart.monday,
    );
    expect(before.firstDayOfWeekIndex, 1);

    // Same tree, new delegate: shouldReload has to notice, or the pickers keep
    // the old grid until the app restarts.
    final after = await resolve(
      tester,
      locale: const Locale('de'),
      weekStart: WeekStart.sunday,
    );
    expect(after.firstDayOfWeekIndex, 0);
  });

  testWidgets('the calendar grid starts on the chosen day', (tester) async {
    Future<String> firstColumn(WeekStart weekStart) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            WeekStartMaterialLocalizationsDelegate(weekStart),
            ...AppLocalizations.localizationsDelegates,
          ],
          home: Scaffold(
            body: CalendarDatePicker(
              initialDate: DateTime(2026, 8, 5),
              firstDate: DateTime(2020),
              lastDate: DateTime(2026, 12, 31),
              onDateChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The weekday headers are the first single-letter labels in the grid.
      final headers = tester.widgetList<Text>(find.byType(Text)).where(
        (text) => (text.data ?? '').length <= 2 && (text.data ?? '').isNotEmpty,
      );
      return headers.first.data!;
    }

    expect(await firstColumn(WeekStart.monday), 'M'); // Montag
    expect(await firstColumn(WeekStart.sunday), 'S'); // Sonntag
  });
}
