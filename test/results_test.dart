import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/app_motion.dart';
import 'package:iris/native_results.dart';

void main() {
  testWidgets('Results tabs show only real account-scoped insights history', (
    tester,
  ) async {
    String scope = '@zion';
    late StateSetter changeScope;
    final data = {
      'records': [
        {
          'id': 'a',
          'account': '@zion',
          'state': 'observed',
          'metrics': {'views': 17},
        },
        {
          'id': 'b',
          'account': '@gabe',
          'state': 'observed',
          'metrics': {'views': 99},
        },
      ],
      'history': [
        {
          'observed_at': '2026-09-13T12:00:00Z',
          'records': [
            {
              'id': 'a',
              'account': '@zion',
              'metrics': {'views': 17},
            },
            {
              'id': 'b',
              'account': '@gabe',
              'metrics': {'views': 99},
            },
          ],
        },
        {
          'observed_at': '2026-09-13T13:00:00Z',
          'records': [
            {
              'id': 'b',
              'account': '@gabe',
              'metrics': {'views': 100},
            },
          ],
        },
        {
          'observed_at': '2026-09-13T14:00:00Z',
          'records': [
            {'id': 'a', 'account': '@zion', 'metrics': <String, Object>{}},
          ],
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            changeScope = setState;
            return Scaffold(
              body: SingleChildScrollView(
                child: NativeResults(
                  base: 'http://127.0.0.1',
                  selectedAccounts: {scope},
                  catalog: const [],
                  accountStatus: const [],
                  load: () async => data,
                  connect: (_) {},
                  preview: (_) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Published 1'), findsOneWidget);
    expect(find.text('Activity 1'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('99'), findsNothing);
    await tester.tap(find.text('Activity 1'));
    await tester.pumpAndSettle();
    expect(find.text('Insights checked'), findsOneWidget);
    expect(find.text('1 reel has available measurements.'), findsOneWidget);
    expect(find.text('17'), findsNothing);
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      Duration.zero,
    );
    changeScope(() => scope = '@gabe');
    await tester.pumpAndSettle();
    expect(find.text('Activity 2'), findsOneWidget);
    expect(find.text('Insights checked'), findsNWidgets(2));
    await tester.tap(find.text('Published 1'));
    await tester.pumpAndSettle();
    expect(find.text('99'), findsOneWidget);
    expect(find.text('17'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Results does not invent activity when history is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: NativeResults(
            base: 'http://127.0.0.1',
            selectedAccounts: const {'all'},
            catalog: const [],
            accountStatus: const [],
            load: () async => {'records': []},
            connect: (_) {},
            preview: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity 0'));
    await tester.pumpAndSettle();
    expect(find.text('Activity history is not available yet.'), findsOneWidget);
    expect(find.text('Insights checked'), findsNothing);
    await tester.tap(find.text('Published 0'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Results appear here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Results metrics fit a phone at large text and preview opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NativeResults(
              base: 'http://127.0.0.1',
              selectedAccounts: const {'all'},
              catalog: const [
                {
                  'id': 'r1',
                  'title': 'An extended title for a real published reel',
                  'account': '@example',
                },
              ],
              accountStatus: const [],
              load: () async => {
                'records': [
                  {
                    'id': 'r1',
                    'account': '@example',
                    'state': 'observed',
                    'metrics': {
                      'views': 12023,
                      'reach': 138,
                      'shares': 2,
                      'saved': 0,
                    },
                    'media_fields': {
                      'like_count': 9,
                      'comments_count': 0,
                      'timestamp': '2026-09-10T12:00:00Z',
                    },
                  },
                ],
              },
              connect: (_) {},
              preview: (reel) => opened = reel,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final valueText = tester.widget<Text>(find.text('12023'));
    expect(valueText.maxLines, 1);
    expect(valueText.softWrap, false);
    expect(
      find.ancestor(of: find.text('12023'), matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    for (final label in [
      'Views',
      'Reach',
      'Likes',
      'Comments',
      'Shares',
      'Saves',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('An extended title for a real published reel'));
    expect(opened?['id'], 'r1');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native Results filters accounts and keeps missing metrics unavailable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NativeResults(
                base: 'http://127.0.0.1',
                selectedAccounts: const <String>{'@zionboggan'},
                catalog: const <Map<String, dynamic>>[],
                accountStatus: const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'account': '@zionboggan',
                    'insights': <String, dynamic>{
                      'status': 'needs_connect',
                      'data_status': 'available',
                    },
                  },
                ],
                load: () async => <String, dynamic>{
                  'records': <dynamic>[
                    <String, dynamic>{
                      'id': 'zion',
                      'account': '@zionboggan',
                      'state': 'observed',
                      'metrics': <String, dynamic>{
                        'views': 21,
                        'reach': 30,
                        'total_interactions': 0,
                      },
                    },
                    <String, dynamic>{
                      'id': 'gabe',
                      'account': '@barcrawling',
                      'state': 'observed',
                      'metrics': <String, dynamic>{'views': 99},
                    },
                  ],
                },
                connect: (_) {},
                preview: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('21'), findsOneWidget);
      expect(find.text('99'), findsNothing);
      expect(find.text('Best reach'), findsOneWidget);
      expect(find.text('Interactions'), findsOneWidget);
      expect(find.text('Top reels'), findsOneWidget);
      expect(find.byType(CdEnter), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('–'), findsNWidgets(4));
      expect(find.bySemanticsLabel('Likes: Not available'), findsOneWidget);
      expect(find.text('Shares'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Saves'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('Results entry reaches its final state when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: NativeResults(
            base: 'http://127.0.0.1',
            selectedAccounts: const <String>{'@zionboggan'},
            catalog: const <Map<String, dynamic>>[],
            accountStatus: const <Map<String, dynamic>>[],
            load: () async => <String, dynamic>{
              'records': <dynamic>[
                <String, dynamic>{
                  'id': 'zion',
                  'account': '@zionboggan',
                  'state': 'observed',
                  'metrics': <String, dynamic>{'reach': 30},
                },
              ],
            },
            connect: (_) {},
            preview: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    final Finder entry = find.byType(CdEnter);
    expect(entry, findsOneWidget);
    final Opacity opacity = tester.widget<Opacity>(
      find.descendant(of: entry, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
    expect(tester.takeException(), isNull);
  });
}
