import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/native_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'restored sequence reorders ranges and creates one review-only job',
    (tester) async {
      const base = 'https://fixture.test';
      final shots = [
        for (final id in ['first', 'second'])
          {
            'source_reel_id': id,
            'trim_in_seconds': 1,
            'trim_out_seconds': 3,
            'title': id,
            'item': {
              'id': id,
              'account': '@zionboggan',
              'title': id,
              'library': true,
              'duration_seconds': 10,
            },
          },
      ];
      SharedPreferences.setMockInitialValues({
        'trial.studio-jobs:$base': jsonEncode({
          'sequences': {'@zionboggan': shots},
        }),
      });
      final requests = <Map<String, Object?>>[];
      Future<dynamic> request(
        String method,
        String path,
        Map<String, Object?>? body,
      ) async {
        if (path == '/reels/catalog') return [];
        if (path.startsWith('/reels/library')) {
          return {'assets': shots.map((shot) => shot['item']).toList()};
        }
        if (path == '/reels/music') return {'assets': []};
        if (path == '/reels/render') {
          requests.add(body!);
          return body['validate_only'] == true
              ? {'validated': true}
              : {'job_id': 'native-sequence'};
        }
        if (path == '/reels/render/native-sequence') {
          return {
            'status': 'ready_for_review',
            'asset': {'id': 'new-review'},
          };
        }
        throw StateError('Unexpected fixture request $method $path');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: NativeReelEditor(base: base, requestOverride: request),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Combine clips into one reel'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip('Move later').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move later').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Render combined preview'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Render combined preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Render preview'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.first['validate_only'], isTrue);
      final payload = requests.last;
      expect(payload.containsKey('source_reel_id'), isFalse);
      expect(payload['account'], '@zionboggan');
      final sent = payload['shots'] as List;
      expect(sent.map((shot) => shot['source_reel_id']), ['second', 'first']);
      expect(sent.first['trim_in_seconds'], 1);
      expect(sent.first['trim_out_seconds'], 3);
      expect(payload.containsKey('scheduled_at'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('trial.studio-jobs:$base')!);
      expect(saved['jobs'].single['review_id'], 'new-review');
      expect(tester.takeException(), isNull);
    },
  );
}
