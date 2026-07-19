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
    testWidgets('an empty day shows exactly the goal in one row', (
      tester,
    ) async {
      // 2000 ml goal at 250 ml a cup is eight bars — one full row, no more.
      expect(await pumpMeter(tester, current: 0), 8);
    });

    testWidgets('hitting the goal exactly does not spawn an empty row', (
      tester,
    ) async {
      // The bug: completing the first row used to force a second, empty one.
      expect(await pumpMeter(tester, current: 2000), 8);
    });

    testWidgets('drinking past the goal opens a second row', (tester) async {
      // One glass beyond the goal needs a ninth bar, hence a second row.
      expect(await pumpMeter(tester, current: 2250), 16);
    });

    testWidgets('dropping back below a full row hides the second row', (
      tester,
    ) async {
      expect(await pumpMeter(tester, current: 2250), 16);
      expect(await pumpMeter(tester, current: 1750), 8);
    });

    testWidgets('a goal finer than a row still fills within one row', (
      tester,
    ) async {
      // 1500 ml at 250 is six cups: still one row of eight, with room to spare.
      expect(await pumpMeter(tester, current: 0, goal: 1500), 8);
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

    testWidgets('the add button logs a glass past a full goal', (tester) async {
      int? set;
      // Exactly at the goal: every bar is full, so only the add button can push
      // the level higher.
      await pumpMeter(tester, current: 2000, onSet: (ml) => set = ml);
      expect(bars.evaluate().length, 8); // still one tidy row

      await tester.tap(find.byKey(const ValueKey('water_add_cup')));
      expect(set, 2250);
    });
  });
}
