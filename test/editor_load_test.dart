// What the editor is allowed to fetch before it has drawn anything.
//
// The four requests behind `loadCatalog`'s `Future.wait` run in parallel, so
// the slowest one gates the editor's first useful frame. `source-finalists` was
// one of them and is dialog-only data -- on a cold backend it measured 578 ms
// against 67 ms for the next slowest, because the server re-hashes every
// reviewed source clip on its first call per process. It is fetched on demand
// now, and these tests are what stops it drifting back into the open path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/native_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _base = 'https://fixture.test';

const Map<String, dynamic> _asset = <String, dynamic>{
  'id': 'lib-1',
  'account': '@zionboggan',
  'title': 'A source clip',
  'library': true,
  'duration_seconds': 10,
};

Future<void> _open(WidgetTester tester, List<String> paths) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  Future<dynamic> request(
    String method,
    String path,
    Map<String, Object?>? body,
  ) async {
    paths.add(path);
    if (path == '/reels/catalog') return <dynamic>[];
    if (path.startsWith('/reels/library')) {
      return <String, dynamic>{
        'assets': <dynamic>[_asset],
      };
    }
    if (path.startsWith('/reels/music')) {
      return <String, dynamic>{'assets': <dynamic>[]};
    }
    if (path.startsWith('/reels/source-taste')) {
      return <String, dynamic>{'reviews': <dynamic>[]};
    }
    if (path.startsWith('/reels/source-finalists')) {
      return <String, dynamic>{
        'review_counts': <String, dynamic>{'use': 3, 'maybe': 1, 'reject': 0},
        'generation_readiness': <String, dynamic>{},
      };
    }
    throw StateError('Unexpected fixture request $method $path');
  }

  await tester.pumpWidget(
    MaterialApp(
      home: NativeReelEditor(base: _base, requestOverride: request),
    ),
  );
  await tester.pumpAndSettle();
}

bool _asked(List<String> paths, String prefix) =>
    paths.any((String path) => path.startsWith(prefix));

void main() {
  testWidgets('opening the editor does not fetch the shortlist summary', (
    WidgetTester tester,
  ) async {
    final List<String> paths = <String>[];
    await _open(tester, paths);
    expect(
      _asked(paths, '/reels/source-finalists'),
      isFalse,
      reason: 'dialog-only data must not gate the editor opening',
    );
    // The three that do feed the first frame are still eager.
    expect(paths, contains('/reels/catalog'));
    expect(_asked(paths, '/reels/library'), isTrue);
    expect(_asked(paths, '/reels/music'), isTrue);
    expect(
      _asked(paths, '/reels/source-taste'),
      isTrue,
      reason: 'the library grid paints its Use/Reject marks on first paint',
    );
  });

  testWidgets('Review shortlist fetches the summary, then shows real counts', (
    WidgetTester tester,
  ) async {
    final List<String> paths = <String>[];
    await _open(tester, paths);
    await tester.ensureVisible(find.text('Review shortlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review shortlist'));
    await tester.pumpAndSettle();
    expect(
      paths.where((String p) => p.startsWith('/reels/source-finalists')),
      hasLength(1),
    );
    // Fetched before the dialog opened, so it never shows zeros for data the
    // server already has.
    expect(find.textContaining('3'), findsWidgets);
  });
}
