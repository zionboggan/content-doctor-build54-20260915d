// Local visual handoff captures. All data is synthetic and no provider route,
// credential, or network resource is used by this test.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/console_shell.dart';
import 'package:iris/native_results.dart';
import 'package:iris/team_page.dart';

const Size _phone = Size(390, 844);

const List<Map<String, dynamic>> _catalog = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'visual-1',
    'account': '@test_only',
    'title': 'A real results title that stays readable on a phone',
  },
  <String, dynamic>{
    'id': 'visual-2',
    'account': '@test_only',
    'title': 'Founder systems: a compact test reel',
  },
  <String, dynamic>{
    'id': 'visual-3',
    'account': '@test_only',
    'title': 'The day the agents ran the whole queue',
  },
  <String, dynamic>{
    'id': 'visual-4',
    'account': '@test_only',
    'title': 'A fourth synthetic reel remains disclosed',
  },
];

const Map<String, dynamic> _roster = <String, dynamic>{
  'account': '@test_only',
  'threads': <Map<String, dynamic>>[
    <String, dynamic>{
      'thread_id': 'visual-chief',
      'role_title': 'Chief Operator',
      'message_count': 3,
      'open_count': 1,
      'last_delivery': 'queued',
      'last_preview': 'One review needs a human decision before it moves.',
    },
    <String, dynamic>{
      'thread_id': 'visual-editor',
      'role_title': 'Video Editor',
      'message_count': 2,
      'open_count': 0,
      'last_delivery': 'working',
      'last_preview': 'A phone-safe edit is ready for a factual review.',
    },
    <String, dynamic>{
      'thread_id': 'visual-analytics',
      'role_title': 'Analytics Scientist',
      'message_count': 1,
      'open_count': 1,
      'last_delivery': 'needs_input',
      'last_preview': 'The comparison window needs one selected baseline.',
    },
    <String, dynamic>{
      'thread_id': 'visual-library',
      'role_title': 'Media Librarian',
      'message_count': 0,
      'open_count': 0,
      'last_delivery': '',
      'last_preview': '',
    },
  ],
};

Future<dynamic> _crewGet(String path) async => _roster;

Future<dynamic> _crewPost(String path, Map<String, dynamic> body) async =>
    <String, dynamic>{'ok': true};

Future<void> _loadVisualFonts() async {
  // Widget tests do not load app fonts by default. Loading the bundled Inter
  // face keeps labels and line wrapping representative of the phone app.
  final FontLoader inter = FontLoader('Inter');
  inter.addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
  final FontLoader jetBrainsMono = FontLoader('JetBrains Mono');
  jetBrainsMono.addFont(
    rootBundle.load('assets/fonts/JetBrainsMono-Variable.ttf'),
  );
  final FontLoader material = FontLoader('MaterialIcons');
  material.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  final FontLoader cupertino = FontLoader(
    'packages/cupertino_icons/CupertinoIcons',
  );
  cupertino.addFont(
    rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
  );
  await Future.wait<void>(<Future<void>>[
    inter.load(),
    jetBrainsMono.load(),
    material.load(),
    cupertino.load(),
  ]);
}

Widget _frame({required Widget child, required double textScale}) =>
    MaterialApp(
      theme: studioTheme(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: _phone,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey<String>('visual-handoff-frame'),
            child: child,
          ),
        ),
      ),
    );

