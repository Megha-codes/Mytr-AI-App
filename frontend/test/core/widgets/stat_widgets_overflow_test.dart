/// Overflow regression coverage for StatTile/MetricHintBox — the widgets
/// most exposed to text-overflow risk in this app: StatTile is laid out
/// 3-across on activity_screen.dart, and its `subtext`/MetricHintBox carries
/// freeform copy (metric_copy.dart's emptyMessage strings, some 60+
/// characters) with no length guarantee. `tester.takeException()` is what
/// actually catches a RenderFlex overflow here — it's a FlutterError thrown
/// during layout/paint, not something `flutter analyze` (static analysis)
/// would ever see.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metasync_app/core/theme/app_theme.dart';
import 'package:metasync_app/core/widgets/stat_widgets.dart';

/// Real emptyMessage strings from core/health/metric_copy.dart — the
/// longest ones on file, so this test exercises the worst case that
/// actually ships, not a synthetic string.
const _longestRealEmptyMessages = [
  'Needs a wearable worn for several hours to compute a resting rate.',
  'Needs a wearable worn overnight — HRV is computed while you sleep.',
  'Grant Health permission to see active calories.',
];

Future<void> _pumpAtWidth(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('StatTile 3-across (activity_screen.dart\'s actual layout)', () {
    for (final width in [320.0, 360.0, 430.0]) {
      testWidgets('no overflow at ${width}px width with the longest real empty-state messages', (tester) async {
        await _pumpAtWidth(
          tester,
          width,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24), // AppTheme.screenPadding
            child: Row(
              children: [
                for (var i = 0; i < _longestRealEmptyMessages.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Resting Heart Rate', // an intentionally long label too
                      value: '—',
                      subtext: _longestRealEmptyMessages[i],
                      textColor: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('MetricHintBox never renders more than 2 lines regardless of message length', (tester) async {
    await _pumpAtWidth(
      tester,
      320,
      const SizedBox(
        width: 90, // narrower than any real StatTile gets — a stress case
        child: MetricHintBox(
          text: 'This is a deliberately long helper message to prove the box '
              'caps itself instead of growing to fit, however long the copy is.',
          color: AppTheme.textPrimary,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.maxLines, 2);
    expect(textWidget.overflow, TextOverflow.ellipsis);
  });

  testWidgets('StatTile label + trailing icon never overflows with a long label', (tester) async {
    await _pumpAtWidth(
      tester,
      320,
      SizedBox(
        width: 90, // one tile's worth of space in a 3-across, 320px-wide row
        child: StatTile(
          label: 'Active Minutes Today', // longer than any real label on file
          value: '128',
          icon: Icons.info_outline,
          textColor: AppTheme.textPrimary,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
