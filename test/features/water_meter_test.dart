// The water meter is a pure widget over an int level and a callback, so it can
// be driven directly — no database, no drift timers, no pump gymnastics. Its
// row-growth rule has regressed twice, so it is pinned here.

import 'package:easytrack/features/diary/widgets/water_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Every bar carries a ValueKey('water_bar_<i>'); counting them counts the
  /// bars, and 8 bars make one row.
  final bars = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('water_bar_'),
  );

  Future<int> pumpMeter(
    WidgetTester tester, {
    required int current,
    int goal = 2000,
    int cup = 250,
    ValueChanged<int>? onSet,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaterMeter(
            currentMl: current,
            goalMl: goal,
            cupMl: cup,
            onSet: onSet ?? (_) {},
          ),
        ),
      ),
    );
    return bars.evaluate().length;
  }

  group('row growth', () {
    testWidgets('an empty day shows a single row of eight cups', (
      tester,
    ) async {
      expect(await pumpMeter(tester, current: 0), 8);
    });

    testWidgets('completing a row reveals a fresh empty row to pour into', (
      tester,
    ) async {
      // Eight cups (2000 ml at 250) fills the first row, so a second, empty row
      // appears — that is where the next glass goes, now that the + button is
      // gone.
      expect(await pumpMeter(tester, current: 2000), 16);
    });

    testWidgets('a partly-filled row shows exactly one row', (tester) async {
      // Five cups: filled bars plus empties, still one row, no buffer yet.
      expect(await pumpMeter(tester, current: 1250), 8);
    });

    testWidgets('drinking into the second row keeps two rows', (tester) async {
      expect(await pumpMeter(tester, current: 2250), 16);
    });

    testWidgets('dropping back within the first row hides the second', (
      tester,
    ) async {
      expect(await pumpMeter(tester, current: 2250), 16);
      expect(await pumpMeter(tester, current: 1750), 8);
    });

    testWidgets('the row count ignores the goal, tracking only what is drunk', (
      tester,
    ) async {
      // A finer or coarser goal does not change the grid — the goal is the
      // reading, the cups are the pours.
      expect(await pumpMeter(tester, current: 0, goal: 1500), 8);
      expect(await pumpMeter(tester, current: 0, goal: 3000), 8);
    });
  });

  group('tapping', () {
    testWidgets('an empty bar sets the level up to it', (tester) async {
      int? set;
      await pumpMeter(tester, current: 0, onSet: (ml) => set = ml);

      await tester.tap(bars.at(2)); // third bar
      expect(set, 750);
    });

    testWidgets('the topmost filled bar empties down to just below it', (
      tester,
    ) async {
      int? set;
      // Four cups in; tapping the fourth (topmost filled) clears it to three.
      await pumpMeter(tester, current: 1000, onSet: (ml) => set = ml);

      await tester.tap(bars.at(3));
      expect(set, 750);
    });

    testWidgets('a custom cup size changes what each bar is worth', (
      tester,
    ) async {
      int? set;
      await pumpMeter(tester, current: 0, cup: 500, onSet: (ml) => set = ml);

      await tester.tap(bars.at(1)); // second bar, 500 ml each
      expect(set, 1000);
    });

    testWidgets('the empty buffer row is how you pour past a full row', (
      tester,
    ) async {
      int? set;
      // Exactly one full row (2000 ml); the second row is empty, and its first
      // bar (index 8) pours the ninth glass.
      await pumpMeter(tester, current: 2000, onSet: (ml) => set = ml);
      expect(bars.evaluate().length, 16);

      await tester.tap(bars.at(8));
      expect(set, 2250);
    });
  });
}
