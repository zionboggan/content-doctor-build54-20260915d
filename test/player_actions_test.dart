// Nothing in the player is allowed to fail quietly.
//
// Scrap, Post now, Cancel, Restore and Retry were called from the reel view
// without `await`, without `setState` and without advancing or popping. The
// handlers did their work on the home page, which is underneath the pushed
// route and invisible, and the only thing that repainted the player was the
// video tick listener — which does nothing when playback is paused or failed.
// So: scrap a reel and it was still there; post it and nothing visibly
// happened; cancel a schedule and the button still said Reschedule, so it got
// tapped again.
//
// Approve was worse. It returned a bool, the adapter threw the bool away, and
// the player advanced to the next reel unconditionally. A failed approve
// looked exactly like a successful one.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/main.dart' show ReelView, markWatched;

import 'support/console_harness.dart';

Map<String, dynamic> _reel(String id) => <String, dynamic>{
  'id': id,
  'sha256': 'sha-$id',
  'account': '@zionboggan',
  'title': 'Yacht sequence $id',
  'caption': 'A caption for $id',
  'status': 'ready_for_review',
  'duration_seconds': 23,
  'created_at': kPinnedNow.subtract(const Duration(hours: 3)).toIso8601String(),
};

List<Map<String, dynamic>> _two() => <Map<String, dynamic>>[
  _reel('one'),
  _reel('two'),
];

/// The reel view's own counter. "1 / 2" is the first reel, "2 / 2" the second,
/// and neither is rendered once the route has popped.
Finder _showing(String position) => find.text(position);

/// The player wraps its stage in a RawGestureDetector carrying a double tap
/// recogniser, so a single tap on a control inside it only resolves once the
/// double tap window has passed.
Future<void> _tapInPlayer(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _openFirstReel(WidgetTester tester) async {
  await tester.tap(reelRow('one'));
  await tester.pumpAndSettle();
  expect(_showing('1 / 2'), findsOneWidget, reason: 'the player opened');
}

Future<void> _overflowRow(WidgetTester tester, String label) async {
  await _tapInPlayer(
    tester,
    find.descendant(
      of: find.byType(ReelView),
      matching: find.bySemanticsLabel('More actions'),
    ),
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _holdApprove(WidgetTester tester) async {
  final TestGesture hold = await tester.startGesture(
    tester.getCenter(find.text('Approve')),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  await hold.up();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a scrap that fails says so, in the player, and stays put', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(
      catalog: _two(),
      failures: const <String, int>{'/reels/scrap': 500},
    );
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await _openFirstReel(tester);

      await _overflowRow(tester, 'Scrap reel');
      await tester.tap(find.text('Scrap reel').last); // the confirm sheet
      await tester.pumpAndSettle();

      expect(
        gateway.callsTo('/reels/scrap'),
        hasLength(1),
        reason: 'it was actually attempted',
      );
      expect(
        find.text('That did not go through'),
        findsOneWidget,
        reason: 'the failure is on the screen the operator is looking at',
      );
      expect(
        _showing('1 / 2'),
        findsOneWidget,
        reason: 'the player did not move on from a reel it failed to scrap',
      );
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('a scrap that works moves the player on', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(catalog: _two());
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await _openFirstReel(tester);
      await _overflowRow(tester, 'Scrap reel');
      await tester.tap(find.text('Scrap reel').last);
      await tester.pumpAndSettle();

      expect(gateway.callsTo('/reels/scrap'), hasLength(1));
      expect(find.text('That did not go through'), findsNothing);
      expect(
        _showing('2 / 2'),
        findsOneWidget,
        reason: 'the player advanced to the next reel',
      );
      // Scrapping clears the reel's watch coverage, which schedules the
      // module-level 700 ms write debounce. Let it land rather than leave a
      // pending timer behind. (That timer belongs to no lifecycle and is
      // never flushed on backgrounding — recorded, not fixed here.)
      await tester.pump(const Duration(milliseconds: 800));
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('dismissing a confirm sheet writes nothing and says nothing', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(catalog: _two());
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await _openFirstReel(tester);
      await _overflowRow(tester, 'Scrap reel');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(gateway.callsTo('/reels/scrap'), isEmpty);
      expect(find.text('That did not go through'), findsNothing);
      expect(_showing('1 / 2'), findsOneWidget);
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('an approve that fails does not advance to the next reel', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(
      catalog: _two(),
      failures: const <String, int>{'/reels/review-approve': 503},
    );
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      markWatched('sha-one', 23);
      await _openFirstReel(tester);
      await _holdApprove(tester);

      expect(
        gateway.callsTo('/reels/review-approve'),
        hasLength(1),
        reason: 'the approve was attempted',
      );
      expect(
        find.text('That did not go through'),
        findsOneWidget,
        reason: 'a failed approve says so instead of looking like a success',
      );
      expect(
        _showing('1 / 2'),
        findsOneWidget,
        reason: 'still on the reel that was not approved',
      );
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('an approve that works advances', (WidgetTester tester) async {
    final FakeGateway gateway = FakeGateway(catalog: _two());
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      markWatched('sha-one', 23);
      await _openFirstReel(tester);
      await _holdApprove(tester);

      expect(gateway.callsTo('/reels/review-approve'), hasLength(1));
      expect(find.text('That did not go through'), findsNothing);
      expect(_showing('2 / 2'), findsOneWidget);
    }, createHttpClient: (SecurityContext? c) => gateway);
  });
}
