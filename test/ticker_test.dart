// Closing a reel must not build an animation controller on the way out.
//
// _SplitPrimary declares its 600 ms hold controller `late final`. On a reel
// below the coverage gate the button is disarmed, so `build` never reads the
// field and neither do its tap closures — which makes `dispose()` the first
// read. Constructing an AnimationController there looks up TickerMode on an
// already-deactivated element. In a release build the assertion is compiled
// out and a Ticker plus its TickerMode listener is orphaned on every reel
// close, which is why this is invisible on device and explodes under
// instrumentation.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:iris/main.dart' show markWatched;

import 'support/console_harness.dart';

void main() {
  testWidgets('opening and closing an unwatched reel throws nothing', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        // Below the coverage gate: the primary is disarmed, which is the state
        // in which the controller is never read during the widget's life.
        await tester.tap(reelRow('reel0'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the reel opened');

        await popRoute(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'no ticker was created while the element was deactivating',
        );
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: reviewCatalog(count: 3)),
    );
  });

  testWidgets('closing an armed reel throws nothing either', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        markWatched('sha0', 23);
        await tester.tap(reelRow('reel0'));
        await tester.pumpAndSettle();
        await popRoute(tester);
        expect(tester.takeException(), isNull);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: reviewCatalog(count: 3)),
    );
  });
}
