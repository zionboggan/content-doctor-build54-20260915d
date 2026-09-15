// A reel's `caption` field is not always a plain string on the wire. Newer
// "captioned successor" rows carry either a single `{text, style}` object
// (per-reel caption authoring) or a list of timed segments
// `[{start, end, text}, ...]` (the per-segment caption editor). A caption
// that assumed a plain string and hard-cast it (`as String?`) threw a
// TypeError mid-build for any such row. Flutter's release-mode error widget
// renders that as a plain grey box — this is the root cause behind a
// "half-screen" screenshot that review_viewport_test.dart's chrome fix does
// not explain: a shell that gives the list its full 740pt workspace still
// goes blank partway down the list once it reaches a structured-caption row.
//
// Content and IDs here are placeholders. Do not use real reel data in a
// committed test: this file ships through the sanitized public CI export.
//
// Everything here is synthetic: fake gateway, pinned clock.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

List<Map<String, dynamic>> _mixedShapeCatalog() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'reel-plain-string-caption',
    'sha256': 'sha-plain',
    'account': '@zionboggan',
    'status': 'ready_for_review',
    'caption': 'a plain string caption',
    'duration_seconds': 20,
    'created_at': kPinnedNow
        .subtract(const Duration(hours: 1))
        .toIso8601String(),
  },
  <String, dynamic>{
    'id': 'reel-object-caption',
    'sha256': 'sha-object',
    'account': '@zionboggan',
    'status': 'ready_for_review',
    // A single-caption authoring object, as produced by the caption editor.
    'caption': <String, dynamic>{
      'text': 'placeholder object caption text',
      'style': 'large lower-case white with black outline',
    },
    'duration_seconds': 20,
    'created_at': kPinnedNow
        .subtract(const Duration(hours: 2))
        .toIso8601String(),
  },
  <String, dynamic>{
    'id': 'reel-segmented-caption',
    'sha256': 'sha-segments',
    'account': '@zionboggan',
    'status': 'changes_requested',
    // A per-segment timed caption list, as produced by the segment editor.
    'caption': <Map<String, dynamic>>[
      <String, dynamic>{'start': 0.1, 'end': 4.0, 'text': 'first segment'},
      <String, dynamic>{'start': 8.0, 'end': 13.0, 'text': 'second segment'},
    ],
    'duration_seconds': 20,
    'created_at': kPinnedNow
        .subtract(const Duration(hours: 3))
        .toIso8601String(),
  },
];

void main() {
  testWidgets(
    'a review row with an object or segmented caption renders instead of throwing',
    (WidgetTester tester) async {
      await HttpOverrides.runZoned(
        () async {
          await bootConsole(tester);

          expect(tester.takeException(), isNull);
          expect(reelRow('reel-plain-string-caption'), findsOneWidget);
          expect(reelRow('reel-object-caption'), findsOneWidget);
          expect(reelRow('reel-segmented-caption'), findsOneWidget);

          // The object-shaped caption's title falls back to its own text,
          // not to Dart's raw `{text: ..., style: ...}` map syntax.
          expect(find.text('placeholder object caption text'), findsOneWidget);
          // The segmented caption's fallback title joins the segment text.
          expect(
            find.textContaining('first segment second segment'),
            findsOneWidget,
          );
        },
        createHttpClient: (SecurityContext? c) =>
            FakeGateway(catalog: _mixedShapeCatalog()),
      );
    },
  );
}
