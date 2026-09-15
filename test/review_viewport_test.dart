// What the Review screen gives the list, and what it looks like at rest.
//
// Two jobs, deliberately in one file so they cannot drift apart:
//
//   1. A golden of the whole shell at rest, at both text scales. The command
//      bar and the control row are allowed to move while a finger is on the
//      list; they are not allowed to look any different when it is not. The
//      golden is the contract for that.
//   2. A measurement of the scroll viewport the list is actually handed. Of a
//      740 pt workspace the shipped build gives it 513 pt at text scale 1.0
//      and 426 pt at 1.5, so the chrome keeps 227 pt and 314 pt respectively
//      and never gives any of it back. That is what a half-screen screenshot
//      of this app is. (The 2026-09-15 register reports 462/287 for the same
//      screen; it measured with the test's fallback font rather than the
//      bundled Inter, which is wider. Same defect, different type metrics.)
//
// Everything here is synthetic. No provider route, credential or network
// resource is used: the gateway is a fake HttpClient and the wall clock is
// pinned, so the rendered pixels are the same on any day and any machine.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

const Key _frame = ValueKey<String>('review-rest-frame');

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Review at rest is pixel-identical to the shipped screen', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, frameKey: _frame);
      await expectLater(
        find.byKey(_frame),
        matchesGoldenFile('goldens/review_rest_390x844.png'),
      );
      expect(tester.takeException(), isNull);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  testWidgets('Review at rest with Larger Text is pixel-identical', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, textScale: 1.5, frameKey: _frame);
      await expectLater(
        find.byKey(_frame),
        matchesGoldenFile('goldens/review_rest_390x844_large_text.png'),
      );
      expect(tester.takeException(), isNull);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  testWidgets('the Review list is handed the screen, measured', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final double scale in <double>[1, 1.5]) {
        await bootConsole(tester, textScale: scale, frameKey: _frame);
        final ScrollPosition position = tabScrollPosition(tester);
        final double viewport = position.viewportDimension;
        final double row = tester.getSize(reelRows.first).height;
        debugPrint('MEASURED 390x844 DPR2, 162 assets, text scale $scale');
        debugPrint('  list viewport      ${viewport.toStringAsFixed(1)}');
        debugPrint('  reel row height    ${row.toStringAsFixed(1)}');
        debugPrint(
          '  whole cards        ${(viewport / row).toStringAsFixed(2)}',
        );
        debugPrint(
          '  first card top     '
          '${tester.getTopLeft(reelRows.first).dy.toStringAsFixed(1)}',
        );
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // Shipped 1.0.40+49, measured by the test above with the app fonts loaded:
  //   text scale 1.0   viewport 513.0   row 140.0   3.66 cards
  //   text scale 1.5   viewport 426.0   row 309.0   1.38 cards
  // The workspace between the safe area and the tab bar is 740 pt, so the
  // chrome was taking 227 pt at 1.0 and 314 pt at 1.5 and never giving it back.
  testWidgets('the list viewport is at least 650 pt at text scale 1.0', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, frameKey: _frame);
      expect(
        tabScrollPosition(tester).viewportDimension,
        greaterThanOrEqualTo(650),
      );
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  testWidgets('with Larger Text the list is given most of the screen', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, textScale: 1.5, frameKey: _frame);
      final double viewport = tabScrollPosition(tester).viewportDimension;
      final double row = tester.getSize(reelRows.first).height;
      expect(viewport, greaterThanOrEqualTo(600));
      expect(viewport / row, greaterThanOrEqualTo(1.8));
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });
}
