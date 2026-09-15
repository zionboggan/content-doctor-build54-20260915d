import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/native_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The editor is pumped here at the test binding's default 800x600, which is
// above the 704 pt breakpoint, so it lays out as the iPad two-pane editor:
// source and preview on the left, the editing controls and the export button
// on the right. Every control these tests reach for is in the right-hand
// pane, so they scroll `Scrollable.last`. At a phone width there is one
// scrollable and `.last` is `.first`, which is the column that shipped.
void main() {
  testWidgets('selected Gabe reel queues exact recipe without rendering', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final item = <String, dynamic>{
      'id': 'gabe-exact',
      'sha256': 'a' * 64,
      'account': '@barcrawling',
      'title': 'Selected export',
      'duration_seconds': 10,
      'status': 'ready_for_review',
    };
    final writes = <Map<String, Object?>>[];
    Future<dynamic> request(
      String method,
      String path,
      Map<String, Object?>? body,
    ) async {
      if (path == '/reels/catalog') return [item];
      if (method == 'GET') return <String, Object?>{};
      expect(path, '/trial-message');
      writes.add(body!);
      return {'intake_verified': true};
    }

    await tester.pumpWidget(
      MaterialApp(
        home: NativeReelEditor(
          base: 'https://fixture.test',
          allowedAccounts: const ['@barcrawling'],
          initialReel: item,
          collectOnly: true,
          requestOverride: request,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Pacing & revision brief'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Pacing & revision brief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pacing & revision brief'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save recipe to revision queue'),
      550,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Save recipe to revision queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe to revision queue'));
    await tester.pumpAndSettle();
    expect(writes.length, 1);
    expect(writes.single['reel_id'], 'gabe-exact');
    expect(writes.single['reel_sha256'], 'a' * 64);
    expect(writes.single['account'], '@barcrawling');
    expect(writes.single['text'], contains('do not execute automatically'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a collection-only session never resumes another role’s render', (
    tester,
  ) async {
    const base = 'https://fixture.test';
    SharedPreferences.setMockInitialValues({
      'trial.studio-jobs:$base':
          '{"jobs":[{"id":"native-owner","account":"@zionboggan","status":"queued"}]}',
    });
    final requests = <String>[];
    Future<dynamic> request(
      String method,
      String path,
      Map<String, Object?>? body,
    ) async {
      requests.add('$method $path');
      if (path == '/reels/catalog') return <dynamic>[];
      if (path.startsWith('/reels/library')) return {'assets': <dynamic>[]};
      return <String, dynamic>{};
    }

    await tester.pumpWidget(
      MaterialApp(
        home: NativeReelEditor(
          base: base,
          allowedAccounts: const ['@barcrawling'],
          collectOnly: true,
          requestOverride: request,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      requests.where((path) => path.startsWith('GET /reels/render/')),
      isEmpty,
    );
    expect(find.text('Review export'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scoped direct-render grant creates a review-only export', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final item = <String, dynamic>{
      'id': 'gabe-review',
      'sha256': 'b' * 64,
      'account': '@barcrawling',
      'title': 'Gabe review source',
      'duration_seconds': 10,
      'status': 'ready_for_review',
    };
    final writes = <Map<String, Object?>>[];
    Future<dynamic> request(
      String method,
      String path,
      Map<String, Object?>? body,
    ) async {
      if (path == '/reels/catalog') return [item];
      if (method == 'GET' && path.startsWith('/reels/render/')) {
        return {
          'status': 'ready_for_review',
          'asset': {'id': 'gabe-review-export'},
        };
      }
      if (path == '/reels/music') return {'assets': <dynamic>[]};
      if (path == '/reels/render') {
        writes.add(body!);
        return {
          'job_id': 'native-gabe-review',
          'status': 'ready_for_review',
          'asset': {'id': 'gabe-review-export'},
        };
      }
      throw StateError('Unexpected fixture request $method $path');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: NativeReelEditor(
          base: 'https://fixture.test',
          allowedAccounts: const ['@barcrawling'],
          initialReel: item,
          collectOnly: true,
          allowDirectRender: true,
          requestOverride: request,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create review export'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Create review export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single['account'], '@barcrawling');
    expect(writes.single['source_reel_id'], 'gabe-review');
    expect(writes.single.containsKey('scheduled_at'), isFalse);
    expect(writes.single.containsKey('post_now'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
