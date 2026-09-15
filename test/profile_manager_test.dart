import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/profile_manager.dart';

const brief = {
  'recommendations': [
    {
      'id': 'resolve_queue',
      'evidence': [
        {
          'reel_id': 'zion-open-water-v4',
          'state': 'needs_attention',
          'scheduled_at': null,
        },
      ],
    },
    {'id': 'taste_unavailable', 'evidence': <String, Object>{}},
    {
      'id': 'review_reference',
      'evidence': {
        'reel_id': 'zion-life-maxxing-v1',
        'views': 1432,
        'observed_at': '2026-09-13T20:05:34Z',
      },
    },
  ],
  'draft_experiments': [
    {
      'variable': 'post_caption',
      'direction': 'Draft a new caption.',
      'parent_reel_id': 'zion-life-maxxing-v1',
      'measurement':
          'Compare distinct reels at matched 24h/72h/7d ages; preserve raw units and do not infer causality.',
    },
  ],
  'analytics': {'observed_at': '2026-09-13T20:05:34Z'},
  'missing_data': ['source-taste-reviews.json unavailable'],
};

void main() {
  testWidgets(
    'profile brief renders human fields, empty evidence and dates on small phones',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileManagerCard(
                accounts: const ['@zion'],
                read: (_) async => brief,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View brief & experiment ideas'));
      await tester.tap(find.text('View brief & experiment ideas'));
      await tester.pumpAndSettle();
      final listScroll = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      Future<void> reveal(String text) async {
        await tester.scrollUntilVisible(
          find.text(text).last,
          140,
          scrollable: listScroll,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(text).last);
        await tester.pumpAndSettle();
      }

      await reveal('Check posts that need attention');
      await tester.tap(find.text('Check posts that need attention').last);
      await tester.pumpAndSettle();
      await reveal('Needs attention');
      expect(find.text('No time set'), findsOneWidget);
      expect(find.text('Zion open water version 4'), findsOneWidget);
      expect(find.textContaining('reel_id:'), findsNothing);
      expect(find.textContaining('needs_attention'), findsNothing);
      await reveal('Source reviews are unavailable');
      await tester.tap(find.text('Source reviews are unavailable'));
      await tester.pumpAndSettle();
      await reveal('No supporting details are available yet.');
      expect(find.textContaining('Evidence: {}'), findsNothing);
      await reveal('Review a high-view reel');
      await tester.tap(find.text('Review a high-view reel'));
      await tester.pumpAndSettle();
      await reveal('1432');
      expect(find.text('Last measured'), findsWidgets);
      expect(find.textContaining('2026-09-13T'), findsNothing);
      await reveal('Post caption');
      await reveal('How to compare');
      expect(
        find.textContaining('24 hours, 72 hours and 7 days'),
        findsOneWidget,
      );
      await reveal('Data coverage');
      await tester.tap(find.text('Data coverage'));
      await tester.pumpAndSettle();
      await reveal('Saved source reviews could not be loaded.');
      expect(find.textContaining('.json'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing accounts does not display a previous account brief', (
    tester,
  ) async {
    final second = Completer<dynamic>();
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: ProfileManagerCard(
            accounts: const ['@zion', '@gabe'],
            read: (path) async {
              if (path.contains('gabe')) return await second.future;
              return brief;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check posts that need attention'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@gabe').last);
    await tester.pumpAndSettle();
    expect(find.text('Check posts that need attention'), findsNothing);
    expect(
      find.text('Loading your brief…'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    second.complete({'recommendations': []});
    await tester.pumpAndSettle();
    expect(find.text('No changes suggested right now.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no account and malformed optional data remain readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: ProfileManagerCard(accounts: const [], read: (_) async => null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose an account to see its brief.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
