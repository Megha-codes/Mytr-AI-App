import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metasync_app/features/nutrition/ui/widgets/nutrition_flags_row.dart';

/// NutritionFlagsRow is a firm boundary in the product spec: descriptive
/// flags only, never a verdict. These tests pin the exact thresholds and
/// confirm the row renders nothing at all when nothing crosses one —
/// silence, not a forced "everything's fine" message.
void main() {
  Future<void> pump(WidgetTester tester, {required double gl, required double fiberG}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NutritionFlagsRow(glycaemicLoad: gl, fiberG: fiberG)),
    ));
  }

  testWidgets('shows no flags for a middling glycaemic load and normal fiber', (tester) async {
    await pump(tester, gl: 15, fiberG: 5);
    expect(find.text('High glycaemic load'), findsNothing);
    expect(find.text('Low glycaemic load'), findsNothing);
    expect(find.text('Low fiber'), findsNothing);
    expect(find.text('High fiber'), findsNothing);
  });

  testWidgets('flags high glycaemic load at the clinical threshold (>=20)', (tester) async {
    await pump(tester, gl: 20, fiberG: 5);
    expect(find.text('High glycaemic load'), findsOneWidget);
  });

  testWidgets('flags low glycaemic load at the clinical threshold (<=10)', (tester) async {
    await pump(tester, gl: 10, fiberG: 5);
    expect(find.text('Low glycaemic load'), findsOneWidget);
  });

  testWidgets('flags low fiber under 3g', (tester) async {
    await pump(tester, gl: 15, fiberG: 2.9);
    expect(find.text('Low fiber'), findsOneWidget);
  });

  testWidgets('flags high fiber at 8g or more', (tester) async {
    await pump(tester, gl: 15, fiberG: 8);
    expect(find.text('High fiber'), findsOneWidget);
  });

  testWidgets('can show both a glycaemic-load flag and a fiber flag together', (tester) async {
    await pump(tester, gl: 25, fiberG: 1);
    expect(find.text('High glycaemic load'), findsOneWidget);
    expect(find.text('Low fiber'), findsOneWidget);
  });
}
