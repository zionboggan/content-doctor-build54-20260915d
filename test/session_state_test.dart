// Not signed in and cannot ask are different answers.
//
// _readSessionRole caught everything — timeout, socket error, TLS failure,
// HTTP 500 — and returned the same null that means "this device has no
// credential". The shell then computed locked = true and rendered
// "Session locked / Unlock". Off the Tailnet, or through a flapping gateway,
// Zion was told he was signed out and sent hunting for credentials that were
// never the problem.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

void main() {
  testWidgets('a gateway that will not answer is a connection problem', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, settle: false);
        expect(
          find.text('No connection'),
          findsOneWidget,
          reason: 'the gateway did not answer, and says so',
        );
        expect(
          find.text('Session locked'),
          findsNothing,
          reason: 'he is not signed out',
        );
        expect(
          find.text('Unlock'),
          findsOneWidget,
          reason: 'still reachable, because a credential problem is possible',
        );
        expect(find.text('Retry'), findsOneWidget);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(failures: const <String, int>{'/trial-auth': 500}),
    );
  });

  testWidgets('a gateway that says no is a session problem', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, settle: false);
        expect(
          find.text('Session locked'),
          findsOneWidget,
          reason: '401 is the gateway refusing the credential',
        );
        expect(find.text('No connection'), findsNothing);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(failures: const <String, int>{'/trial-auth': 401}),
    );
  });

  testWidgets('a healthy gateway shows neither', (WidgetTester tester) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        expect(find.text('Session locked'), findsNothing);
        expect(find.text('No connection'), findsNothing);
        expect(reelRows, findsWidgets);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: reviewCatalog(count: 3)),
    );
  });
}
