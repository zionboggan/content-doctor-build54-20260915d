// What the app does with an iPad's glass.
//
// Build 52 answered this with one idea: cap the column at 704 pt and centre
// it. Measured, that stopped every stretched control and every 1366 pt line
// of text — and left a phone-width strip of cards in the middle of a 12.9"
// with 331 pt of dark ground down each side. Zion rejected it on sight:
// "I just want a full iPad screen layout, no small center bar stuff."
//
// So the rule these tests enforce is the opposite one, and it is a layout
// rule, not a look rule — same colours, same type, same spacing tokens, same
// motion:
//
//   1. nothing throws and nothing overflows, at eight iPad viewports and both
//      text scales, on every tab — unchanged from build 52, and still true;
//   2. anything that is fundamentally a list of cards is a **grid** on an
//      iPad, and that grid spans the workspace: the leftmost card starts at
//      x=0 and the rightmost ends at the right edge of the glass;
//   3. anything that is a thing plus the controls that change it — the
//      player, the editor, the generator, the flyer composer, Schedule's
//      calendar and queue, Team's roster and conversation — is **two panes**
//      side by side at iPad width, and the two panes tile the workspace;
//   4. a width cap survives in exactly three places, because more width is
//      worse there and nowhere else: a modal sheet, a block of body prose,
//      and a destructive control;
//   5. every one of the above is inert below 704 pt. One card per row, one
//      column, one list — at 390x844, at both Split View pane widths, and at
//      both text scales. The two shipped goldens in review_viewport_test.dart
//      are the pixel contract for that and still match byte for byte.
//
// NOT VERIFIED HERE, and not verifiable from this environment: real touch
// targets under a finger, Apple Pencil, drag and drop, a real iPadOS Split
// View or Stage Manager resize, the external-display path, and the hardware
// keyboard. Everything below is pure layout in a widget test.
//
// Everything is synthetic. No provider route, credential or network resource
// is reachable from any test in this file.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show BottomSheet, MaterialApp, Scaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/app_motion.dart';
import 'package:iris/console_shell.dart';
import 'package:iris/flyer_composer_page.dart';
import 'package:iris/generation_page.dart';
import 'package:iris/main.dart';
import 'package:iris/native_editor.dart';
import 'package:iris/native_results.dart';
import 'package:iris/schedule_calendar.dart';
import 'package:iris/team_page.dart';

import 'support/console_harness.dart';

const List<String> _tabs = <String>[
  'REVIEW',
  'SCHEDULE',
  'STUDIO',
  'RESULTS',
  'ACCOUNTS',
  'TEAM',
];

/// Every exception the framework handed the test since the last drain,
/// including every `RenderFlex overflowed` it reported.
List<String> _drain(WidgetTester tester) {
  final List<String> out = <String>[];
  for (
    Object? thrown = tester.takeException();
    thrown != null;
    thrown = tester.takeException()
  ) {
    out.add('$thrown'.split('\n').first);
  }
  return out;
}

Rect _rectOf(Element element) {
  final RenderBox box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

List<Rect> _rects(Finder finder) => finder.evaluate().map(_rectOf).toList();

/// The most populated row of [rects] — the cards that share a top edge —
/// sorted left to right.
///
/// A grid row is the unit this file measures: how many cards are in it, and
/// whether it reaches both edges of the glass.
List<Rect> _row(List<Rect> rects) {
  if (rects.isEmpty) return rects;
  final Map<int, List<Rect>> byTop = <int, List<Rect>>{};
  for (final Rect rect in rects) {
    byTop.putIfAbsent(rect.top.round(), () => <Rect>[]).add(rect);
  }
  final List<Rect> best = byTop.values.reduce(
    (List<Rect> a, List<Rect> b) => b.length > a.length ? b : a,
  );
  return List<Rect>.of(best)
    ..sort((Rect a, Rect b) => a.left.compareTo(b.left));
}

/// Cards keyed `studio-<id>` in the Studio library grid.
Finder get _studioTiles => find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('studio-'),
);

Finder _paneKey(String name) => find.byKey(ValueKey<String>('pane-$name'));

