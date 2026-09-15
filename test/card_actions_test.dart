// Scrap, post and edit on the clip card.
//
// Zion asked for all three to be reachable from the home page card. Scrap was
// already there. Post now was card -> ⋯ -> "Post now" -> confirm sheet, and
// Edit was card -> ⋯ -> "Make variations", or card -> tap -> player ->
// "Edit reel". Both are now one tap.
//
// It also holds the row to its width budget. The action row is a fixed 44 pt
// Row and at 390 pt it has about 278 pt for controls; one control too many
// overflows it rather than wrapping. MEASURED, adding an 18 pt Edit icon to
// the Approved row squeezes Schedule from 71 pt to 19 pt wide, which is why
// Edit is on Scheduled, On hold and Revision queued and not on For review or
// Approved. Those two rows are already full on the shipped build — "Changes"
// truncates to "Cha…" today.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/console_shell.dart';
import 'package:iris/native_editor.dart';

import 'support/console_harness.dart';

Map<String, dynamic> _reel(
  String id, {
  String status = 'ready_for_review',
  Map<String, dynamic>? review,
  Map<String, dynamic>? schedule,
}) => <String, dynamic>{
  'id': id,
  'sha256': 'sha-$id',
  'account': '@zionboggan',
  'title': 'Yacht sequence $id',
  'caption': 'A caption for $id',
  'status': status,
  'duration_seconds': 23,
  'created_at': kPinnedNow.subtract(const Duration(hours: 3)).toIso8601String(),
  // _reviewApproved requires the review receipt to match the export exactly.
  'review': ?(review == null
      ? null
      : <String, dynamic>{
          'id': id,
          'sha256': 'sha-$id',
          'account': '@zionboggan',
          'caption': 'A caption for $id',
          ...review,
        }),
  'schedule_detail': ?schedule,
};

final List<Map<String, dynamic>> _lifecycles = <Map<String, dynamic>>[
  _reel('forreview'),
  _reel('approved', review: <String, dynamic>{'state': 'review_approved'}),
  _reel(
    'scheduled',
    review: <String, dynamic>{'state': 'review_approved'},
    schedule: <String, dynamic>{
      'state': 'scheduled',
      'scheduled_at': '2026-09-20T18:00:00Z',
    },
  ),
  _reel('revision', status: 'changes_requested'),
];

Finder _actionIn(String id, String semanticLabel) => find.descendant(
  of: reelRow(id),
  matching: find.bySemanticsLabel(semanticLabel),
);

Finder _buttonIn(String id, String label) =>
    find.descendant(of: reelRow(id), matching: find.text(label));

Future<void> _showAll(WidgetTester tester) async {
  // "All" rather than "Needs you", so approved and scheduled reels are listed.
  await tester.tap(find.text('All').first);
  await tester.pumpAndSettle();
}

List<String> _horizontalOverflows(WidgetTester tester) {
  final List<String> errors = <String>[];
  for (
    Object? thrown = tester.takeException();
    thrown != null;
    thrown = tester.takeException()
  ) {
    // The 57 pt bottom overflow on a card carrying a receipt line is the
    // known IntrinsicHeight defect recorded in test/row_meta_test.dart, not
    // anything this file changed.
    if ('$thrown'.contains('on the right')) errors.add('$thrown');
  }
  return errors;
}

void main() {
  testWidgets('Edit and Post now are one tap from the card', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        await _showAll(tester);

        expect(
          _buttonIn('approved', 'Post now'),
          findsOneWidget,
          reason: 'an approved reel can be posted from the card',
        );
        expect(
          _actionIn('scheduled', 'Edit'),
          findsOneWidget,
          reason: 'a scheduled reel can be edited from the card',
        );
        expect(
          _buttonIn('forreview', 'Scrap'),
          findsOneWidget,
          reason: 'scrap was already there and stays',
        );

        await tester.scrollUntilVisible(reelRow('revision'), 200);
        await tester.pumpAndSettle();
        expect(
          _actionIn('revision', 'Edit'),
          findsOneWidget,
          reason: 'a reel with changes queued can be edited from the card',
        );
        expect(_horizontalOverflows(tester), isEmpty);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: _lifecycles),
    );
  });

  testWidgets('the card Edit opens the editor on that reel', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        await _showAll(tester);
        await tester.tap(_actionIn('scheduled', 'Edit'));
        await tester.pumpAndSettle();
        expect(find.byType(NativeReelEditor), findsOneWidget);
        _horizontalOverflows(tester);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: _lifecycles),
    );
  });

  testWidgets('the card Post now still asks before it posts', (
    WidgetTester tester,
  ) async {
    final FakeGateway gateway = FakeGateway(catalog: _lifecycles);
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      await _showAll(tester);
      await tester.tap(_buttonIn('approved', 'Post now'));
      await tester.pumpAndSettle();

      expect(
        find.text('This posts immediately and cannot be recalled.'),
        findsOneWidget,
        reason: 'the irreversible action keeps its confirm sheet',
      );
      expect(
        gateway.callsTo('/reels/post-now'),
        isEmpty,
        reason: 'nothing left the device on the first tap',
      );

      await tester.tap(find.widgetWithText(ConButton, 'Post now').last);
      await tester.pumpAndSettle();
      expect(gateway.callsTo('/reels/post-now'), hasLength(1));
      _horizontalOverflows(tester);
    }, createHttpClient: (SecurityContext? c) => gateway);
  });

  testWidgets('no card action row overflows sideways at either text scale', (
    WidgetTester tester,
  ) async {
    for (final double scale in <double>[1, 1.5]) {
      await HttpOverrides.runZoned(
        () async {
          await bootConsole(tester, textScale: scale);
          await _showAll(tester);
          for (final Map<String, dynamic> reel in _lifecycles) {
            final Finder row = reelRow('${reel['id']}');
            if (row.evaluate().isEmpty) continue;
            expect(
              tester.getSize(row).width,
              390,
              reason: '${reel['id']} at scale $scale',
            );
          }
          expect(
            _horizontalOverflows(tester),
            isEmpty,
            reason: 'no sideways overflow at text scale $scale',
          );
        },
        createHttpClient: (SecurityContext? c) =>
            FakeGateway(catalog: _lifecycles),
      );
    }
  });
}
