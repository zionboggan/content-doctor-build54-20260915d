// Batch scheduling.
//
// The plan builder is pure, so these assert the exact entries the screen would
// send. No test here reaches a gateway, and none may exercise a posting path:
// a batch is scheduled through /reels/schedule, which queues a TRIAL reel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/batch_schedule.dart';

Map<String, dynamic> _item(String id, {String caption = 'original'}) =>
    <String, dynamic>{
      'id': id,
      'sha256': id.hashCode.toRadixString(16).padLeft(64, '0'),
      'account': '@zionboggan',
      'title': 'Reel $id',
      'caption': caption,
    };

final DateTime _now = DateTime(2026, 9, 17, 8);
DateTime _phoenixNow() => _now;
DateTime _wallToUtc(DateTime wall) =>
    DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute)
        .add(const Duration(hours: 7));

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> items,
  required BatchConfirm onConfirm,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BatchSchedulePage(
        items: items,
        phoenixNow: _phoenixNow,
        wallToUtc: _wallToUtc,
        onConfirm: onConfirm,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('plan building', () {
    test('spreads one reel per day from the first slot', () {
      final List<BatchPlanRow> plan = buildPlan(
        selected: <Map<String, dynamic>>[_item('a'), _item('b'), _item('c')],
        firstSlot: DateTime(2026, 9, 18, 9),
        everyDays: 1,
        template: '',
        overrides: const <String, String>{},
      );
      expect(plan.map((BatchPlanRow r) => r.when.day), <int>[18, 19, 20]);
      expect(plan.every((BatchPlanRow r) => r.when.hour == 9), isTrue);
    });

    test('honours wider spacing', () {
      final List<BatchPlanRow> plan = buildPlan(
        selected: <Map<String, dynamic>>[_item('a'), _item('b'), _item('c')],
        firstSlot: DateTime(2026, 9, 18, 9),
        everyDays: 3,
        template: '',
        overrides: const <String, String>{},
      );
      expect(plan.map((BatchPlanRow r) => r.when.day), <int>[18, 21, 24]);
    });

    test('a blank template keeps each reel its own caption', () {
      // Sending an empty caption would silently strip a caption an operator
      // already approved.
      final List<BatchPlanRow> plan = buildPlan(
        selected: <Map<String, dynamic>>[
          _item('a', caption: 'first'),
          _item('b', caption: 'second'),
        ],
        firstSlot: DateTime(2026, 9, 18, 9),
        everyDays: 1,
        template: '   ',
        overrides: const <String, String>{},
      );
      expect(
        plan.map((BatchPlanRow r) => r.caption),
        <String>['first', 'second'],
      );
    });

    test('a template applies to every reel that has no override', () {
      final List<BatchPlanRow> plan = buildPlan(
        selected: <Map<String, dynamic>>[_item('a'), _item('b')],
        firstSlot: DateTime(2026, 9, 18, 9),
        everyDays: 1,
        template: 'shared line',
        overrides: const <String, String>{},
      );
      expect(
        plan.map((BatchPlanRow r) => r.caption),
        <String>['shared line', 'shared line'],
      );
    });

    test('an override beats the template for that reel only', () {
      final List<BatchPlanRow> plan = buildPlan(
        selected: <Map<String, dynamic>>[_item('a'), _item('b')],
        firstSlot: DateTime(2026, 9, 18, 9),
        everyDays: 1,
        template: 'shared line',
        overrides: const <String, String>{'b': 'just for b'},
      );
      expect(
        plan.map((BatchPlanRow r) => r.caption),
        <String>['shared line', 'just for b'],
      );
    });

    test('zero or negative spacing still advances a day', () {
      // Two reels in the same slot would be a duplicate the backend rejects
      // after the operator already built the plan.
      for (final int spacing in <int>[0, -3]) {
        final List<BatchPlanRow> plan = buildPlan(
          selected: <Map<String, dynamic>>[_item('a'), _item('b')],
          firstSlot: DateTime(2026, 9, 18, 9),
          everyDays: spacing,
          template: '',
          overrides: const <String, String>{},
        );
        expect(plan[1].when.difference(plan[0].when).inDays, 1);
      }
    });
  });

  testWidgets('an empty library says so rather than offering an empty plan', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      items: <Map<String, dynamic>>[],
      onConfirm: (_) async => fail('must not confirm'),
    );
    expect(find.text('Nothing approved yet'), findsOneWidget);
    expect(find.text('Select reels to schedule'), findsOneWidget);
  });

  testWidgets('confirming sends exact entries with UTC slots, and no posting', (
    WidgetTester tester,
  ) async {
    List<Map<String, dynamic>>? sent;
    await _pump(
      tester,
      items: <Map<String, dynamic>>[_item('a'), _item('b')],
      onConfirm: (List<Map<String, dynamic>> entries) async => sent = entries,
    );
    await tester.tap(find.text('Reel a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reel b'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Schedule 2 reels'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.length, 2);
    for (final Map<String, dynamic> entry in sent!) {
      expect(entry['confirm'], isTrue);
      expect(entry['account'], '@zionboggan');
      expect(entry['sha256'], isNotEmpty);
      expect(entry['scheduled_at'], endsWith('Z'));
      // Nothing in a scheduling entry may ask for an immediate post.
      expect(entry.containsKey('post_now'), isFalse);
      expect(entry.containsKey('cadence_minutes'), isFalse);
    }
    // 9am Phoenix on the 18th is 16:00 UTC.
    expect(sent!.first['scheduled_at'], '2026-09-18T16:00:00.000Z');
    expect(sent!.last['scheduled_at'], '2026-09-19T16:00:00.000Z');
  });

  testWidgets('deselecting removes a reel from the plan', (
    WidgetTester tester,
  ) async {
    List<Map<String, dynamic>>? sent;
    await _pump(
      tester,
      items: <Map<String, dynamic>>[_item('a'), _item('b')],
      onConfirm: (List<Map<String, dynamic>> entries) async => sent = entries,
    );
    await tester.tap(find.text('Reel a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reel b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reel a'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Schedule 1 reel'));
    await tester.pumpAndSettle();

    expect(sent!.single['id'], 'b');
  });

  testWidgets('a rejected batch is reported and nothing is silently dropped', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      items: <Map<String, dynamic>>[_item('a')],
      onConfirm: (_) async =>
          throw Exception('Export already approved or scheduled; use reschedule'),
    );
    await tester.tap(find.text('Reel a'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Schedule 1 reel'));
    await tester.pumpAndSettle();

    expect(find.text('Batch not scheduled'), findsOneWidget);
    expect(find.textContaining('use reschedule'), findsOneWidget);
    // Still usable: the operator can fix and retry without losing the plan.
    expect(find.textContaining('Schedule 1 reel'), findsOneWidget);
  });

  testWidgets('the batch limit is stated instead of silently truncating', (
    WidgetTester tester,
  ) async {
    // The cap matches the backend's. Injected here so the guard is exercised
    // without building a twenty-row plan.
    await tester.pumpWidget(
      MaterialApp(
        home: BatchSchedulePage(
          items: <Map<String, dynamic>>[_item('a'), _item('b'), _item('c')],
          phoenixNow: _phoenixNow,
          wallToUtc: _wallToUtc,
          limit: 2,
          onConfirm: (_) async => fail('must not confirm'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reel a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reel b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reel c'));
    await tester.pumpAndSettle();

    expect(find.textContaining('One batch holds 2'), findsOneWidget);
    expect(find.textContaining('Schedule 2 reels'), findsOneWidget);
  });

  test('the shipped limit matches the backend cap', () {
    expect(kBatchLimit, 20);
  });

  testWidgets('the screen states that scheduling does not post', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      items: <Map<String, dynamic>>[_item('a')],
      onConfirm: (_) async {},
    );
    expect(find.textContaining('Nothing posts now'), findsOneWidget);
    expect(find.textContaining('Trial reel'), findsOneWidget);
  });

  group('slot labels', () {
    test('render Phoenix wall time in 12 hour form', () {
      expect(batchSlotLabel(DateTime(2026, 9, 18, 9)), 'Sep 18 · 9:00 AM');
      expect(batchSlotLabel(DateTime(2026, 9, 18, 13, 5)), 'Sep 18 · 1:05 PM');
      expect(batchSlotLabel(DateTime(2026, 9, 18, 0, 30)), 'Sep 18 · 12:30 AM');
      expect(batchSlotLabel(DateTime(2026, 9, 18, 12)), 'Sep 18 · 12:00 PM');
    });
  });
}
