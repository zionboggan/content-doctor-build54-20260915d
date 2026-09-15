import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/render_jobs.dart';

void main() {
  test(
    'mixed batch outcomes retain each result and only pending work resumes',
    () {
      final jobs = RenderJobs();
      for (final id in ['first', 'second', 'third']) {
        jobs.submitted(
          {'job_id': id},
          sourceId: id,
          account: '@zionboggan',
          signature: id,
        );
      }
      jobs.update('first', {
        'status': 'ready_for_review',
        'asset': {'id': 'export-first'},
      });
      jobs.update('second', {
        'status': 'failed',
        'error': 'Bad source',
        'asset': {'id': 'not-ready'},
      });
      final restored = RenderJobs()
        ..restore(jsonDecode(jsonEncode(jobs.toJson())));
      expect(restored.items.length, 3);
      expect(restored.pending.single['id'], 'third');
      expect(restored.items.first['review_id'], 'export-first');
      expect(restored.items.elementAt(1)['review_id'], isNull);
      expect(restored.items.elementAt(1)['error'], 'Bad source');
    },
  );
  test(
    'partial retry deduplicates an accepted job and rejects missing receipt',
    () {
      final jobs = RenderJobs();
      for (var i = 0; i < 2; i++) {
        jobs.submitted(
          {'job_id': 'same'},
          sourceId: 'source',
          account: '@zionboggan',
          signature: 'recipe',
        );
      }
      expect(jobs.items.length, 1);
      expect(
        () => jobs.submitted(
          {},
          sourceId: 'second',
          account: '@zionboggan',
          signature: 'next',
        ),
        throwsStateError,
      );
      expect(jobs.items.single['id'], 'same');
    },
  );
  test(
    'lost or incomplete completion receipts stop polling and stay retryable',
    () {
      final jobs = RenderJobs()
        ..submitted(
          {'job_id': 'lost'},
          sourceId: 'source',
          account: '@zionboggan',
          signature: 'lost-recipe',
        );
      jobs.update('lost', {'status': 'unknown'});
      expect(jobs.pending, isEmpty);
      expect(jobs.items.single['status'], 'failed');
      expect(jobs.items.single['error'], contains('no longer has'));

      jobs.submitted(
        {'job_id': 'incomplete'},
        sourceId: 'source',
        account: '@zionboggan',
        signature: 'incomplete-recipe',
      );
      jobs.update('incomplete', {'status': 'ready_for_review'});
      expect(jobs.pending, isEmpty);
      expect(jobs.items.last['status'], 'failed');
      expect(jobs.items.last['review_id'], isNull);
    },
  );
}
