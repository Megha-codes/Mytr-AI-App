/// Overflow regression coverage for ProfileRow — trailing is often
/// account/device data with no length guarantee at all (a wearable's own
/// Bluetooth name, a user-typed free-text goal), unlike this row's own
/// fixed `title` strings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metasync_app/core/theme/app_theme.dart';
import 'package:metasync_app/features/profile/ui/widgets/profile_widgets.dart';

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('ProfileRow does not overflow at ${width}px with a long title and a long trailing value', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
              child: ProfileRow(
                title: 'Connected devices',
                trailing: const Text(
                  "Asha's Very Long Custom Wearable Device Name Pro Max",
                  style: TextStyle(fontSize: 14),
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ProfileRow with a Row trailing (CGM Device pattern) does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
            child: ProfileRow(
              title: 'CGM Device',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Flexible(
                    child: Text(
                      'FreeStyle Libre 3 Plus Continuous Glucose Monitor',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.circle, size: 8, color: AppTheme.brandGreen),
                ],
              ),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
