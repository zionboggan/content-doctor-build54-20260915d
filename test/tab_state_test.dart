// Leaving a tab must not destroy it.
//
// Zion scrolls a long way into Review, taps Schedule to check something, taps
// Review again — and he is at the top of 162 reels. At the viewport the
// shipped build gives him that is around fifty screens of scrolling to get
// back. Team loses the conversation he had open. Inbox and Automations refetch
// everything.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

void main() {
  testWidgets('Review keeps its scroll position across a tab round trip', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway();
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);

      tabScrollPosition(tester).jumpTo(3000);
      await tester.pumpAndSettle();
      final double before = tabScrollPosition(tester).pixels;
      final Set<String> rowsBefore = mountedRowKeys();
      expect(before, 3000);
      expect(rowsBefore, isNotEmpty);

      await tapTab(tester, 'SCHEDULE');
      await tapTab(tester, 'REVIEW');

      final double after = tabScrollPosition(tester).pixels;
      final Set<String> rowsAfter = mountedRowKeys();
      debugPrint('MEASURED Review -> Schedule -> Review');
      debugPrint('  offset before  $before');
      debugPrint('  offset after   $after');
      debugPrint(
        '  rows reused    ${rowsAfter.intersection(rowsBefore).length}'
        ' of ${rowsBefore.length}',
      );

      expect(after, before, reason: 'the scroll position survives the trip');
      expect(
        rowsAfter.intersection(rowsBefore).length,
        rowsBefore.length,
        reason: 'the same rows are still mounted',
      );
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('returning to a tab does not refetch the whole catalogue', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway();
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      final int catalogLoads = gateway.callsTo('/reels/catalog').length;

      await tapTab(tester, 'SCHEDULE');
      await tapTab(tester, 'REVIEW');
      await tapTab(tester, 'STUDIO');
      await tapTab(tester, 'REVIEW');

      debugPrint(
        'MEASURED catalogue reads: $catalogLoads at boot, '
        '${gateway.callsTo('/reels/catalog').length} after four tab taps',
      );
      // Tab bodies read the shell's snapshot. Switching tabs must not be a
      // reason to go back to the gateway.
      expect(gateway.callsTo('/reels/catalog').length, catalogLoads);
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('Team keeps the thread it had open across a tab round trip', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(
      catalog: reviewCatalog(count: 2),
      routes: <String, Object Function()>{
        '/reels/team/threads': () => <String, dynamic>{
          'account': '@zionboggan',
          'threads': <Map<String, dynamic>>[
            <String, dynamic>{
              'thread_id': 'chief',
              'role_title': 'Chief Operator',
              'message_count': 1,
              'open_count': 1,
              'last_delivery': 'queued',
              'last_preview': 'One review needs a human decision.',
            },
          ],
        },
        '/reels/team/thread': () => <String, dynamic>{
          'account': '@zionboggan',
          'thread_id': 'chief',
          'role_title': 'Chief Operator',
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'at': '2026-09-15T18:00:00Z',
              'job_id': 'job-1',
              'direction': 'inbound',
              'text': 'A distinctive line only the open thread renders.',
            },
          ],
        },
      },
    );
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await tapTab(tester, 'TEAM');
      await tester.tap(find.text('Chief Operator').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('only the open thread renders'),
        findsOneWidget,
        reason: 'the thread opened',
      );

      await tapTab(tester, 'REVIEW');
      await tapTab(tester, 'TEAM');

      expect(
        find.textContaining('only the open thread renders'),
        findsOneWidget,
        reason: 'Team came back to the conversation, not to the roster',
      );
    }, createHttpClient: (SecurityContext? c) => gateway);
  });
}
