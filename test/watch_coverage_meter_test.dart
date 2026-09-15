// The watch meter under Approve has to be a fraction of Approve.
//
// The bar that shows how much of a reel has been watched was laid out with
// `width: MediaQuery.sizeOf(context).width * coverage` and painted inside the
// Approve button. The button is not the screen: the player's control deck
// insets it by 16 pt on each side, and while the schedule door is showing it
// gives up a further 55 pt plus a 1 pt divider. So the bar was drawn against a
// reference 88 pt wider than the thing it was drawn in, the ClipRRect quietly
// cut off the overshoot, and it read full at 77% watched — while Approve was
// still disabled, with nothing on screen to say how much was left.
//
// The approve gate itself is 80% (`coverageGate`) and is not changed here.
//
// Everything is synthetic. No provider route, credential or network resource
// is reachable from this test.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/main.dart';

import 'support/console_harness.dart';

const Key _meter = ValueKey<String>('watch-coverage');

/// The catalogue fixture is sorted and grouped before it reaches the list, so
/// the reel at the top is not necessarily `reel0`. Its sha is what the watch
/// store is keyed on.
String _shaOfTopRow() => reelRows
    .evaluate()
    .map((Element e) => (e.widget.key! as ValueKey<String>).value)
    .first
    .replaceFirst('reel-row-reel', 'sha');

void main() {
  setUpAll(loadAppFonts);

  /// The Approve button the meter is painted inside.
  Finder approveButton() => find.ancestor(
    of: find.byKey(_meter),
    matching: find.byType(AnimatedContainer),
  );

  for (final (String name, DeviceView view) in <(String, DeviceView)>[
    ('a phone', kPhone),
    ('an iPad Pro 12.9 in landscape', kIpad129Landscape),
  ]) {
    testWidgets('the watch meter is a fraction of the button on $name', (
      WidgetTester tester,
    ) async {
      await HttpOverrides.runZoned(() async {
        await bootConsole(tester, view: view);
        // Half of a 10 second reel, so the gate is not met and the meter is
        // the only thing telling Zion where he is.
        final String sha = _shaOfTopRow();
        for (int second = 0; second < 5; second++) {
          recordWatched(sha, second, 10);
        }
        expect(coverageFor(sha), 0.5);

        await tester.tap(reelRows.first);
        await tester.pumpAndSettle();
        expect(find.byKey(_meter), findsOneWidget);

        final double button = tester.getSize(approveButton()).width;
        final double meter = tester.getSize(find.byKey(_meter)).width;
        debugPrint(
          'MEASURED $name  screen ${view.logical.width.toStringAsFixed(0)}'
          '  Approve button ${button.toStringAsFixed(1)}'
          '  meter at 50% watched ${meter.toStringAsFixed(1)}',
        );

        expect(
          meter,
          closeTo(button * 0.5, 0.5),
          reason: 'half watched is half of the button, not half the screen',
        );
        expect(
          meter,
          lessThan(button),
          reason: 'a partly watched reel never reads as fully watched',
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (SecurityContext? c) => FakeGateway());
    });
  }

  testWidgets(
    'the meter reaches the button edge only when the reel is watched',
    (WidgetTester tester) async {
      await HttpOverrides.runZoned(() async {
        await bootConsole(tester);
        // 77% — the point at which the shipped bar already filled the button
        // on a 390 pt phone, while Approve was still gated at 80%.
        final String sha = _shaOfTopRow();
        for (int second = 0; second < 77; second++) {
          recordWatched(sha, second, 100);
        }
        await tester.tap(reelRows.first);
        await tester.pumpAndSettle();

        final double button = tester.getSize(approveButton()).width;
        final double meter = tester.getSize(find.byKey(_meter)).width;
        debugPrint(
          'MEASURED at 77% watched, gate ${(coverageGate * 100).round()}%:'
          '  button ${button.toStringAsFixed(1)}'
          '  meter ${meter.toStringAsFixed(1)}'
          '  shipped would have drawn ${(390 * 0.77).toStringAsFixed(1)}',
        );
        expect(meter, closeTo(button * 0.77, 0.5));
        expect(
          meter,
          lessThan(button),
          reason: 'still short of the gate, and it looks short of the gate',
        );
        // The shipped reference was the full 390 pt screen. MEASURED: the
        // button is 302 pt, so the old bar reached the button's edge at
        // 302/390 = 77.4% watched and the ClipRRect hid everything after
        // that — it read full before the 80% gate it was reporting against.
        expect(button / kPhone.logical.width, closeTo(0.774, 0.002));
        expect(
          kPhone.logical.width * coverageGate,
          greaterThan(button),
          reason: 'the shipped bar saturated before Approve unlocked',
        );
      }, createHttpClient: (SecurityContext? c) => FakeGateway());
    },
  );
}
