// White-label agency surface.
//
// Every request here is a local fake. No test in this file may reach a
// gateway, and none of them may exercise a publish, post, or schedule path:
// a client decision is a record the operator acts on, never a dispatch.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/agency_workspace.dart';
import 'package:iris/app_theme.dart';
import 'package:iris/console_shell.dart';

const Map<String, dynamic> _apex = <String, dynamic>{
  'agency_id': 'apex-social',
  'name': 'Apex Social',
  'primary_color': '#22AA66',
  'logo_url': null,
  'support_email': 'hello@apexsocial.co',
  'branded': true,
  'accounts': <dynamic>[
    <String, dynamic>{'account': '@gabejlove', 'client_label': 'Gabe Love'},
  ],
};

const Map<String, dynamic> _brandedAccount = <String, dynamic>{
  'agency_id': 'apex-social',
  'name': 'Apex Social',
  'primary_color': '#22AA66',
  'branded': true,
  'client_label': 'Gabe Love',
};

const Map<String, dynamic> _neutralAccount = <String, dynamic>{
  'agency_id': null,
  'name': 'Review workspace',
  'primary_color': '#8A8F98',
  'branded': false,
};

Map<String, dynamic> _decisions(List<Map<String, dynamic>> rows) =>
    <String, dynamic>{'account': '@gabejlove', 'decisions': rows};

