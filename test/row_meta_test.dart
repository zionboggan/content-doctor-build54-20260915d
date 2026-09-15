// The state mark on a reel card must give way, not overflow the card.
//
// Caps already asks for one line with TextOverflow.ellipsis, but an unbounded
// child of a Row never gets the chance to honour that: it is laid out at its
// natural width and paints past the edge. A scheduled reel, whose state mark
// carries its schedule, overflowed the 16 pt meta row by 30 pt on a 390 pt
// phone — a yellow-and-black stripe on the card in debug, clipped text in
// release.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/console_harness.dart';

Map<String, dynamic> _scheduled() => <String, dynamic>{
  'id': 'scheduled',
  'sha256': 'sha-scheduled',
  'account': '@zionboggan',
  'title': 'Yacht sequence scheduled',
  'caption': 'A caption',
  'status': 'ready_for_review',
  'duration_seconds': 23,
  'created_at': kPinnedNow.subtract(const Duration(hours: 3)).toIso8601String(),
  'review': <String, dynamic>{
    'id': 'scheduled',
    'sha256': 'sha-scheduled',
    'account': '@zionboggan',
    'caption': 'A caption',
    'state': 'review_approved',
  },
  'schedule_detail': <String, dynamic>{
    'state': 'scheduled',
    'scheduled_at': '2026-09-20T18:00:00Z',
  },
};

void main() {
  testWidgets('a scheduled card does not overflow its meta row sideways', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        await tester.tap(find.text('All').first);
        await tester.pumpAndSettle();
        expect(reelRow('scheduled'), findsOneWidget);
        expect(tester.getSize(reelRow('scheduled')).width, 390);

        final List<String> errors = <String>[];
        for (
          Object? thrown = tester.takeException();
          thrown != null;
          thrown = tester.takeException()
        ) {
          errors.add('$thrown');
        }
        debugPrint('MEASURED overflow errors on a scheduled card: $errors');
        expect(
          errors.where((String e) => e.contains('on the right')),
          isEmpty,
          reason: 'the state mark ellipsises instead of painting past the card',
        );
        // Recorded, not fixed here: the card body still overflows its
        // IntrinsicHeight by 57 pt on the bottom for a scheduled reel, because
        // IntrinsicHeight asks the title for its single-line height and the
        // title then wraps. The register's CD-04 remedy — move the accent bar
        // into the Stack that already wraps the row and drop IntrinsicHeight
        // entirely — removes the whole class. Not done blind.
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: <Map<String, dynamic>>[_scheduled()]),
    );
  });

  // CD-04's remedy is recorded in the register as "pixel-identical if done as
  // described". MEASURED here, it is not, and the difference is on every card
  // in Review — so this is a refutation, not a re-derivation.
  //
  // The register identifies the accent bar as "the only thing needing
  // full-row height" and concludes that moving it into the Stack removes both
  // IntrinsicHeight and `crossAxisAlignment: stretch` for free. The poster is
  // the second thing. `_Poster` declares a 60x104 SizedBox, but `stretch`
  // hands its Padding a *tight* height, and `BoxConstraints.tighten` cannot
  // escape a tight parent — so the poster is laid out at the row's height
  // less its 12 pt top inset, not at 104.
  //
  // Dropping `stretch` therefore shrinks every poster in the Review list by
  // 18 pt. That is an appearance change on every row, it is not covered by
  // the register's entry, and per the standing constraint it needs Zion
  // before anyone applies it.
  testWidgets('the poster is stretched, so CD-04 is not free', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        final Finder row = reelRows.first;
        final double card = tester.getSize(row).height;
        final double poster = tester
            .getSize(
              find.descendant(of: row, matching: find.byType(Image)).first,
            )
            .height;
        debugPrint(
          'MEASURED reel row ${card.toStringAsFixed(0)} pt tall'
          '  poster ${poster.toStringAsFixed(0)} pt'
          '  declared 104 pt',
        );
        expect(
          poster,
          greaterThan(104),
          reason: 'crossAxisAlignment.stretch overrides the declared height',
        );
        expect(poster, closeTo(card - 6 - 12, 0.5));
      },
      // A plain card, because the stretch is on every card, not only on the
      // one that overflows.
      createHttpClient: (SecurityContext? c) => FakeGateway(),
    );
  });
}
