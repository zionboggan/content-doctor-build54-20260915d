// Menus and sheets paint in the app's own type, not Flutter's fallback.
//
// `showConSheet` puts its content on an Overlay through `showGeneralDialog`.
// Nothing on that route is a `Material`, so the nearest `DefaultTextStyle` was
// `MaterialApp`'s `_errorTextStyle`: 48 pt w900 monospace (Courier on iOS),
// #D0FF0000, with a double #FFFF00 underline. Every `Ty.*` role except
// `Ty.caps` leaves `fontFamily` and `decoration` unset, so the sheets inherited
// the wrong face and the yellow rule underneath every label — the thing Zion
// kept calling "the yellow underline". It was never a style decision.
//
// These read the style off the RenderParagraph, which is the style the engine
// actually paints, not the style the widget asked for. Before the fix the ⋯
// sheet title resolved to `monospace` + `TextDecoration.underline` /
// #FFFF00 / `TextDecorationStyle.double`; after it resolves to Inter with no
// decoration, the same as identical text inside a Scaffold.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_theme.dart';
import 'package:iris/console_shell.dart';

import 'support/console_harness.dart';

/// `MaterialApp._errorTextStyle`'s underline colour.
const Color kFallbackYellow = Color(0xFFFFFF00);

/// `MaterialApp._errorTextStyle`'s face.
const String kFallbackFamily = 'monospace';

/// The style the engine paints for [finder], after the inherited
/// [DefaultTextStyle] has been merged in.
TextStyle paintedStyle(WidgetTester tester, Finder finder) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    finder,
  );
  return (paragraph.text as TextSpan).style!;
}

/// Asserts [text] is painted in the app's type rather than the fallback.
void expectAppType(WidgetTester tester, Finder finder, String reason) {
  final TextStyle style = paintedStyle(tester, finder);
  expect(
    style.fontFamily,
    isNot(kFallbackFamily),
    reason: '$reason: painted in Flutter\'s fallback monospace',
  );
  expect(
    style.fontFamily,
    SandType.sans,
    reason: '$reason: not the app\'s Inter',
  );
  expect(
    style.decoration ?? TextDecoration.none,
    TextDecoration.none,
    reason: '$reason: carries a decoration nothing asked for',
  );
  expect(
    style.decorationColor,
    isNot(kFallbackYellow),
    reason: '$reason: still underlined in fallback yellow',
  );
  expect(
    style.decorationStyle,
    isNot(TextDecorationStyle.double),
    reason: '$reason: still carries the double fallback rule',
  );
}

/// The text of the topmost open [ConSheet].
Finder inTopSheet(String text) => find.descendant(
  of: find.byType(ConSheet).last,
  matching: find.text(text),
);