Widget _results({required double textScale}) => _frame(
  textScale: textScale,
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: NativeResults(
      base: 'http://visual.test',
      selectedAccounts: const <String>{'@test_only'},
      catalog: _catalog,
      accountStatus: const <Map<String, dynamic>>[],
      load: () async => <String, dynamic>{
        'observed_at': '2026-09-13T16:37:04.579421Z',
        'records': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'visual-1',
            'account': '@test_only',
            'state': 'observed',
            'metrics': <String, dynamic>{
              'views': 12023,
              'reach': 8400,
              'shares': 224,
              'saved': 9,
              'total_interactions': 416,
            },
            'media_fields': <String, dynamic>{
              'like_count': 176,
              'comments_count': 7,
              'timestamp': '2026-09-12T20:00:00Z',
            },
          },
          <String, dynamic>{
            'id': 'visual-2',
            'account': '@test_only',
            'state': 'observed',
            'metrics': <String, dynamic>{
              'views': 8448,
              'reach': 7785,
              'shares': 113,
              'saved': 4,
              'total_interactions': 369,
            },
            'media_fields': <String, dynamic>{
              'like_count': 245,
              'comments_count': 5,
              'timestamp': '2026-09-11T20:00:00Z',
            },
          },
          <String, dynamic>{
            'id': 'visual-3',
            'account': '@test_only',
            'state': 'observed',
            'metrics': <String, dynamic>{
              'views': 7785,
              'reach': 6543,
              'total_interactions': 251,
            },
            'media_fields': <String, dynamic>{'like_count': 134},
          },
          <String, dynamic>{
            'id': 'visual-4',
            'account': '@test_only',
            'state': 'pending',
          },
        ],
      },
      connect: (_) {},
      preview: (_) {},
    ),
  ),
);

Widget _crew({required double textScale}) => _frame(
  textScale: textScale,
  child: TeamPanel(
    account: '@test_only',
    getJson: _crewGet,
    postJson: _crewPost,
  ),
);

Future<void> _capture(WidgetTester tester, Widget widget, String golden) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  // A roster is loaded after the initial frame. Capture its settled state,
  // not the first 0%-opacity frame of its intentional card entrance.
  await tester.pump(const Duration(milliseconds: 800));
  await expectLater(
    find.byKey(const ValueKey<String>('visual-handoff-frame')),
    matchesGoldenFile('goldens/$golden'),
  );
  expect(tester.takeException(), isNull);
}

/// An open `showConSheet` menu, captured from above the `MaterialApp` so the
/// Overlay the sheet lives on is inside the boundary.
///
/// The sheet route carries no `Scaffold`, so before `showConSheet` wrapped its
/// page in a `Material` every label here painted in Flutter's fallback style:
/// monospace under a double #FFFF00 rule. A golden is the cheapest guard
/// against that coming back — the yellow is impossible to miss in a diff.
Future<void> _captureSheet(WidgetTester tester, {required double textScale}) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  late BuildContext host;
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey<String>('visual-handoff-sheet'),
      child: MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          backgroundColor: Con.ground,
          body: Builder(
            builder: (BuildContext context) {
              host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  unawaited(
    showConSheet<void>(
      host,
      (BuildContext sheet) => const ConSheet(
        title: 'Yacht sequence v1',
        children: <Widget>[
          ConSheetRow(label: 'Rate'),
          ConSheetRow(label: 'Edit caption'),
          ConSheetRow(label: 'Notes'),
          ConSheetRow(label: 'Details'),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The rows enter on a stagger; capture the settled sheet, not frame one.
  await tester.pump(const Duration(milliseconds: 800));
  await expectLater(
    find.byKey(const ValueKey<String>('visual-handoff-sheet')),
    matchesGoldenFile('goldens/sheet_390x844.png'),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(_loadVisualFonts);

  testWidgets('visual handoff: Results at 390 by 844', (tester) async {
    await _capture(tester, _results(textScale: 1), 'results_390x844.png');
  });

  testWidgets('visual handoff: Crew at 390 by 844', (tester) async {
    await _capture(tester, _crew(textScale: 1), 'crew_390x844.png');
  });

  testWidgets('visual handoff: Results at 390 by 844, large text', (
    tester,
  ) async {
    await _capture(
      tester,
      _results(textScale: 1.35),
      'results_390x844_large_text.png',
    );
  });

  testWidgets('visual handoff: Crew at 390 by 844, large text', (tester) async {
    await _capture(
      tester,
      _crew(textScale: 1.35),
      'crew_390x844_large_text.png',
    );
  });

  testWidgets('visual handoff: the reel overflow sheet at 390 by 844', (
    tester,
  ) async {
    await _captureSheet(tester, textScale: 1);
  });
}
