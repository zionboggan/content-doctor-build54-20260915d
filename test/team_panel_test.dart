// Team panel: the state a message shows is the state the queue holds.
//
// The one thing this screen must never do is make an unclaimed message look
// delivered, so that is what this test pins. It uses stub transports, so it
// exercises the panel and not the network.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/team_page.dart';

const Map<String, dynamic> _threads = <String, dynamic>{
  'account': '@zionboggan',
  'accounts': <String>['@zionboggan'],
  'role': 'owner',
  'chief_thread_id': 'bot-chief-operator::@zionboggan',
  'threads': <dynamic>[
    <String, dynamic>{
      'thread_id': 'bot-chief-operator::@zionboggan',
      'bot_id': 'bot-chief-operator',
      'role_title': 'Chief Operator',
      'account': '@zionboggan',
      'scope_kind': 'all_accounts',
      'is_chief': true,
      'message_count': 2,
      'reply_count': 1,
      'open_count': 1,
      'last_at': '2026-09-12T12:36:45.000000Z',
      'last_state': 'queued',
      'last_delivery': 'queued',
      'last_preview': 'Give me the queue picture',
    },
  ],
};

const Map<String, dynamic> _thread = <String, dynamic>{
  'thread_id': 'bot-chief-operator::@zionboggan',
  'bot_id': 'bot-chief-operator',
  'role_title': 'Chief Operator',
  'account': '@zionboggan',
  'scope_kind': 'all_accounts',
  'is_chief': true,
  'message_count': 2,
  'messages': <dynamic>[
    <String, dynamic>{
      'kind': 'message',
      'job_id': 'aq-one',
      'text': 'First question',
      'from_actor': 'Zion',
      'from_role': 'owner',
      'at': '2026-09-12T12:36:45.000000Z',
      'updated_at': '2026-09-12T12:37:04.000000Z',
      'state': 'review_ready',
      'delivery': 'replied',
      'delivery_detail': 'Replied.',
      'claimed_by': 'trialreels-operator',
      'retry_count': 0,
      'reply_count': 1,
      'replies': <dynamic>[
        <String, dynamic>{
          'kind': 'reply',
          'receipt_id': 'aqr-proof-one',
          'job_id': 'aq-one',
          'bot': 'trialreels-operator',
          'outcome': 'review_ready',
          'action': 'submit-review-proposal',
          'text': 'Two queued, one claimed, five complete.',
          'at': '2026-09-12T12:37:04.000000Z',
        },
      ],
    },
    <String, dynamic>{
      'kind': 'message',
      'job_id': 'aq-two',
      'text': 'Second question, nobody has taken it',
      'from_actor': 'Zion',
      'from_role': 'owner',
      'at': '2026-09-12T12:38:00.000000Z',
      'updated_at': '2026-09-12T12:38:00.000000Z',
      'state': 'queued',
      'delivery': 'queued',
      'delivery_detail': 'Queued. No Bot has picked it up.',
      'claimed_by': null,
      'retry_count': 0,
      'reply_count': 0,
      'replies': <dynamic>[],
    },
  ],
};

Future<dynamic> _get(String path) async =>
    path.startsWith('/reels/team/threads') ? _threads : _thread;

Future<dynamic> _post(String path, Map<String, dynamic> body) async =>
    <String, dynamic>{'thread_id': body['bot_id']};

