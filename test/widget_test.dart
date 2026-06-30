import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noema/app/noema_app.dart';

void main() {
  testWidgets('Noema app smoke test', (tester) async {
    await tester.pumpWidget(const NoemaApp());

    expect(find.text('Noema'), findsOneWidget);
  });

  testWidgets('Noema falls back to English for unsupported system locale', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const NoemaApp());

    expect(find.text('Noema'), findsOneWidget);
    expect(find.byTooltip('Create a space'), findsOneWidget);
  });
}
