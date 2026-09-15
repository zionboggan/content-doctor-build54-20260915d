// The flyer composer must not let a user do the one thing the Python
// compositor exists to prevent: ship a flyer with an invented or silently
// blank event detail. The tool refuses those decks server-side, but a form
// that quietly posts an empty string has already lost — the operator sees a
// render start and assumes the details were accepted.
//
// These tests cover the form's own required-field discipline, the render-job
// states the screen can show (submitted, rendering, ready, failed, and a
// render host that is simply not there), and the review-only framing.
//
// All data is synthetic. No network call, credential or render host is used:
// the read/write pair is a recording fake.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/flyer_composer_page.dart';

class FakeBackend {
  FakeBackend({this.rendererReachable = true, List<dynamic>? statuses})
    : statuses = statuses ?? <dynamic>[];

  final bool rendererReachable;
  final List<dynamic> statuses;
  final List<String> reads = <String>[];
  final List<Map<String, dynamic>> posts = <Map<String, dynamic>>[];
  int _status = 0;

  Future<dynamic> read(String path) async {
    reads.add(path);
    if (path == '/flyers/renderer') {
      return <String, dynamic>{
        'host': 'homelab@192.168.1.74',
        'mode': 'remote',
        'reachable': rendererReachable,
        'message': rendererReachable
            ? 'Render host 192.168.1.74 is answering.'
            : 'Render host 192.168.1.74 is not answering. Flyers cannot be '
                  'rendered until it is back.',
      };
    }
    final dynamic next = statuses.isEmpty
        ? <String, dynamic>{'status': 'unknown'}
        : statuses[_status.clamp(0, statuses.length - 1)];
    _status++;
    return next;
  }

  Future<dynamic> write(String path, Map<String, dynamic> payload) async {
    posts.add(<String, dynamic>{'path': path, ...payload});
    return <String, dynamic>{'job_id': 'flyer-test-1', 'status': 'queued'};
  }
}

Map<String, dynamic> ready({int slides = 2}) => <String, dynamic>{
  'id': 'flyer-test-1',
  'status': 'ready_for_review',
  'asset': <String, dynamic>{'id': 'flyer-test-1', 'slides': slides},
  'review_only': true,
  'manifest': <String, dynamic>{
    'publish_contract': <String, dynamic>{
      'ordered_assets': <String>[
        for (int i = 0; i < slides; i++) 'deck-0$i.png',
      ],
      'ordered_sha256': <String>[for (int i = 0; i < slides; i++) 'hash$i'],
    },
  },
};

Future<FakeBackend> boot(
  WidgetTester tester, {
  bool rendererReachable = true,
  List<dynamic>? statuses,
}) async {
  final FakeBackend backend = FakeBackend(
    rendererReachable: rendererReachable,
    statuses: statuses,
  );
  // A tall surface so the whole form is laid out; this screen is a normal
  // scrolling ListView on a phone, and nothing here depends on the size.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: FlyerComposerPage(
        accounts: const <String>['@zionboggan', '@barcrawling'],
        read: backend.read,
        write: backend.write,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

Future<void> fillHook(WidgetTester tester, {String name = 'app-flyer-one'}) async {
  await tester.enterText(find.byKey(const ValueKey<String>('flyer-deck-name')), name);
  const Map<String, String> values = <String, String>{
    'ARTIST_NAME': 'Trippy Red',
    'DATE': 'OCT 03',
    'VENUE': '9th & Jackson',
    'CITY': 'Phoenix, AZ',
    'EVENT_ID': 'EVENT ID // 004821',
    'CTA': 'Link in bio',
  };
  for (final MapEntry<String, String> entry in values.entries) {
    await tester.enterText(
      find.byKey(ValueKey<String>('flyer-slide-0-${entry.key}')),
      entry.value,
    );
  }
  await tester.pump();
}

Future<void> confirmAndRender(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('flyer-reviewed')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey<String>('flyer-render')));
  await tester.pumpAndSettle();
  // The poll loop waits two seconds between status calls and schedules no
  // frame while it does, so the clock has to be advanced deliberately.
  for (int round = 0; round < 3; round++) {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }
}

String messageText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey<String>('flyer-message')))
    .data!;

