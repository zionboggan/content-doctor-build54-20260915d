// The catalog-to-schedule join, pinned at the UI.
//
// `_enriched` used to find a reel's schedule by scanning every schedule entry
// for every reel, taking `matches.last`. It is an indexed lookup now, and this
// test exists to pin the two behaviours that made the old version correct and
// that an index could silently change: only an exact id + sha256 + account
// match counts, and when a reel has more than one matching entry the *last*
// one -- the most recent write -- is the one shown.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

Map<String, dynamic> _schedule(
  String id,
  String sha,
  String account,
  DateTime at,
) => <String, dynamic>{
  'id': id,
  'sha256': sha,
  'account': account,
  'state': 'scheduled',
  'scheduled_at': at.toIso8601String(),
};

void main() {
  testWidgets('a reel shows its last matching schedule, not its first', (
    WidgetTester tester,
  ) async {
    final List<Map<String, dynamic>> catalog = reviewCatalog(count: 3);
    // reel0 is '@zionboggan' / 'sha0'. Three entries claim to be its schedule:
    // one with the wrong sha, one with the wrong account, then two real ones.
    final List<Map<String, dynamic>> schedules = <Map<String, dynamic>>[
      _schedule('reel0', 'wrong-sha', '@zionboggan', kPinnedNow.add(
        const Duration(hours: 1),
      )),
      _schedule('reel0', 'sha0', '@barcrawling', kPinnedNow.add(
        const Duration(hours: 2),
      )),
      _schedule('reel0', 'sha0', '@zionboggan', kPinnedNow.add(
        const Duration(hours: 3),
      )),
      _schedule('reel0', 'sha0', '@zionboggan', kPinnedNow.add(
        const Duration(hours: 9),
      )),
    ];
    final FakeGateway gateway = FakeGateway(
      catalog: catalog,
      routes: <String, Object Function()>{
        '/reels/schedules': () => <String, dynamic>{'entries': schedules},
      },
    );
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      // A scheduled reel leaves the default "Needs you" queue -- which is
      // itself proof the join attached -- so read it on the All segment.
      expect(mountedRowKeys(), isNot(contains('reel-row-reel0')));
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      // 21:00 UTC + 9h, in Phoenix (UTC-7), is 11:00 PM the same day.
      expect(
        find.descendant(
          of: reelRow('reel0'),
          matching: find.text('SCHEDULED 11:00 PM'),
        ),
        findsOneWidget,
        reason: 'the later of the two exact matches must win',
      );
      // The near-miss entries must not attach to anything.
      expect(
        find.descendant(
          of: reelRow('reel1'),
          matching: find.textContaining('SCHEDULED'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: reelRow('reel2'),
          matching: find.textContaining('SCHEDULED'),
        ),
        findsNothing,
      );
    }, createHttpClient: (_) => gateway);
  });
}
