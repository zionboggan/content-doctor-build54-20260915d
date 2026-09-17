import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/console_shell.dart';
import 'package:iris/inbox_automations.dart';

const Map<String, dynamic> _status = <String, dynamic>{
  'account': '@zionboggan',
  'local_conversations': 1,
  'local_unread_count': 1,
  'outbound_messaging_enabled': false,
  'review_only': true,
  'capability': <String, dynamic>{
    'state': 'ready',
    'reason':
        'Messaging provider path is ready for inbound review. Replies remain disabled.',
  },
};

const Map<String, dynamic> _threads = <String, dynamic>{
  'account': '@zionboggan',
  'threads': <dynamic>[
    <String, dynamic>{
      'id': 'signed-conversation-1',
      'participant_label': 'Taylor',
      'last_message_at': '2026-09-13T10:00:00Z',
      'preview': 'Are there dates this weekend?',
      'unread_count': 1,
    },
  ],
};

Future<dynamic> _get(String path) async {
  if (path.contains('/status')) return _status;
  if (path.contains('/threads')) return _threads;
  if (path.contains('/suggestions')) {
    return const <String, dynamic>{
      'suggestions': <String>['What part are you working on right now?'],
      'review_only': true,
      'outbound_enabled': false,
    };
  }
  return const <String, dynamic>{'drafts': <dynamic>[]};
}

void main() {
  testWidgets('Inbox saves an account-scoped review draft, never a sent DM', (
    WidgetTester tester,
  ) async {
    Map<String, dynamic>? saved;
    Future<dynamic> post(String path, Map<String, dynamic> body) async {
      expect(path, '/reels/dms/drafts');
      saved = body;
      return const <String, dynamic>{
        'state': 'draft',
        'outbound_enabled': false,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: InboxPanel(
            account: '@zionboggan',
            getJson: _get,
            postJson: post,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Taylor'), findsOneWidget);
    expect(find.textContaining('Replies remain disabled.'), findsOneWidget);
    await tester.tap(find.text('Taylor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use follow-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(saved, <String, dynamic>{
      'account': '@zionboggan',
      'conversation_id': 'signed-conversation-1',
      'text': 'What part are you working on right now?',
      'source': 'manual',
    });
    expect(find.textContaining('sent'), findsNothing);

    // The save worked, so the control has to come back. _load() increments
    // the request counter the finally guard compares against, so `saving`
    // used to latch true and the button stayed disabled forever with nothing
    // on screen to say why.
    expect(find.text('Saving…'), findsNothing, reason: 'the save finished');
    expect(
      tester
          .widget<ConButton>(find.widgetWithText(ConButton, 'Save draft'))
          .onPressed,
      isNotNull,
      reason: 'Save draft is usable again after a successful save',
    );
  });

  testWidgets('DM sending requires explicit exact-text confirmation', (
    WidgetTester tester,
  ) async {
    final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
    bool completed = false;
    Future<dynamic> get(String path) async {
      if (path.contains('/status')) {
        return <String, dynamic>{
          ..._status,
          'outbound_messaging_enabled': true,
        };
      }
      if (path.contains('/threads')) return _threads;
      return <String, dynamic>{
        'drafts': <dynamic>[
          <String, dynamic>{
            'id': 'draft-1',
            'account': '@zionboggan',
            'conversation_id': 'signed-conversation-1',
            'text': 'Exact approved reply',
            'state': completed ? 'sent' : 'draft',
          },
        ],
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: InboxPanel(
            account: '@zionboggan',
            getJson: get,
            postJson: (String path, Map<String, dynamic> body) async {
              expect(path, '/reels/dms/send');
              sent.add(body);
              completed = true;
              return <String, dynamic>{'state': 'sent'};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review and send'));
    await tester.tap(find.text('Review and send'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.textContaining('From @zionboggan'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await tester.tap(find.text('Review and send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve and send'));
    await tester.pumpAndSettle();
    expect(sent, <Map<String, dynamic>>[
      <String, dynamic>{
        'account': '@zionboggan',
        'draft_id': 'draft-1',
        'conversation_id': 'signed-conversation-1',
        'text': 'Exact approved reply',
        'confirm': true,
      },
    ]);
    expect(find.text('Review and send'), findsNothing);
    expect(find.text('sent'), findsOneWidget);
  });

  testWidgets('Automations does not invent enabled rules or work hours', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: const Scaffold(
          body: AutomationsPanel(
            account: '@zionboggan',
            getJson: _get,
            postJson: _unusedPost,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Automatic replies are not active.'),
      findsOneWidget,
    );
    expect(find.text('Create review plan'), findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect(find.textContaining('nothing sends from this app.'), findsOneWidget);
  });
}

Future<dynamic> _unusedPost(String path, Map<String, dynamic> body) async =>
    const <String, dynamic>{};
