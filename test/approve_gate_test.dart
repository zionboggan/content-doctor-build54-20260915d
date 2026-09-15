// A reel whose preview will not play must still be reviewable.
//
// The approve gate is local playback coverage: a reel is only approvable once
// 80% of its seconds have been observed playing. Coverage is only ever written
// from a playing controller, so a preview that 404s, 401s or stalls produced a
// reel that could never be approved, scheduled or posted — only scrapped. The
// escape hatch, "I watched this reel", was disabled in precisely those states,
// and its own zero-duration guard was unreachable code.
//
// In a widget test there is no video platform, so every preview fails to
// initialise. That is the device-side broken-preview state exactly.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/console_shell.dart';
import 'package:iris/main.dart' show markWatched;

import 'support/console_harness.dart';

Finder _buttonLabelled(String label) => find.widgetWithText(ConButton, label);

int _count(Finder finder) => finder.evaluate().length;

void main() {
  testWidgets('a reel with no playable preview can still be approved', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(catalog: reviewCatalog(count: 3));
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);

      debugPrint('MEASURED the list, with no preview that will play');
      debugPrint('  Approve buttons  ${_count(_buttonLabelled('Approve'))}');
      debugPrint('  Watch buttons    ${_count(_buttonLabelled('Watch'))}');
      expect(
        _count(_buttonLabelled('Approve')),
        0,
        reason: 'nothing is approvable before a watch',
      );
      expect(_count(_buttonLabelled('Watch')), greaterThan(0));

      await tester.tap(reelRow('reel0'));
      await tester.pumpAndSettle();

      // Inside the player. The preview failed, so the confirm control must be
      // offered, must say why, and must work.
      final Finder bypass = _buttonLabelled(
        'Playback is broken — approve without watching',
      );
      debugPrint('  bypass control   ${_count(bypass)}');
      expect(bypass, findsOneWidget);
      expect(
        tester.widget<ConButton>(bypass).onPressed,
        isNotNull,
        reason: 'enabled in exactly the state it exists for',
      );

      await tester.tap(bypass);
      await tester.pumpAndSettle();

      // The primary is now armed: hold it and the approve leaves the device.
      await popRoute(tester);
      debugPrint('  after the bypass:');
      debugPrint('  Approve buttons  ${_count(_buttonLabelled('Approve'))}');
      debugPrint('  Watch buttons    ${_count(_buttonLabelled('Watch'))}');
      expect(
        _count(_buttonLabelled('Approve')),
        1,
        reason: 'the reel Zion could not watch is now approvable from the card',
      );
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('the approve payload records that the watch was not observed', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(catalog: reviewCatalog(count: 3));
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await tester.tap(reelRow('reel0'));
      await tester.pumpAndSettle();
      await tester.tap(
        _buttonLabelled('Playback is broken — approve without watching'),
      );
      await tester.pumpAndSettle();
      await popRoute(tester);

      await tester.tap(_buttonLabelled('Approve'));
      await tester.pumpAndSettle();

      final List<GatewayCall> approvals = gateway.callsTo(
        '/reels/review-approve',
      );
      expect(approvals, hasLength(1));
      final Map<String, dynamic> payload =
          jsonDecode(approvals.single.body) as Map<String, dynamic>;
      debugPrint('MEASURED approve payload $payload');
      expect(
        payload['watch_observed'],
        isFalse,
        reason: 'the server can tell an unwatchable reel from a watched one',
      );
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('a watched reel still reports the watch as observed', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(catalog: reviewCatalog(count: 3));
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await tester.tap(reelRow('reel0'));
      await tester.pumpAndSettle();
      // Stand in for a preview that played all the way through.
      markWatched('sha0', 23);
      await popRoute(tester);
      await tester.tap(_buttonLabelled('Approve'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> payload =
          jsonDecode(gateway.callsTo('/reels/review-approve').single.body)
              as Map<String, dynamic>;
      expect(payload['watch_observed'], isTrue);
    }, createHttpClient: (SecurityContext? c) => gateway);
  });
}