void main() {
  testWidgets(
    'composer scrolls with a keyboard and clears when leaving a thread',
    (tester) async {
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: TeamPanel(
              account: '@zionboggan',
              getJson: _get,
              postJson: _post,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chief Operator'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CupertinoTextField),
        'Only for this conversation',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chief Operator'));
      await tester.pumpAndSettle();
      expect(find.text('Only for this conversation'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty conversation fits a narrow phone with large text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<dynamic> get(String path) async =>
        path.startsWith('/reels/team/threads')
        ? _threads
        : <String, dynamic>{..._thread, 'messages': <dynamic>[]};
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
          body: TeamPanel(
            account: '@zionboggan',
            getJson: get,
            postJson: _post,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chief Operator'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing sent yet'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching accounts ignores an older roster response', (
    tester,
  ) async {
    final oldResponse = Completer<dynamic>();
    Future<dynamic> get(String path) async {
      if (path.contains('zionboggan')) return oldResponse.future;
      return <String, dynamic>{
        ..._threads,
        'account': '@barcrawling',
        'threads': <dynamic>[],
      };
    }

    Widget panel(String account) => MaterialApp(
      theme: studioTheme(),
      home: Scaffold(
        body: TeamPanel(account: account, getJson: get, postJson: _post),
      ),
    );
    await tester.pumpWidget(panel('@zionboggan'));
    await tester.pumpWidget(panel('@barcrawling'));
    await tester.pumpAndSettle();
    oldResponse.complete(_threads);
    await tester.pumpAndSettle();
    expect(find.text('No Bots on this account'), findsOneWidget);
    expect(find.text('Chief Operator'), findsNothing);
  });

  testWidgets('an unclaimed message reads as unclaimed, not as delivered', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: const Scaffold(
          body: TeamPanel(
            account: '@zionboggan',
            getJson: _get,
            postJson: _post,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The roster lists the Bot and says how many of its jobs are still open.
    expect(find.text('Chief Operator'), findsOneWidget);
    expect(find.text('1 open'), findsOneWidget);

    await tester.tap(find.text('Chief Operator'));
    await tester.pumpAndSettle();

    // The thread never claims delivery it does not have.
    expect(find.text('Queued — not picked up yet'), findsOneWidget);

    // The queued message says so in full, and carries no reply.
    expect(find.text('Queued — not picked up yet'), findsOneWidget);
    expect(find.text('Second question, nobody has taken it'), findsOneWidget);

    // The answered message carries the Bot text and the receipt it came from.
    expect(
      find.text('Two queued, one claimed, five complete.'),
      findsOneWidget,
    );
    expect(find.text('Receipt aqr-proof-one'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt aqr-proof-one'), findsOneWidget);
    expect(find.textContaining('Replied.'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the compact Crew roster is backed by queue state, not simulated presence',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: const Scaffold(
            body: TeamPanel(
              account: '@zionboggan',
              getJson: _get,
              postJson: _post,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The card takes its label from last_delivery. It never substitutes an
      // online/typing claim that the queue did not return.
      expect(find.text('Give me the queue picture'), findsOneWidget);
      expect(find.text('1 open'), findsOneWidget);
      expect(find.text('On schedule'), findsNothing);
      expect(find.text('Typing'), findsNothing);
      expect(
        find.text(
          'Ask your crew a question or give them a task. Tasks here do not '
          'post content.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Chief Operator'));
      await tester.pumpAndSettle();
      expect(find.text('Queued — not picked up yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the roster keeps machine detail in the thread, not the card', (
    WidgetTester tester,
  ) async {
    Future<dynamic> get(String path) async =>
        path.startsWith('/reels/team/threads')
        ? <String, dynamic>{
            ..._threads,
            'threads': <dynamic>[
              <String, dynamic>{
                ...Map<String, dynamic>.from(
                  (_threads['threads'] as List<dynamic>).first as Map,
                ),
                'last_preview':
                    'Implementation check requested by Zion: '
                    'inspect the current cached account context for '
                    '@zionboggan. In one to three plain sentences.',
              },
            ],
          }
        : _thread;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: TeamPanel(
            account: '@zionboggan',
            getJson: get,
            postJson: _post,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open conversation for the full update.'), findsOneWidget);
    expect(find.textContaining('cached account context'), findsNothing);
    expect(find.text('1 open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('send submits once and immediately refreshes the open thread', (
    WidgetTester tester,
  ) async {
    int sends = 0;
    int threadReads = 0;
    final Completer<dynamic> sent = Completer<dynamic>();
    Future<dynamic> get(String path) async {
      if (path.startsWith('/reels/team/threads')) return _threads;
      threadReads++;
      return _thread;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: TeamPanel(
            account: '@zionboggan',
            getJson: get,
            postJson: (String path, Map<String, dynamic> body) async {
              sends++;
              return sent.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chief Operator'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'Check this');
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.tap(find.text('Sending'));
    sent.complete(<String, dynamic>{'ok': true});
    await tester.pumpAndSettle();

    expect(sends, 1);
    expect(threadReads, 2);
    expect(find.text('Check this'), findsNothing);
  });

  testWidgets('long replies collapse cleanly and machine evidence is hidden', (
    WidgetTester tester,
  ) async {
    final String longReply =
        '${List<String>.filled(12, 'The review is ready for your decision. ').join()}'
        'Evidence: {reel_id: internal-review, scheduled_at: never}';
    final Map<String, dynamic> replyMessage =
        Map<String, dynamic>.from(
            (_thread['messages'] as List<dynamic>)[0] as Map,
          )
          ..['replies'] = <dynamic>[
            <String, dynamic>{
              'receipt_id': 'long-reply',
              'text': longReply,
              'at': '2026-09-12T12:37:04.000000Z',
            },
          ];
    Future<dynamic> get(String path) async =>
        path.startsWith('/reels/team/threads')
        ? _threads
        : <String, dynamic>{
            ..._thread,
            'messages': <dynamic>[replyMessage],
          };
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: TeamPanel(
            account: '@zionboggan',
            getJson: get,
            postJson: _post,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chief Operator'));
    await tester.pumpAndSettle();
    expect(find.text('Read full update'), findsOneWidget);
    expect(find.textContaining('reel_id:'), findsNothing);
    await tester.tap(find.text('Read full update'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