/// Two panes that tile [width] with nothing idle between or beside them.
void _expectTiled(List<Rect> panes, double width, {required String what}) {
  expect(panes, hasLength(2), reason: '$what is two panes');
  expect(panes.first.left, closeTo(0, 0.5), reason: '$what starts at x=0');
  expect(
    panes.last.right,
    closeTo(width, 0.5),
    reason: '$what reaches the right edge',
  );
  expect(
    panes.last.left - panes.first.right,
    lessThanOrEqualTo(2),
    reason: '$what leaves no gap between the panes',
  );
}

void main() {
  setUpAll(loadAppFonts);

  // -------------------------------------------------------------------------
  // 1. Nothing throws and nothing overflows, anywhere.
  // -------------------------------------------------------------------------

  for (final DeviceView view in kIpadViewports) {
    for (final double scale in <double>[1, 1.5]) {
      testWidgets('$view at text scale $scale renders every tab clean', (
        WidgetTester tester,
      ) async {
        await HttpOverrides.runZoned(() async {
          await bootConsole(tester, view: view, textScale: scale);
          expect(_drain(tester), isEmpty, reason: 'boot');
          for (final String tab in _tabs) {
            await tapTab(tester, tab);
            expect(
              _drain(tester),
              isEmpty,
              reason: '$tab at $view, text scale $scale',
            );
          }
        }, createHttpClient: (SecurityContext? c) => FakeGateway());
      });
    }
  }

  // -------------------------------------------------------------------------
  // 2. A list of cards is a grid, and the grid spans the glass.
  // -------------------------------------------------------------------------

  // Shipped 1.0.43+52, MEASURED by this test's predecessor: one reel card per
  // row, 704 pt wide, centred at x=331 on a 12.9" in landscape — 662 pt of
  // dark ground with nothing in it. That is the build Zion rejected.
  testWidgets('Review is a grid of cards that reaches both edges', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in kIpadViewports) {
        await bootConsole(tester, view: view);
        final double width = view.logical.width;
        final List<Rect> row = _row(_rects(reelRows));
        final int expected = SandLayout.columnsFor(width);
        debugPrint(
          'MEASURED $view  ${row.length} cards per row'
          '  card ${row.first.width.toStringAsFixed(0)} pt'
          '  x=${row.first.left.toStringAsFixed(0)}'
          '..${row.last.right.toStringAsFixed(0)}',
        );
        expect(row, hasLength(expected), reason: '$view cards per row');
        expect(row.first.left, closeTo(0, 0.5), reason: '$view starts at x=0');
        expect(
          row.last.right,
          closeTo(width, 0.5),
          reason: '$view reaches the right edge of the glass',
        );
        for (final Rect card in row) {
          expect(
            card.width,
            closeTo(width / expected, 1),
            reason: '$view cards share the width evenly',
          );
        }
        expect(_drain(tester), isEmpty, reason: '$view');
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // The iPhone contract. Anything that changed above has to be provably
  // absent here, at both text scales and at both Split View pane widths,
  // because an iPad hands a docked app an iPhone-narrow pane.
  testWidgets('every phone width is still one card per row, full bleed', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[
        kPhone,
        kSplitNarrow,
        kSplitWide,
      ]) {
        for (final double scale in <double>[1, 1.5]) {
          await bootConsole(tester, view: view, textScale: scale);
          final List<Rect> row = _row(_rects(reelRows));
          debugPrint(
            'MEASURED $view scale $scale  ${row.length} card per row'
            '  ${row.first.width.toStringAsFixed(0)} pt'
            '  x=${row.first.left.toStringAsFixed(0)}',
          );
          expect(
            SandLayout.columnsFor(view.logical.width),
            1,
            reason: '$view is below the breakpoint',
          );
          expect(
            row,
            hasLength(1),
            reason: '$view at $scale: one card per row',
          );
          expect(
            row.single.width,
            view.logical.width,
            reason: '$view at $scale: the card still spans the pane',
          );
          expect(row.single.left, 0, reason: '$view at $scale: no left margin');
        }
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // CD-01 was fixed on the phone by moving the command bar, the control row
  // and the readout strip into the list's own scroll view. That fix is a
  // measurement, so it is re-measured at every size it now runs at, against a
  // grid row rather than a single card.
  testWidgets('the Review list is handed the whole workspace on every iPad', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in kIpadViewports) {
        for (final double scale in <double>[1, 1.5]) {
          await bootConsole(tester, view: view, textScale: scale);
          final ScrollPosition position = tabScrollPosition(tester);
          final double workspace = workspaceRect(tester).height;
          final List<Rect> row = _row(_rects(reelRows));
          final double rowHeight = row
              .map((Rect r) => r.height)
              .reduce(math.max);
          debugPrint(
            'MEASURED $view scale $scale'
            '  workspace ${workspace.toStringAsFixed(0)}'
            '  list viewport ${position.viewportDimension.toStringAsFixed(0)}'
            '  ${row.length} per row'
            '  whole rows ${(position.viewportDimension / rowHeight).toStringAsFixed(2)}'
            '  whole cards '
            '${(position.viewportDimension / rowHeight * row.length).toStringAsFixed(2)}',
          );
          expect(
            position.viewportDimension,
            workspace,
            reason: '$view at $scale: the list viewport is the whole workspace',
          );
          expect(
            position.viewportDimension / rowHeight,
            greaterThanOrEqualTo(1.8),
            reason: '$view at $scale: at least two rows of cards are visible',
          );
        }
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // Accounts is a list of cards too, and it carried the worst stretched
  // control in the app: "Sign out" was 1334 pt of red outline before build 52
  // capped the whole page. The cards now use the width; the button does not.
  testWidgets('Accounts deals its cards across and keeps sign out a control', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[
        kPhone,
        kIpadMini,
        kIpad129Landscape,
      ]) {
        await bootConsole(tester, view: view);
        await tapTab(tester, 'ACCOUNTS');
        final List<Rect> row = _row(_rects(find.byType(DoctorCard)));
        await tester.scrollUntilVisible(find.text('Sign out'), 200);
        final Rect signOut = _rectOf(
          find
              .byWidgetPredicate(
                (Widget w) => w is ConButton && w.label == 'Sign out',
              )
              .evaluate()
              .single,
        );
        debugPrint(
          'MEASURED $view  ${row.length} account cards per row'
          '  card ${row.first.width.toStringAsFixed(0)}'
          '  sign out ${signOut.width.toStringAsFixed(0)} pt'
          ' at x=${signOut.left.toStringAsFixed(0)}',
        );
        expect(
          row,
          hasLength(math.min(2, SandLayout.columnsFor(view.logical.width))),
          reason: '$view: two accounts, so two per row above the breakpoint',
        );
        expect(
          signOut.width,
          lessThanOrEqualTo(SandLayout.card),
          reason: '$view: a destructive control keeps a control width',
        );
        expect(
          signOut.left,
          closeTo(16, 0.5),
          reason: '$view: and stays on the leading edge, as on a phone',
        );
        expect(_drain(tester), isEmpty, reason: '$view');
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // Z-4 from the build 52 audit: the approved library was a fixed three
  // columns of nine tiles at every width. It is the same tile; an iPad simply
  // fits more of them across, so the library shows more of the library.
  testWidgets('the Studio library fits more tiles across at width', (
    WidgetTester tester,
  ) async {
    // The library only lists reels whose recorded approval still matches the
    // export, so the fixture carries one. Synthetic, like everything else
    // here.
    final List<Map<String, dynamic>> approved = <Map<String, dynamic>>[
      for (final Map<String, dynamic> item in reviewCatalog(count: 40))
        <String, dynamic>{
          ...item,
          'review': <String, dynamic>{
            'state': 'review_approved',
            'sha256': item['sha256'],
            'account': item['account'],
            'caption': item['caption'],
          },
        },
    ];
    await HttpOverrides.runZoned(
      () async {
        for (final DeviceView view in <DeviceView>[
          kPhone,
          kIpadMini,
          kIpad11,
          kIpad129Landscape,
        ]) {
          await bootConsole(tester, view: view);
          await tapTab(tester, 'STUDIO');
          await tester.pumpAndSettle();
          final List<Rect> row = _row(_rects(_studioTiles));
          debugPrint(
            'MEASURED $view  ${row.length} library tiles per row'
            '  tile ${row.first.width.toStringAsFixed(0)}'
            'x${row.first.height.toStringAsFixed(0)}',
          );
          expect(
            row,
            hasLength(
              SandLayout.isWide(view.logical.width)
                  ? (view.logical.width / 190).round().clamp(3, 8)
                  : 3,
            ),
            reason: '$view library columns',
          );
          expect(_drain(tester), isEmpty, reason: '$view');
        }
      },
      createHttpClient: (SecurityContext? c) => FakeGateway(catalog: approved),
    );
  });

  // Results is a list of cards as well, and the one the build 52 audit called
  // "very sparse at width": a poster, a title and six metric tiles in a 1366
  // pt row. Three reels side by side is what a results screen is for.
  testWidgets('Results deals its cards across on an iPad', (
    WidgetTester tester,
  ) async {
    for (final DeviceView view in <DeviceView>[
      kPhone,
      kIpadMini,
      kIpad129Landscape,
    ]) {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = view.logical * 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NativeResults(
                base: 'http://127.0.0.1',
                selectedAccounts: const <String>{'@zionboggan'},
                catalog: const <Map<String, dynamic>>[],
                accountStatus: const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'account': '@zionboggan',
                    'insights': <String, dynamic>{
                      'status': 'ready',
                      'data_status': 'available',
                    },
                  },
                ],
                load: () async => <String, dynamic>{
                  'records': <dynamic>[
                    for (int i = 0; i < 3; i++)
                      <String, dynamic>{
                        'id': 'reel-$i',
                        'account': '@zionboggan',
                        'state': 'observed',
                        'metrics': <String, dynamic>{
                          'views': 20 + i,
                          'reach': 30 + i,
                          'total_interactions': i,
                        },
                      },
                  ],
                },
                connect: (_) {},
                preview: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final List<Rect> row = _row(
        _rects(
          find.byWidgetPredicate(
            (Widget w) =>
                w is CdEnter &&
                w.key is ValueKey<Object?> &&
                '${(w.key! as ValueKey<Object?>).value}'.startsWith('reel-'),
          ),
        ),
      );
      debugPrint(
        'MEASURED $view  ${row.length} result cards per row'
        '  card ${row.first.width.toStringAsFixed(0)} pt'
        '  x=${row.first.left.toStringAsFixed(0)}'
        '..${row.last.right.toStringAsFixed(0)}',
      );
      expect(
        row,
        hasLength(SandLayout.columnsFor(view.logical.width)),
        reason: '$view result cards per row',
      );
      expect(_drain(tester), isEmpty, reason: '$view');
    }
  });

  // -------------------------------------------------------------------------
  // 3. A thing and its controls are two panes.
  // -------------------------------------------------------------------------

  // Shipped, MEASURED: 390x377 on a phone, 744x630 on an iPad mini and
  // 1366x1074 on a 12.9" in landscape — where the workspace is 943 pt tall,
  // so one month of a seven-column grid was taller than the whole screen.
  // Build 52 fixed that by making the calendar narrower and giving the rest
  // of the width to nothing. Half the width fixes it and spends the other
  // half on what is actually scheduled.
  testWidgets('Schedule puts the month beside the queue, and it fits', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in kIpadViewports.followedBy(<DeviceView>[
        kPhone,
      ])) {
        await bootConsole(tester, view: view);
        await tapTab(tester, 'SCHEDULE');
        final Rect calendar = _rectOf(
          find.byType(CdScheduleCalendar).evaluate().single,
        );
        final Rect queue = _rectOf(find.byType(ConEmpty).evaluate().single);
        final double workspace = workspaceRect(tester).height;
        final bool wide = SandLayout.isWide(view.logical.width);
        debugPrint(
          'MEASURED $view calendar '
          '${calendar.width.toStringAsFixed(0)}x'
          '${calendar.height.toStringAsFixed(0)}'
          ' at x=${calendar.left.toStringAsFixed(0)}'
          '  queue at x=${queue.left.toStringAsFixed(0)}'
          '  workspace height ${workspace.toStringAsFixed(0)}',
        );
        expect(
          calendar.height,
          lessThan(workspace),
          reason: '$view: a month must not be taller than the screen',
        );
        if (wide) {
          expect(
            calendar.width,
            closeTo(view.logical.width / 2, 1),
            reason: '$view: the month takes half the width',
          );
          expect(
            queue.left,
            greaterThanOrEqualTo(calendar.right - 0.5),
            reason: '$view: the queue is beside the month, not under it',
          );
        } else {
          expect(
            calendar.width,
            view.logical.width,
            reason: '$view: the phone calendar still spans the screen',
          );
          expect(
            queue.top,
            greaterThanOrEqualTo(calendar.bottom - 0.5),
            reason: '$view: the phone stacks them, as it shipped',
          );
        }
        expect(_drain(tester), isEmpty, reason: '$view');
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // Shipped, MEASURED at 1366x1024: the editor, the generator and the flyer
  // composer were each a single form — 1366 pt wide before build 52, then 704
  // pt centred with 662 pt of nothing beside it. They are the same shape as
  // each other: the thing, and the controls that change it.
  testWidgets('the editor, generator and composer are two panes on an iPad', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[
        kIpadMini,
        kIpad129,
        kIpad129Landscape,
      ]) {
        await bootConsole(tester, view: view);

        Future<void> check(String what, Finder page) async {
          final List<Rect> panes = <Rect>[
            _rectOf(_paneKey('primary').evaluate().single),
            _rectOf(_paneKey('secondary').evaluate().single),
          ];
          debugPrint(
            'MEASURED $view $what  page '
            '${tester.getSize(page).width.toStringAsFixed(0)} wide'
            '  left pane ${panes.first.width.toStringAsFixed(0)}'
            ' at x=${panes.first.left.toStringAsFixed(0)}'
            '  right pane ${panes.last.width.toStringAsFixed(0)}'
            ' at x=${panes.last.left.toStringAsFixed(0)}',
          );
          _expectTiled(panes, view.logical.width, what: '$view $what');
          expect(_drain(tester), isEmpty, reason: '$view $what');
        }

        await tapTab(tester, 'STUDIO');
        await tester.tap(find.text('Make variations'));
        await tester.pumpAndSettle();
        await check('editor', find.byType(NativeReelEditor));
        await popRoute(tester);

        await tapTab(tester, 'STUDIO');
        await tester.tap(find.text('Request a reel'));
        await tester.pumpAndSettle();
        await check('generator', find.byType(GenerationPage));
        await popRoute(tester);

        await tapTab(tester, 'STUDIO');
        await tester.tap(find.text('Make a flyer'));
        await tester.pumpAndSettle();
        await check('flyer composer', find.byType(FlyerComposerPage));
        await popRoute(tester);
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // The same three screens on a phone: one list, in the order that shipped,
  // and no pane at all.
  testWidgets('the same three screens are one column at every phone width', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[
        kPhone,
        kSplitNarrow,
        kSplitWide,
      ]) {
        await bootConsole(tester, view: view);
        for (final String action in <String>[
          'Make variations',
          'Request a reel',
          'Make a flyer',
        ]) {
          await tapTab(tester, 'STUDIO');
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(
            _paneKey('primary'),
            findsNothing,
            reason: '$view $action is not split',
          );
          expect(
            _paneKey('secondary'),
            findsNothing,
            reason: '$view $action is not split',
          );
          expect(_drain(tester), isEmpty, reason: '$view $action');
          await popRoute(tester);
        }
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // Shipped: the reel full bleed with a 704 pt deck of controls centred under
  // it. The reel is still the content and still full bleed — it simply stops
  // having 1366 pt of buttons under it and gets a rail beside it instead,
  // wherever there is room for both.
  testWidgets('the player puts its deck beside the reel where there is room', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[
        kPhone,
        kIpadMini,
        kIpad11,
        kIpad129,
        kIpadMiniLandscape,
        kIpad129Landscape,
      ]) {
        await bootConsole(tester, view: view);
        await tester.tap(reelRows.first);
        await tester.pumpAndSettle();
        expect(find.byType(ReelView), findsOneWidget);
        final Rect player = _rectOf(find.byType(ReelView).evaluate().single);
        final Rect deck = _rectOf(
          find.byKey(const ValueKey<String>('player-deck')).evaluate().single,
        );
        final bool rail = SandLayout.isRoomy(view.logical.width);
        debugPrint(
          'MEASURED $view  player ${player.width.toStringAsFixed(0)}'
          '  deck ${deck.width.toStringAsFixed(0)} pt'
          ' at x=${deck.left.toStringAsFixed(0)}'
          '  ${rail ? 'rail' : 'stacked'}',
        );
        expect(
          player.width,
          view.logical.width,
          reason: '$view: the reel is not letterboxed',
        );
        if (rail) {
          expect(
            deck.right,
            closeTo(view.logical.width, 0.5),
            reason: '$view: the rail is against the right edge',
          );
          expect(
            deck.top,
            closeTo(0, 0.5),
            reason: '$view: and runs the full height beside the reel',
          );
          expect(
            deck.width,
            inInclusiveRange(340, 448),
            reason: '$view: a rail is a rail, not a second screen',
          );
        } else {
          // Stacked, the deck's box is the width of the screen and its
          // content is the capped column inside it — which is what shipped,
          // and the one cap that survives on this screen.
          final Rect column = tester.getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey<String>('player-deck')),
                  matching: find.byType(ConstrainedBox),
                )
                .first,
          );
          expect(
            column.width,
            lessThanOrEqualTo(SandLayout.readable),
            reason: '$view: stacked under the reel, as it shipped',
          );
          expect(
            deck.bottom,
            closeTo(view.logical.height, 0.5),
            reason: '$view: at the bottom of the screen',
          );
        }
        expect(_drain(tester), isEmpty, reason: '$view');
        await popRoute(tester);
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // -------------------------------------------------------------------------
  // 4. The three places a cap survives.
  // -------------------------------------------------------------------------

  // Shipped, MEASURED: the row-overflow sheet was 1366 pt wide on a 12.9" in
  // landscape, with its title at x=16 and its close button at x=1310. A sheet
  // is a focused question and stays capped.
  testWidgets('a sheet is capped and centred rather than spanning the glass', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[
        kPhone,
        kIpadMini,
        kIpad129Landscape,
      ]) {
        await bootConsole(tester, view: view);
        await tester.tap(
          find
              .byWidgetPredicate(
                (Widget w) => w is ConIconButton && w.semanticLabel == 'More',
              )
              .first,
        );
        await tester.pumpAndSettle();
        final Rect sheet = tester.getRect(find.byType(ConSheet));
        debugPrint(
          'MEASURED $view sheet ${sheet.width.toStringAsFixed(0)} wide'
          ' at x=${sheet.left.toStringAsFixed(0)}',
        );
        expect(sheet.width, lessThanOrEqualTo(SandLayout.sheet));
        expect(
          sheet.center.dx,
          closeTo(view.logical.width / 2, 0.5),
          reason: '$view: a sheet stays centred',
        );
        expect(_drain(tester), isEmpty, reason: '$view sheet');
        await popRoute(tester);
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // The phone-import, profile-manager and editor-library sheets are Material
  // showModalBottomSheet calls rather than ConSheet, so they take the cap
  // through `constraints:` instead.
  testWidgets('a Material bottom sheet is capped and centred too', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      for (final DeviceView view in <DeviceView>[kPhone, kIpad129Landscape]) {
        await bootConsole(tester, view: view);
        await tapTab(tester, 'STUDIO');
        await tester.tap(find.text('Add from phone'));
        await tester.pumpAndSettle();
        final Rect content = tester.getRect(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(ConstrainedBox),
              )
              .first,
        );
        debugPrint(
          'MEASURED $view phone-import sheet '
          '${content.width.toStringAsFixed(0)} wide'
          ' at x=${content.left.toStringAsFixed(0)}',
        );
        expect(content.width, lessThanOrEqualTo(SandLayout.sheet));
        expect(content.center.dx, closeTo(view.logical.width / 2, 0.5));
        expect(_drain(tester), isEmpty, reason: '$view');
        await popRoute(tester);
      }
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // The tutorial is a single block of body prose with one illustration. It is
  // the one pushed page where a cap is still the right answer, and it keeps
  // one deliberately.
  testWidgets('the tutorial is still a capped column of prose', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, view: kIpad129Landscape);
      await tapTab(tester, 'ACCOUNTS');
      await tester.scrollUntilVisible(find.text('Replay tutorial'), 200);
      await tester.tap(find.text('Replay tutorial'));
      await tester.pumpAndSettle();
      final Rect column = tester.getRect(
        find
            .descendant(
              of: find
                  .descendant(
                    of: find.byType(TutorialPage),
                    matching: find.byType(ConColumn),
                  )
                  .first,
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      debugPrint(
        'MEASURED tutorial column ${column.width.toStringAsFixed(0)} wide'
        ' at x=${column.left.toStringAsFixed(0)}',
      );
      expect(column.width, SandLayout.readable);
      expect(
        column.center.dx,
        closeTo(kIpad129Landscape.logical.width / 2, 0.5),
      );
      expect(_drain(tester), isEmpty);
      await popRoute(tester);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // -------------------------------------------------------------------------
  // 5. Team: a roster of cards, and a conversation that keeps it beside it.
  // -------------------------------------------------------------------------

  group('Team', () {
    Map<String, dynamic> threads(int count) => <String, dynamic>{
      'account': '@zionboggan',
      'accounts': <String>['@zionboggan'],
      'role': 'owner',
      'threads': <dynamic>[
        for (int i = 0; i < count; i++)
          <String, dynamic>{
            'thread_id': 'bot-$i::@zionboggan',
            'bot_id': 'bot-$i',
            'role_title': 'Operator $i',
            'account': '@zionboggan',
            'scope_kind': 'all_accounts',
            'message_count': 1,
            'reply_count': 0,
            'open_count': 0,
            'last_at': '2026-09-12T12:36:45.000000Z',
            'last_state': 'queued',
            'last_delivery': 'queued',
            'last_preview': 'Give me the queue picture',
          },
      ],
    };

    Future<void> boot(WidgetTester tester, DeviceView view) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = view.logical * 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(
            body: TeamPanel(
              account: '@zionboggan',
              getJson: (String path) async =>
                  path.startsWith('/reels/team/threads')
                  ? threads(6)
                  : <String, dynamic>{
                      ...(threads(6)['threads'] as List<dynamic>).first
                          as Map<String, dynamic>,
                      'messages': <dynamic>[],
                    },
              postJson: (String path, Map<String, dynamic> body) async =>
                  <String, dynamic>{},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder crewCards() => find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('crew:'),
    );

    for (final DeviceView view in <DeviceView>[
      kPhone,
      kIpadMini,
      kIpad129Landscape,
    ]) {
      testWidgets('$view roster is a grid of the width it is given', (
        WidgetTester tester,
      ) async {
        await boot(tester, view);
        final List<Rect> row = _row(_rects(crewCards()));
        debugPrint(
          'MEASURED $view  ${row.length} crew cards per row'
          '  card ${row.first.width.toStringAsFixed(0)}',
        );
        expect(row, hasLength(SandLayout.columnsFor(view.logical.width)));
        expect(_drain(tester), isEmpty);
      });
    }

    testWidgets('an open conversation keeps the roster beside it at width', (
      WidgetTester tester,
    ) async {
      await boot(tester, kIpad129Landscape);
      await tester.tap(find.text('Operator 0').first);
      await tester.pumpAndSettle();
      final List<Rect> row = _row(_rects(crewCards()));
      debugPrint(
        'MEASURED iPad Pro 12.9 landscape open thread'
        '  roster rail card ${row.first.width.toStringAsFixed(0)} pt'
        ' at x=${row.first.left.toStringAsFixed(0)}'
        '..${row.first.right.toStringAsFixed(0)}'
        '  ${row.length} card per row in the rail',
      );
      expect(row, hasLength(1), reason: 'the rail is one card wide');
      expect(
        row.single.left,
        closeTo(12, 1),
        reason: 'the rail is on the left',
      );
      expect(
        row.single.right,
        lessThan(340),
        reason: 'and the conversation gets the rest',
      );
      expect(_drain(tester), isEmpty);
    });

    testWidgets('a phone still swaps the roster for the conversation', (
      WidgetTester tester,
    ) async {
      await boot(tester, kPhone);
      await tester.tap(find.text('Operator 0').first);
      await tester.pumpAndSettle();
      expect(crewCards(), findsNothing);
      expect(_drain(tester), isEmpty);
    });
  });
}