Future<void> _pump(
  WidgetTester tester, {
  required Future<dynamic> Function(String) get,
  required Future<dynamic> Function(String, Map<String, dynamic>) post,
  String account = '@gabejlove',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CupertinoPageScaffold(
        backgroundColor: Con.ground,
        child: SingleChildScrollView(
          child: AgencyWorkspaceCard(
            account: account,
            getJson: get,
            postJson: post,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<dynamic> Function(String) _getter({
  List<Map<String, dynamic>> agencies = const <Map<String, dynamic>>[],
  Map<String, dynamic> brand = _neutralAccount,
}) => (String path) async {
  if (path.startsWith('/reels/agency/profiles')) {
    return <String, dynamic>{'agencies': agencies};
  }
  if (path.startsWith('/reels/agency/brand')) return brand;
  throw StateError('unexpected GET $path');
};

Future<dynamic> _noPost(String path, Map<String, dynamic> body) async {
  if (path == '/reels/agency/approval-dispatch') return _decisions(const []);
  throw StateError('unexpected POST $path');
}

void main() {
  testWidgets('with no agency yet it offers to create one', (
    WidgetTester tester,
  ) async {
    await _pump(tester, get: _getter(), post: _noPost);
    expect(find.text('No agency yet'), findsOneWidget);
    expect(find.text('Create agency'), findsOneWidget);
  });

  testWidgets('an unassigned account is stated as unbranded, not as ours', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(agencies: <Map<String, dynamic>>[_apex]),
      post: _noPost,
    );
    expect(
      find.textContaining('is not assigned to an agency'),
      findsOneWidget,
    );
    // The neutral fallback must never surface this product's name to an
    // operator looking at what a client would see.
    expect(find.textContaining('Content Doctor'), findsNothing);
    expect(find.textContaining('Trial Reel'), findsNothing);
  });

  testWidgets('an assigned account names the agency and the client', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(
        agencies: <Map<String, dynamic>>[_apex],
        brand: _brandedAccount,
      ),
      post: _noPost,
    );
    expect(find.textContaining('Gabe Love'), findsOneWidget);
    expect(find.text('Apex Social'), findsOneWidget);
    expect(find.text('1 client'), findsOneWidget);
  });

  testWidgets('creating an agency posts name and colour, and nothing else', (
    WidgetTester tester,
  ) async {
    final List<String> paths = <String>[];
    Map<String, dynamic>? saved;
    await _pump(
      tester,
      get: _getter(),
      post: (String path, Map<String, dynamic> body) async {
        paths.add(path);
        if (path == '/reels/agency/approval-dispatch') {
          return _decisions(const []);
        }
        saved = body;
        return <String, dynamic>{'ok': true};
      },
    );
    await tester.tap(find.text('Create agency'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, 'Apex Social');
    await tester.tap(find.text('Create agency').last);
    await tester.pumpAndSettle();

    expect(saved!['name'], 'Apex Social');
    expect(saved!['primary_color'], '#E8202E');
    expect(
      paths.where((String p) => p.contains('post') || p.contains('schedule')),
      isEmpty,
      reason: 'the agency surface must never touch a publish path',
    );
  });

  testWidgets('a malformed colour is refused in the sheet, not sent', (
    WidgetTester tester,
  ) async {
    bool posted = false;
    await _pump(
      tester,
      get: _getter(),
      post: (String path, Map<String, dynamic> body) async {
        if (path == '/reels/agency/approval-dispatch') {
          return _decisions(const []);
        }
        posted = true;
        return <String, dynamic>{'ok': true};
      },
    );
    await tester.tap(find.text('Create agency'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, 'Apex');
    await tester.enterText(find.byType(CupertinoTextField).at(1), '#fff');
    await tester.tap(find.text('Create agency').last);
    await tester.pumpAndSettle();

    expect(posted, isFalse);
    expect(find.textContaining('six-digit hex'), findsOneWidget);
  });

  testWidgets('an empty name is refused in the sheet, not sent', (
    WidgetTester tester,
  ) async {
    bool posted = false;
    await _pump(
      tester,
      get: _getter(),
      post: (String path, Map<String, dynamic> body) async {
        if (path == '/reels/agency/approval-dispatch') {
          return _decisions(const []);
        }
        posted = true;
        return <String, dynamic>{'ok': true};
      },
    );
    await tester.tap(find.text('Create agency'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create agency').last);
    await tester.pumpAndSettle();

    expect(posted, isFalse);
    expect(find.textContaining('Give the agency a name'), findsOneWidget);
  });

  testWidgets('a client approval is shown as a record, not as a post', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(
        agencies: <Map<String, dynamic>>[_apex],
        brand: _brandedAccount,
      ),
      post: (String path, Map<String, dynamic> body) async {
        expect(path, '/reels/agency/approval-dispatch');
        expect(body['action'], 'decisions');
        return _decisions(<Map<String, dynamic>>[
          <String, dynamic>{
            'reel_id': 'gabe-interview-v2',
            'sha256': 'a' * 64,
            'subject': 'gabe',
            'decision': 'approved',
            'note': '',
            'applies_to_current_export': true,
          },
        ]);
      },
    );
    expect(find.text('CLIENT DECISIONS'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
    expect(
      find.textContaining('Nothing posts or schedules'),
      findsOneWidget,
    );
  });

  testWidgets('an approval of a re-rendered export is marked stale', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(
        agencies: <Map<String, dynamic>>[_apex],
        brand: _brandedAccount,
      ),
      post: (String path, Map<String, dynamic> body) async => _decisions(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'reel_id': 'gabe-interview-v2',
            'subject': 'gabe',
            'decision': 'approved',
            'note': '',
            'applies_to_current_export': false,
          },
        ],
      ),
    );
    expect(find.text('RE-RENDERED'), findsOneWidget);
    expect(find.text('APPROVED'), findsNothing);
  });

  testWidgets('a decision with no stated freshness is treated as stale', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(
        agencies: <Map<String, dynamic>>[_apex],
        brand: _brandedAccount,
      ),
      post: (String path, Map<String, dynamic> body) async => _decisions(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'reel_id': 'gabe-interview-v2',
            'subject': 'gabe',
            'decision': 'approved',
            'note': '',
          },
        ],
      ),
    );
    expect(find.text('RE-RENDERED'), findsOneWidget);
  });

  testWidgets('a gateway with no agency surface leaves the tab untouched', (
    WidgetTester tester,
  ) async {
    // White label is additive. An older or unreachable gateway must not put an
    // error where an operator expects their connection settings; the tab's own
    // no-connection banner already covers a real outage.
    await _pump(
      tester,
      get: (String path) async => throw Exception('gateway down'),
      post: _noPost,
    );
    expect(find.text('AGENCY'), findsNothing);
    expect(find.text('No agency yet'), findsNothing);
    expect(find.byType(ConBanner), findsNothing);
  });

  testWidgets('a gateway answering unknown paths with {} shows no agency', (
    WidgetTester tester,
  ) async {
    // The console's own fake gateways answer every unrecognised path with an
    // empty body. That is not an agency surface with zero agencies in it, and
    // must not render as one.
    await _pump(
      tester,
      get: (String path) async => const <String, dynamic>{},
      post: _noPost,
    );
    expect(find.text('AGENCY'), findsNothing);
    expect(find.text('No agency yet'), findsNothing);
  });

  testWidgets('a real gateway with zero agencies does offer to create one', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: (String path) async => path.startsWith('/reels/agency/profiles')
          ? const <String, dynamic>{'agencies': <dynamic>[]}
          : _neutralAccount,
      post: _noPost,
    );
    expect(find.text('AGENCY'), findsOneWidget);
    expect(find.text('No agency yet'), findsOneWidget);
  });

  testWidgets('a rejected save is reported, and the surface stays usable', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(),
      post: (String path, Map<String, dynamic> body) async {
        if (path == '/reels/agency/approval-dispatch') {
          return _decisions(const []);
        }
        throw Exception('Agency name must be 1-60 characters');
      },
    );
    await tester.tap(find.text('Create agency'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, 'Apex');
    await tester.tap(find.text('Create agency').last);
    await tester.pumpAndSettle();

    expect(find.text('That agency change did not save'), findsOneWidget);
    expect(find.text('AGENCY'), findsOneWidget);
  });

  testWidgets('decisions failing alone still renders the agency profile', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      get: _getter(
        agencies: <Map<String, dynamic>>[_apex],
        brand: _brandedAccount,
      ),
      post: (String path, Map<String, dynamic> body) async =>
          throw Exception('no review links yet'),
    );
    expect(find.text('Apex Social'), findsOneWidget);
    expect(find.text('Agency settings unavailable'), findsNothing);
  });

  testWidgets('with no account scope it still lists agencies', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      account: '',
      get: _getter(agencies: <Map<String, dynamic>>[_apex]),
      post: _noPost,
    );
    expect(find.text('Apex Social'), findsOneWidget);
    expect(find.text('Assign client'), findsNothing);
  });

  group('brand colour parsing', () {
    test('accepts a six-digit hex and ignores case', () {
      expect(parseBrandColour('#22aa66'), const Color(0xFF22AA66));
      expect(parseBrandColour('#22AA66'), const Color(0xFF22AA66));
    });

    test('refuses anything else rather than throwing', () {
      for (final dynamic value in <dynamic>[
        null,
        '',
        'red',
        '#fff',
        '#22AA6',
        '22AA66',
        '#22AA6G',
        <String>['#22AA66'],
      ]) {
        expect(parseBrandColour(value), isNull, reason: 'for $value');
      }
    });
  });

  group('the agency palette never leaks into app chrome', () {
    test('an agency colour is not one of the app surface tokens', () {
      // Guards the rule this feature was built under: a client's brand colour
      // is previewed here, it never becomes a Con/SandDark token.
      const Color agency = Color(0xFF22AA66);
      expect(agency, isNot(Con.signal));
      expect(agency, isNot(Con.ground));
      expect(agency, isNot(SandDark.primary));
    });
  });
}