void main() {
  group('required-field discipline', () {
    test('a blank required slot is named, never defaulted', () {
      final FlyerSlideDraft hook = FlyerSlideDraft('slide-0', 'hook');
      hook.fields['ARTIST_NAME']!.text = 'Trippy Red';
      final List<String> problems = flyerDeckProblems(
        deckId: 'app-flyer-one',
        account: '@zionboggan',
        slides: <FlyerSlideDraft>[hook],
        allowPlaceholders: false,
      );
      expect(problems.single, contains('Slide 1 is missing'));
      for (final String slot in <String>[
        'date',
        'venue',
        'city',
        'event ID'.toLowerCase(),
        'call to action',
      ]) {
        expect(problems.single.toLowerCase(), contains(slot));
      }
      hook.dispose();
    });

    test('whitespace does not count as a filled slot', () {
      final FlyerSlideDraft cta = FlyerSlideDraft('slide-0', 'cta');
      cta.fields['CTA']!.text = '   ';
      expect(cta.blanks(), <String>['CTA']);
      expect(cta.textLayers(), isEmpty);
      cta.dispose();
    });

    test('a body slide needs at least one line', () {
      final FlyerSlideDraft body = FlyerSlideDraft('slide-0', 'body');
      body.fields['SECTION_LABEL']!.text = 'Event Details';
      expect(body.blanks(), <String>['BODY_LINE']);
      body.lines.first.text = 'Doors 9PM';
      expect(body.blanks(), isEmpty);
      expect(body.textLayers(), <Map<String, String>>[
        <String, String>{'field': 'SECTION_LABEL', 'value': 'Event Details'},
        <String, String>{'field': 'BODY_LINE', 'value': 'Doors 9PM'},
      ]);
      body.dispose();
    });

    test('placeholder mode is the only way a blank slot may be sent', () {
      final FlyerSlideDraft hook = FlyerSlideDraft('slide-0', 'hook');
      expect(
        flyerDeckProblems(
          deckId: 'app-flyer-one',
          account: '@zionboggan',
          slides: <FlyerSlideDraft>[hook],
          allowPlaceholders: true,
        ),
        isEmpty,
      );
      hook.dispose();
    });

    test('the deck name and account are both required', () {
      final FlyerSlideDraft cta = FlyerSlideDraft('slide-0', 'cta');
      cta.fields['CTA']!.text = 'Link in bio';
      expect(
        flyerDeckProblems(
          deckId: 'Not A Deck',
          account: '@zionboggan',
          slides: <FlyerSlideDraft>[cta],
          allowPlaceholders: false,
        ).single,
        contains('lowercase'),
      );
      expect(
        flyerDeckProblems(
          deckId: 'app-flyer-one',
          account: null,
          slides: <FlyerSlideDraft>[cta],
          allowPlaceholders: false,
        ).single,
        contains('Choose an account'),
      );
      cta.dispose();
    });

    test('a carousel may not exceed what Instagram accepts', () {
      final List<FlyerSlideDraft> slides = <FlyerSlideDraft>[
        for (int i = 0; i < 11; i++)
          FlyerSlideDraft('slide-$i', 'cta')..fields['CTA']!.text = 'Link',
      ];
      expect(
        flyerDeckProblems(
          deckId: 'app-flyer-one',
          account: '@zionboggan',
          slides: slides,
          allowPlaceholders: false,
        ).first,
        contains('2 to 10'),
      );
      for (final FlyerSlideDraft slide in slides) {
        slide.dispose();
      }
    });
  });

  testWidgets('an incomplete deck names every blank slot and sends nothing', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await boot(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('flyer-deck-name')),
      'app-flyer-one',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('flyer-slide-0-ARTIST_NAME')),
      'Trippy Red',
    );
    await confirmAndRender(tester);

    expect(backend.posts, isEmpty);
    final String shown = messageText(tester).toLowerCase();
    expect(shown, contains('slide 1 is missing'));
    expect(shown, contains('event id'));
  });

  testWidgets('a complete deck is submitted verbatim in slide order', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await boot(
      tester,
      statuses: <dynamic>[ready(slides: 1)],
    );
    await fillHook(tester);
    await confirmAndRender(tester);

    expect(backend.posts.single['path'], '/flyers/render');
    final Map<String, dynamic> sent = backend.posts.single;
    expect(sent['account'], '@zionboggan');
    expect(sent['on_missing_field'], 'fail');
    expect(sent['brand_profile'], 'desert_events');
    final List<dynamic> slides = sent['slides'] as List<dynamic>;
    expect(slides.single['layout'], 'hud_ticket');
    expect(slides.single['index'], 0);
    // Values arrive exactly as typed: no reformatting, no added weekday.
    final List<dynamic> layers = slides.single['text_layers'] as List<dynamic>;
    expect(
      layers.firstWhere((dynamic l) => l['field'] == 'DATE')['value'],
      'OCT 03',
    );
    expect(
      layers.firstWhere((dynamic l) => l['field'] == 'VENUE')['value'],
      '9th & Jackson',
    );
  });

  testWidgets('placeholder mode is an explicit choice, never a silent default', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await boot(
      tester,
      statuses: <dynamic>[ready(slides: 1)],
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('flyer-deck-name')),
      'app-flyer-one',
    );
    await tester.tap(find.byKey(const ValueKey<String>('flyer-placeholders')));
    await tester.pump();
    await confirmAndRender(tester);

    expect(backend.posts.single['on_missing_field'], 'placeholder');
    expect(
      (backend.posts.single['slides'] as List<dynamic>).single['text_layers'],
      isEmpty,
    );
  });

  testWidgets('the render-job states each read honestly', (
    WidgetTester tester,
  ) async {
    await boot(
      tester,
      statuses: <dynamic>[
        <String, dynamic>{'id': 'flyer-test-1', 'status': 'rendering'},
        ready(slides: 3),
      ],
    );
    await fillHook(tester);
    await confirmAndRender(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('flyer-job-flyer-test-1')),
        matching: find.text('app-flyer-one'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('3 slides in order'),
      findsOneWidget,
      reason: 'a ready carousel states how many ordered slides it produced',
    );
    expect(find.textContaining('nothing published'), findsOneWidget);
    expect(messageText(tester), contains('Rendering finished'));
  });

  testWidgets('an unreachable render host is stated, not hidden', (
    WidgetTester tester,
  ) async {
    await boot(tester, rendererReachable: false);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('flyer-renderer-status')),
          )
          .data,
      contains('is not answering'),
    );
  });

  testWidgets('a failed render shows the reason and offers no result', (
    WidgetTester tester,
  ) async {
    await boot(
      tester,
      statuses: <dynamic>[
        <String, dynamic>{
          'id': 'flyer-test-1',
          'status': 'failed',
          'error':
              'The 3060 render host (192.168.1.74) is not answering, so this '
              'flyer was not rendered.',
          'renderer_unavailable': true,
        },
      ],
    );
    await fillHook(tester);
    await confirmAndRender(tester);

    expect(find.textContaining('is not answering'), findsWidgets);
    expect(find.textContaining('was not rendered'), findsOneWidget);
    expect(find.textContaining('Ready for review'), findsNothing);
  });

  testWidgets('a lost receipt stops polling instead of spinning', (
    WidgetTester tester,
  ) async {
    await boot(
      tester,
      statuses: <dynamic>[
        <String, dynamic>{'id': 'flyer-test-1', 'status': 'unknown'},
      ],
    );
    await fillHook(tester);
    await confirmAndRender(tester);

    expect(find.textContaining('no longer has this receipt'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('flyer-check-status')),
      findsNothing,
      reason: 'nothing is left pending, so there is nothing to re-check',
    );
  });

  testWidgets('reordering a slide carries its typed text with it', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await boot(
      tester,
      statuses: <dynamic>[ready(slides: 2)],
    );
    await fillHook(tester);
    await tester.tap(find.byKey(const ValueKey<String>('flyer-add-cta')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('flyer-slide-1-CTA')),
      'Tickets at link in bio',
    );
    await tester.pump();

    await tester.tap(find.byIcon(CupertinoIcons.arrow_up).last);
    await tester.pumpAndSettle();
    await confirmAndRender(tester);

    final List<dynamic> slides =
        backend.posts.single['slides'] as List<dynamic>;
    expect(slides.map((dynamic s) => s['role']).toList(), <String>[
      'cta',
      'hook',
    ]);
    expect(slides.first['index'], 0);
    expect(
      (slides.first['text_layers'] as List<dynamic>).single['value'],
      'Tickets at link in bio',
    );
  });

  testWidgets('the unimplemented Energy Photo template is not offered', (
    WidgetTester tester,
  ) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey<String>('flyer-template')));
    await tester.pumpAndSettle();
    expect(find.text('HUD Ticket'), findsWidgets);
    expect(find.textContaining('Energy'), findsNothing);
    expect(find.textContaining('Photo'), findsNothing);
  });

  testWidgets('the screen offers no way to publish, schedule or approve', (
    WidgetTester tester,
  ) async {
    await boot(tester, statuses: <dynamic>[ready(slides: 2)]);
    await fillHook(tester);
    await confirmAndRender(tester);
    for (final String forbidden in <String>[
      'Post',
      'Publish',
      'Approve',
      'Schedule',
    ]) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: '"$forbidden" must not exist on a review-only surface',
      );
    }
    expect(find.textContaining('review-only'), findsWidgets);
  });
}
