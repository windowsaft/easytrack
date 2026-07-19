import 'package:easytrack/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots and shows the diary tab first', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EasyTrackApp()));

    expect(find.text('Tagebuch'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EasyTrackApp()));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Profil folgt'), findsOneWidget);
  });
}
