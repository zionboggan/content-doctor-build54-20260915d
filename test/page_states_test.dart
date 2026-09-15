// Every tab has to answer for itself when there is nothing to show.
//
// A page-by-page audit of the six tabs against an empty catalogue and against
// a gateway that will not answer. The standard is the one the 2026-09-15
// register used: an empty state is only an empty state if it says which
// emptiness this is and offers the next thing to do. A spinner that never
// resolves, a blank column, or a screen that silently shows nothing is a
// dead end.
//
// This is a page audit, so it is written to be read as a table. It passes
// today — recorded because "we checked" is not evidence and because it is the
// regression net for every later change to these six screens.
//
// Everything is synthetic. No provider route, credential or network resource
// is reachable from this test.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

/// Every non-empty string of text currently on screen.
List<String> _copy(WidgetTester tester) => find
    .byType(Text)
    .evaluate()
    .map((Element e) => (e.widget as Text).data)
    .whereType<String>()
    .where((String s) => s.trim().isNotEmpty)
    .toList();

void _says(WidgetTester tester, String tab, String fragment) => expect(
  _copy(tester).where((String s) => s.contains(fragment)),
  isNotEmpty,
  reason:
      '$tab empty state must say "$fragment" — on screen: '
      '${_copy(tester).take(30).toList()}',
);

void main() {
  setUpAll(loadAppFonts);

  // | tab      | empty state says                                  | way out |
  // |----------|---------------------------------------------------|---------|
  // | Review   | Nothing waiting                                   | Show all reels · Request a reel |
  // | Schedule | Nothing queued                                    | the month grid stays live |
  // | Studio   | Your approved clips will appear here.              | Add from phone · Request a reel · Make variations |
  // | Results  | Results appear here after ... published.           | Connect (per account) |
  // | Accounts | Connection not checked                            | Connect (per account) · Sign out |
  // | Team     | No Bots on this account                           | account scope picker |
  testWidgets('an empty catalogue is explained on every tab', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);

        _says(tester, 'Review', 'Nothing waiting');
        expect(find.text('Show all reels'), findsOneWidget);
        expect(find.text('Request a reel'), findsOneWidget);

        await tapTab(tester, 'SCHEDULE');
        _says(tester, 'Schedule', 'Nothing queued');

        await tapTab(tester, 'STUDIO');
        _says(tester, 'Studio', 'Your approved clips will appear here.');
        expect(find.text('Add from phone'), findsOneWidget);
        expect(find.text('Make variations'), findsOneWidget);

        await tapTab(tester, 'RESULTS');
        _says(tester, 'Results', 'Results appear here after');

        await tapTab(tester, 'ACCOUNTS');
        _says(tester, 'Accounts', 'Connection not checked');
        await tester.scrollUntilVisible(find.text('Sign out'), 200);
        expect(find.text('Sign out'), findsOneWidget);

        await tapTab(tester, 'TEAM');
        _says(tester, 'Team', 'No Bots on this account');

        expect(tester.takeException(), isNull);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: <Map<String, dynamic>>[]),
    );
  });

  // Nothing cached, gateway refusing: the app must not sit on a spinner, and
  // must not claim the session is the problem (CD-18, fixed in 3d45197).
  testWidgets('a first load that fails names itself and offers Retry', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, settle: false);
        await tester.pumpAndSettle();
        _says(tester, 'first load', 'Could not load reels');
        _says(tester, 'first load', 'Nothing is cached on this device.');
        expect(find.text('Retry'), findsWidgets);
        expect(
          find.text('Session locked'),
          findsNothing,
          reason: 'a gateway that will not answer is not a credential problem',
        );
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(failures: const <String, int>{'/reels': 500}),
    );
  });

  // Same six tabs, at the iPad size where a centred column has the most
  // empty ground around it: an empty state must still be findable, not lost.
  testWidgets('the empty states survive an iPad Pro 12.9 in landscape', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, view: kIpad129Landscape);
        _says(tester, 'Review', 'Nothing waiting');
        for (final String tab in <String>[
          'SCHEDULE',
          'STUDIO',
          'RESULTS',
          'ACCOUNTS',
          'TEAM',
        ]) {
          await tapTab(tester, tab);
          expect(_copy(tester), isNotEmpty, reason: '$tab is not a blank page');
          expect(tester.takeException(), isNull, reason: tab);
        }
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: <Map<String, dynamic>>[]),
    );
  });
}
