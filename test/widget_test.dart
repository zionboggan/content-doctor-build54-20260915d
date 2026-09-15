import 'package:iris/main.dart';
import 'package:iris/native_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The production shell is fully native; pure helpers below lock down role scope.

void main() {
  test('display choices never change owner and Gabe account scope', () {
    final accounts = <Map<String, dynamic>>[
      for (final name in <String>[
        '@zionboggan',
        '@barcrawls.arizona',
        '@barcrawling',
        '@gabejlove',
      ])
        <String, dynamic>{'account': name},
    ];
    final source = TrialSnapshot(
      reels: 4,
      accounts: 4,
      schedules: 4,
      accountStatus: accounts,
      catalogItems: <Map<String, dynamic>>[
        for (final row in accounts)
          <String, dynamic>{...row, 'id': row['account']},
      ],
      scheduleItems: <Map<String, dynamic>>[
        for (final row in accounts)
          <String, dynamic>{...row, 'id': row['account']},
      ],
      revisionStatus: const <String, dynamic>{},
    );

    expect(scopeSnapshotForRole(source, 'owner').accounts, 4);
    final gabe = scopeSnapshotForRole(source, 'gabe');
    expect(gabe.accounts, 2);
    expect(
      gabe.accountStatus.any((row) => row['account'] == '@zionboggan'),
      isFalse,
    );
  });

  test(
    'favorites use explicit owner ratings across statuses and stay account scoped',
    () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 'rated',
          'account': '@zionboggan',
          'owner_rating': 4,
          'status': 'changes_requested',
        },
        {
          'id': 'inferred',
          'account': '@zionboggan',
          'feedback': {'liked': true},
        },
        {'id': 'low', 'account': '@zionboggan', 'owner_rating': 3},
        {'id': 'other', 'account': '@barcrawling', 'owner_rating': 5},
      ];
      expect(
        positiveRatedReels(rows, {'@zionboggan'}).map((item) => item['id']),
        ['rated'],
      );
      expect(positiveRatedReels(rows, {'all'}), hasLength(2));
      expect(rows.any((item) => item.containsKey('approval')), isFalse);
    },
  );

  test('only cancelled and invalidated intents can be replaced', () {
    expect(reelCanReceiveNewIntent({}), isTrue);
    for (final state in ['cancelled', 'invalidated']) {
      expect(
        reelCanReceiveNewIntent({
          'approval': {'state': state},
        }),
        isTrue,
      );
    }
    for (final state in [
      'scheduled',
      'paused',
      'publishing',
      'published',
      'needs_attention',
      'failed',
      'unknown',
    ]) {
      expect(
        reelCanReceiveNewIntent({
          'approval': {'state': state},
        }),
        isFalse,
      );
    }
  });

  test(
    'approved music response parses assets and preserves no-music state',
    () {
      final List<Map<String, dynamic>> assets = parseMusicAssets(
        <String, dynamic>{
          'assets': <dynamic>[
            <String, dynamic>{
              'id': 'larp-one',
              'label': 'Approved cue',
              'approved': true,
            },
            <String, dynamic>{
              'id': 'blocked',
              'label': 'Blocked cue',
              'approved': false,
            },
          ],
        },
      );
      expect(assets.single['id'], 'larp-one');
      expect(
        parseMusicAssets(<String, dynamic>{'assets': <dynamic>[]}),
        isEmpty,
      );
    },
  );

  test('live response shapes parse catalog list and schedule entries', () {
    final TrialSnapshot snapshot = TrialSnapshot.fromResponses(
      <dynamic>[
        <String, dynamic>{'id': 'one'},
        <String, dynamic>{'id': 'two'},
      ],
      <String, dynamic>{
        'accounts': <String, dynamic>{
          '@zionboggan': <String, dynamic>{'enabled': true},
        },
      },
      <String, dynamic>{
        'entries': <dynamic>[
          <String, dynamic>{'id': 'scheduled'},
        ],
        'controls': <String, dynamic>{},
      },
    );
    expect(snapshot.reels, 2);
    expect(snapshot.accounts, 1);
    expect(snapshot.schedules, 1);
  });

  group('Trial launch migration', () {
    test('old Console and index paths load Trial on the same origin', () {
      for (final String host in knownHosts.map((GatewayHost h) => h.url)) {
        for (final String suffix in <String>[
          '',
          '/',
          '/console',
          '/console/',
          '/console.html',
          '/index.html',
          '/trial.html',
        ]) {
          expect(
            trialEntryUri('$host$suffix').toString(),
            '$host/trial.html?native=13',
          );
          expect(trialGatewayHost('$host$suffix'), host);
        }
      }
    });

    test('custom reverse proxy prefixes and network ports survive', () {
      expect(
        trialEntryUri('https://custom.test:8443/team/index.html').toString(),
        'https://custom.test:8443/team/trial.html?native=13',
      );
      expect(
        trialEntryUri('http://10.1.1.2:8105/team/').toString(),
        'http://10.1.1.2:8105/team/trial.html?native=13',
      );
    });

    test(
      'stale query and fragment are not forwarded; migration is idempotent',
      () {
        const String old = 'http://192.0.2.15:8105/console?old=value#session';
        final String migrated = trialGatewayHost(old);
        expect(trialGatewayHost(migrated), migrated);
        expect(
          trialEntryUri(old).toString(),
          'http://192.0.2.15:8105/trial.html?native=13',
        );
        expect(
          trialEntryUri('invalid://host').toString(),
          '$defaultHost/trial.html?native=13',
        );
      },
    );
  });

  group('normalizeHost', () {
    test('assumes plain HTTP for a bare address', () {
      expect(normalizeHost('192.0.2.15:8105'), 'http://192.0.2.15:8105');
    });

    test('keeps an explicit scheme and port', () {
      expect(
        normalizeHost('https://gateway.example.invalid:8445'),
        'https://gateway.example.invalid:8445',
      );
    });

    test('trims surrounding space and trailing slashes', () {
      expect(
        normalizeHost('  http://10.0.0.2:8105/  '),
        'http://10.0.0.2:8105',
      );
    });

    test('drops a port that is the default for the scheme', () {
      expect(normalizeHost('http://10.0.0.2:80'), 'http://10.0.0.2');
      expect(normalizeHost('https://example.test:443'), 'https://example.test');
    });

    test('rejects empty and non-web input', () {
      expect(normalizeHost(''), isNull);
      expect(normalizeHost('   '), isNull);
      expect(normalizeHost('ftp://192.0.2.15'), isNull);
    });
  });

  test('the default host is a secure origin', () {
    // Push to talk depends on this: an insecure origin gives the web client no
    // navigator.mediaDevices at all, whatever the WebView permits.
    expect(defaultHost.startsWith('https://'), isTrue);
    expect(knownHostFor(defaultHost)?.secure, isTrue);
  });

  testWidgets('the error view names the host it tried', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewayErrorView(
            host: 'http://192.0.2.15:8105',
            reason: 'Connection refused.',
            onRetry: () {},
            onSwitchHost: () {},
          ),
        ),
      ),
    );

    expect(find.text('http://192.0.2.15:8105'), findsOneWidget);
    expect(find.text('Connection refused.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Switch host'), findsOneWidget);
  });

  testWidgets('retry and switch host are wired', (WidgetTester tester) async {
    var retried = 0;
    var switched = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewayErrorView(
            host: 'http://192.0.2.15:8105',
            reason: '',
            onRetry: () => retried++,
            onSwitchHost: () => switched++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Try again'));
    await tester.tap(find.text('Switch host'));
    await tester.pump();

    expect(retried, 1);
    expect(switched, 1);
  });

  testWidgets('the host sheet offers every known host and pops the choice', (
    WidgetTester tester,
  ) async {
    String? popped;

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
            builder: (BuildContext context) => Scaffold(
              body: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<String>(
                      context: context,
                      builder: (_) =>
                          const HostSheet(current: 'http://192.0.2.15:8105'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final GatewayHost host in knownHosts) {
      expect(find.text(host.label), findsOneWidget);
    }

    await tester.tap(find.text(knownHosts.first.label));
    await tester.pumpAndSettle();

    expect(popped, knownHosts.first.url);
  });

  testWidgets('choosing the host already in use pops nothing', (
    WidgetTester tester,
  ) async {
    String? popped = 'sentinel';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await showModalBottomSheet<String>(
                  context: context,
                  builder: (_) => HostSheet(current: knownHosts.first.url),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(knownHosts.first.label));
    await tester.pumpAndSettle();

    expect(popped, isNull);
  });
}
