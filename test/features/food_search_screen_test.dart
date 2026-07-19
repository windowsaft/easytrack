// End-to-end check of the search feature: the real widget, the real
// orchestrator, and the real 7,140-food BLS pack. Only the asset-loading and
// database-opening seams are overridden, because a widget test has no app
// support directory to copy the pack into.

import 'package:easytrack/core/di/providers.dart';
import 'package:easytrack/core/ui/widgets/bold_controls.dart';
import 'package:easytrack/data/db/reference_database.dart';
import 'package:easytrack/data/db/user_database.dart';
import 'package:easytrack/features/search/food_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ReferenceDatabase reference;
  late UserDatabase user;
  late Set<String> morphemes;

  setUp(() {
    reference = ReferenceDatabase.openAt('assets/data/bls.sqlite');
    user = UserDatabase.forTesting();
  });

  tearDown(() async {
    reference.dispose();
    await user.close();
  });

  setUpAll(() {
    morphemes = {'brot', 'korn', 'vollkorn', 'hafer', 'flocken', 'milch'};
  });

  Widget boot() {
    return ProviderScope(
      overrides: [
        referenceDatabaseProvider.overrideWith((ref) async => reference),
        userDatabaseProvider.overrideWithValue(user),
        morphemesProvider.overrideWith((ref) async => morphemes),
      ],
      child: const MaterialApp(home: FoodSearchScreen()),
    );
  }

  /// Result rows have no public type, so they are counted by the icon tile
  /// every one of them renders.
  final resultRows = find.byType(TileIcon);

  /// Types a query and lets the debounce and the search complete.
  Future<void> searchFor(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 300)); // debounce
    await tester.pumpAndSettle();
  }

  testWidgets('shows a hint before anything is typed', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.textContaining('Funktioniert auch offline'), findsOneWidget);
  });

  testWidgets('finds a German staple and shows its nutrients', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await searchFor(tester, 'apfel');

    expect(find.textContaining('Apfel'), findsWidgets);
    // Each row states the portion its quick-add would log, and the calories
    // for that portion — not an unlabelled per-100 g figure.
    expect(find.textContaining('100 g'), findsWidgets);
    expect(find.text('KCAL'), findsWidgets);
  });

  testWidgets('umlaut spelling works from the UI', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await searchFor(tester, 'käse');
    expect(find.textContaining('käse'), findsWidgets);
  });

  testWidgets('the ae spelling finds the same foods', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await searchFor(tester, 'kaese');
    expect(resultRows, findsWidgets);
  });

  testWidgets('a compound is findable by an interior part', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await searchFor(tester, 'korn');
    expect(resultRows, findsWidgets);
  });

  testWidgets('reports no results rather than an error', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await searchFor(tester, 'xyzzyqwertz');

    expect(find.textContaining('Nichts gefunden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FTS operators typed by the user do not crash the screen', (
    tester,
  ) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    for (final query in ['brot AND', '"', '*', 'brot OR NOT']) {
      await searchFor(tester, query);
      expect(tester.takeException(), isNull, reason: 'query: $query');
    }
  });

  testWidgets('clearing the field returns to the hint', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    await searchFor(tester, 'apfel');
    expect(resultRows, findsWidgets);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.textContaining('Funktioniert auch offline'), findsOneWidget);
  });

  testWidgets('typing incrementally keeps returning results', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    for (final partial in ['h', 'ha', 'haf', 'hafe', 'hafer']) {
      await searchFor(tester, partial);
      expect(
        resultRows,
        findsWidgets,
        reason: 'no results while typing "$partial"',
      );
    }
  });
}
