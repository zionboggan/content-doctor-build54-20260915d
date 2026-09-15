import 'package:flutter_test/flutter_test.dart';
import 'package:iris/main.dart';

void main() {
  final reel = <String, dynamic>{
    'id': 'one',
    'sha256': 'abc',
    'account': '@zionboggan',
    'caption': 'Caption',
    'status': 'ready_for_review',
    'review': {
      'id': 'one',
      'sha256': 'abc',
      'account': '@zionboggan',
      'caption': 'Caption',
      'state': 'review_approved',
    },
  };
  test(
    'scheduled exact export takes precedence over approval and offers next action',
    () {
      final scheduled = {
        ...reel,
        'schedule_detail': {
          'state': 'scheduled',
          'scheduled_at': '2026-09-12T18:00:00Z',
        },
      };
      expect(reelLifecycle(scheduled), 'Scheduled');
      expect(reelNextAction(scheduled), contains('Scheduled'));
      expect(
        reelLifecycle({
          ...reel,
          'schedule_detail': {'state': 'published'},
        }),
        'Published',
      );
      expect(
        reelLifecycle({...reel, 'status': 'changes_requested'}),
        'Revision queued',
      );
    },
  );
  test(
    'provider status explanation and recovery displayed without raw errors',
    () {
      expect(
        scheduleExplanation({
          'state': 'paused',
          'status_explanation': {
            'summary': 'Publishing is paused for this account.',
            'recovery_action': 'Enable publishing in Accounts.',
          },
        }),
        'Publishing is paused for this account.\nEnable publishing in Accounts.',
      );
    },
  );
  test('operator times use Phoenix 12-hour clock with AM or PM', () {
    expect(clock(DateTime.utc(2026, 9, 12, 7)), '12:00 AM');
    expect(clock(DateTime.utc(2026, 9, 12, 19, 5)), '12:05 PM');
    expect(clock(DateTime.utc(2026, 9, 13, 1, 45)), '6:45 PM');
  });
  test('scrap remains available only for reversible review states', () {
    expect(canScrapReel(reel), isTrue);
    expect(canScrapReel({...reel, 'status': 'changes_requested'}), isTrue);
    expect(canScrapReel({...reel, 'status': 'published'}), isFalse);
  });
  test('a scrapped reel is plainly marked and only offers restore', () {
    final scrapped = {...reel, 'status': 'scrapped'};
    expect(reelLifecycle(scrapped), 'Scrapped');
    expect(canScrapReel(scrapped), isFalse);
    expect(canRestoreReel(scrapped), isTrue);
    expect(reelCanReceiveNewIntent(scrapped), isFalse);
  });
  test('published receipt exposes the nested Instagram permalink and time', () {
    final published = {
      ...reel,
      'status': 'published',
      'approval': {
        'state': 'published',
        'finished_at': '2026-09-14T06:10:00Z',
        'receipt': {'permalink': 'https://instagram.com/reel/example'},
      },
    };
    expect(reelPermalink(published), 'https://instagram.com/reel/example');
    expect(reelPostedAt(published), DateTime.utc(2026, 9, 14, 6, 10));
    expect(reelReceiptSummary(published), startsWith('Posted '));
    expect(reelReceiptSummary(published), endsWith('at 11:10 PM'));
  });
  test('a published status without a provider receipt does not invent one', () {
    expect(reelReceiptSummary({...reel, 'status': 'published'}), isNull);
  });
}
