// If the gateway stopped answering, every tab has to say so.
//
// CD-23 in the 2026-09-15 register, carried forward unfixed. The shell builds
// the "No connection / showing data from <time> / Retry" banner in
// `_leadingSlivers()`, and only Review and Schedule call it. Studio, Results
// and Accounts render the same stale snapshot with no banner and no retry, so
// a connection Zion can see is broken on one tab looks healthy on the next
// three — and Studio is where he uploads, Accounts is where he connects.
//
// Everything is synthetic. No provider route, credential or network resource
// is reachable from this test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

/// A gateway that serves the catalogue and then fails the enrichment call, so
/// the app has a snapshot and a `lastFetch` *and* an error — which is exactly
/// the state the banner exists to describe: stale data, still on screen.
FakeGateway _stale() =>
    FakeGateway(failures: const <String, int>{'/reels/controls': 503});

void main() {
  setUpAll(loadAppFonts);

  testWidgets('every tab says the connection is down, and offers Retry', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      expect(
        reelRows,
        findsWidgets,
        reason: 'the stale snapshot is still on screen',
      );

      for (final String tab in <String>[
        'REVIEW',
        'SCHEDULE',
        'STUDIO',
        'RESULTS',
        'ACCOUNTS',
      ]) {
        await tapTab(tester, tab);
        expect(
          find.text('No connection'),
          findsWidgets,
          reason: '$tab must not present stale data as live data',
        );
        expect(
          find.text('Retry'),
          findsWidgets,
          reason: '$tab must offer a way out',
        );
      }
    }, createHttpClient: (SecurityContext? c) => _stale());
  });

  testWidgets('a healthy gateway shows the banner on no tab at all', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      for (final String tab in <String>[
        'REVIEW',
        'SCHEDULE',
        'STUDIO',
        'RESULTS',
        'ACCOUNTS',
      ]) {
        await tapTab(tester, tab);
        expect(find.text('No connection'), findsNothing, reason: tab);
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });
}