Widget _host(WidgetBuilder sheet) => MaterialApp(
  theme: studioTheme(),
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) => Center(
        child: TextButton(
          onPressed: () => showConSheet<void>(context, sheet),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, WidgetBuilder sheet) async {
  await tester.pumpWidget(_host(sheet));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tapRow(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _reel(
  String id, {
  String status = 'ready_for_review',
  Map<String, dynamic>? review,
}) => <String, dynamic>{
  'id': id,
  'sha256': 'sha-$id',
  'account': '@zionboggan',
  'title': 'Yacht sequence $id',
  'caption': 'A caption for $id',
  'status': status,
  'duration_seconds': 23,
  'created_at': kPinnedNow.subtract(const Duration(hours: 3)).toIso8601String(),
  'review': ?(review == null
      ? null
      : <String, dynamic>{
          'id': id,
          'sha256': 'sha-$id',
          'account': '@zionboggan',
          'caption': 'A caption for $id',
          ...review,
        }),
};

final List<Map<String, dynamic>> _catalog = <Map<String, dynamic>>[
  _reel('forreview'),
  _reel('approved', review: <String, dynamic>{'state': 'review_approved'}),
];

FakeGateway _gateway() => FakeGateway(catalog: _catalog);

/// "All" rather than "Needs you", so the approved reel is listed too.
Future<void> _showAll(WidgetTester tester) async {
  await tester.tap(find.text('All').first);
  await tester.pumpAndSettle();
}

Finder get _workspaceButton => find.byWidgetPredicate(
  (Widget w) => w is ConIconButton && w.semanticLabel == 'More',
);

// The account chip annotates a subtree rather than owning a node, so its
// semantics label merges with the account name it shows. Match the widget.
Finder get _accountChip => find.byWidgetPredicate(
  (Widget w) => w is Semantics && w.properties.label == 'Account scope',
);

void main() {
  // --- The shared root --------------------------------------------------

  testWidgets('a sheet built by showConSheet is not on the fallback style', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      (BuildContext sheet) => const ConSheet(
        title: 'Yacht sequence v1',
        children: <Widget>[
          ConSheetRow(label: 'Rate'),
          Caps('Pick a time'),
        ],
      ),
    );
    expectAppType(tester, inTopSheet('Yacht sequence v1'), 'sheet title');
    expectAppType(tester, inTopSheet('Rate'), 'sheet row label');
    expectAppType(tester, inTopSheet('PICK A TIME'), 'sheet caps header');
  });

  testWidgets('a sheet opened from inside a sheet inherits it too', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      (BuildContext outer) => ConSheet(
        title: 'Yacht sequence v1',
        children: <Widget>[
          ConSheetRow(
            label: 'Rate',
            onTap: () => showConSheet<void>(
              outer,
              (BuildContext inner) => const ConSheet(
                title: 'Rate',
                children: <Widget>[ConSheetRow(label: 'Four stars')],
              ),
            ),
          ),
        ],
      ),
    );
    await _tapRow(tester, 'Rate');
    expect(find.byType(ConSheet), findsNWidgets(2));
    expectAppType(tester, inTopSheet('Four stars'), 'nested sub-sheet row');
  });

  testWidgets('a sheet that is a bare container, the _pickTime shape, too', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      (BuildContext sheet) => Container(
        color: Con.surface1,
        child: const SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Rule(strong: true),
              SizedBox(height: 44, child: Caps('Pick a time')),
            ],
          ),
        ),
      ),
    );
    expectAppType(tester, find.text('PICK A TIME'), '_pickTime header');
  });

  testWidgets('the Material wrapper adds no surface of its own', (
    WidgetTester tester,
  ) async {
    await _open(
      tester,
      (BuildContext sheet) => const ConSheet(
        title: 'Yacht sequence v1',
        children: <Widget>[ConSheetRow(label: 'Rate')],
      ),
    );
    // The sheet sits where it sat: bottom-centred, capped, unchanged in size.
    final Rect sheet = tester.getRect(find.byType(ConSheet));
    expect(sheet.bottom, tester.getRect(find.byType(Overlay)).bottom);
    // Nothing between the route and the sheet paints a colour. A transparent
    // Material is the only Material on the route above the sheet's own
    // Container, so the scrim still reads through everywhere the sheet is not.
    for (final Material material in tester
        .widgetList<Material>(
          find.ancestor(
            of: find.byType(ConSheet),
            matching: find.byType(Material),
          ),
        )
        .where((Material m) => m.type != MaterialType.canvas)) {
      expect(material.type, MaterialType.transparency);
      expect(material.elevation, 0);
    }
  });

  // --- Every named surface, in the real shell ---------------------------

  testWidgets('Workspace, Account and Filter and sort render in Inter', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);

        await tester.tap(_workspaceButton.first);
        await tester.pumpAndSettle();
        expectAppType(tester, inTopSheet('Workspace'), 'Workspace title');
        expectAppType(tester, inTopSheet('Inbox'), 'Workspace row');
        await popRoute(tester);

        await tester.tap(_accountChip.first);
        await tester.pumpAndSettle();
        expectAppType(tester, inTopSheet('Account'), 'Account title');
        await popRoute(tester);

        await tester.tap(find.bySemanticsLabel('Filter and sort').first);
        await tester.pumpAndSettle();
        expectAppType(
          tester,
          inTopSheet('Filter and sort'),
          'Filter and sort title',
        );
        expectAppType(tester, inTopSheet('SHOW'), 'Filter and sort group');
        await popRoute(tester);
      },
      createHttpClient: (SecurityContext? c) => _gateway(),
    );
  });

  testWidgets('the reel ⋯ menu and its sub-sheets render in Inter', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        await _showAll(tester);

        await tester.tap(find.bySemanticsLabel('More actions').first);
        await tester.pumpAndSettle();
        expectAppType(tester, inTopSheet('Rate'), '⋯ menu row');
        expectAppType(tester, inTopSheet('Details'), '⋯ menu row');
        expectAppType(tester, inTopSheet('Notes'), '⋯ menu row');

        // Rate, Caption, Notes and Details are sub-sheets of the ⋯ menu: each
        // pops it and opens its own showConSheet route.
        for (final List<String> hop in <List<String>>[
          <String>['Rate', 'Rate'],
          <String>['Edit caption', 'Caption'],
          <String>['Notes', 'Notes'],
          <String>['Details', 'Details'],
        ]) {
          await tester.tap(inTopSheet(hop.first));
          await tester.pumpAndSettle();
          expectAppType(tester, inTopSheet(hop.last), '${hop.last} sub-sheet');
          await popRoute(tester);
          await tester.tap(find.bySemanticsLabel('More actions').first);
          await tester.pumpAndSettle();
        }
        await popRoute(tester);
      },
      createHttpClient: (SecurityContext? c) => _gateway(),
    );
  });

  testWidgets('Schedule and its Pick a time sub-menu render in Inter', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester);
        await _showAll(tester);

        await tester.tap(
          find.descendant(
            of: reelRow('approved'),
            matching: find.text('Schedule'),
          ),
        );
        await tester.pumpAndSettle();
        // 'Schedule' is both the sheet title and its commit button.
        expectAppType(tester, inTopSheet('Schedule').first, 'Schedule title');
        expectAppType(tester, inTopSheet('Pick a time'), 'Schedule row');

        await tester.tap(inTopSheet('Pick a time'));
        await tester.pumpAndSettle();
        expectAppType(tester, find.text('PICK A TIME'), '_pickTime header');
        await popRoute(tester);
        await popRoute(tester);
      },
      createHttpClient: (SecurityContext? c) => _gateway(),
    );
  });
}
