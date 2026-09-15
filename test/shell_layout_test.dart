// The shell's contract with a tab body: you get the whole workspace.
//
// The second half-screen mechanism in this app has nothing to do with
// scrolling. The shell's AnimatedSwitcher was built with no `layoutBuilder`,
// so Flutter used AnimatedSwitcher.defaultLayoutBuilder — a loose-fit Stack
// centred on its children. Anything that shrink-wraps in the scroll axis
// therefore rendered as a short island floating in the middle of an 844 pt
// screen with dead ground above and below it. TeamPanel's failure state is a
// bare SingleChildScrollView, so a Team route that answers 503 produced
// exactly the screenshot Zion sends.
//
// All data is synthetic and no provider route, credential or network resource
// is used.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/console_shell.dart';
import 'package:iris/team_page.dart';

import 'support/console_harness.dart';

void main() {
  // A measurement kept because it refutes a prescribed fix. CD-07 in the
  // 2026-09-15 register says ConTabBar should read MediaQuery.paddingOf
  // instead of viewPaddingOf, on the grounds that Scaffold has already lifted
  // the bar above viewInsets.bottom so the home indicator is counted twice.
  //
  // MEASURED at 390x844 with a 34 pt bottom safe area:
  //   shipped, viewPaddingOf   ConTabBar 57.0 with and without a keyboard
  //   proposed, paddingOf      ConTabBar 91.0 with and without a keyboard
  // Scaffold hands its bottomNavigationBar a MediaQuery with removeViewInsets
  // applied, which restores padding.bottom to the full safe area, so the
  // proposed change does not remove a band — it adds one, 34 pt of it, at
  // rest, on every screen. Neither getter varies with the keyboard, so
  // neither is the double count described. Left alone; this test holds the
  // invariant that actually matters.
  testWidgets('the tab bar band is the same either way, measured', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, settle: false);
        final double atRest = tester.getSize(find.byType(ConTabBar)).height;

        tester.view.viewInsets = const FakeViewPadding(bottom: 672);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        final double withKeyboard = tester
            .getSize(find.byType(ConTabBar))
            .height;

        debugPrint('MEASURED ConTabBar height');
        debugPrint('  no keyboard  $atRest');
        debugPrint('  keyboard up  $withKeyboard');
        expect(withKeyboard, atRest);
      },
      createHttpClient: (SecurityContext? c) =>
          FakeGateway(catalog: reviewCatalog(count: 1)),
    );
  });

  testWidgets('a failed Team fills the workspace instead of floating in it', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, settle: false);
        await tapTab(tester, 'TEAM');

        expect(find.text('Team is unavailable'), findsOneWidget);

        final Rect workspace = workspaceRect(tester);
        final Rect body = tester.getRect(find.byType(TeamPanel));
        debugPrint('MEASURED Team failure state at 390x844');
        debugPrint(
          '  workspace  ${workspace.top} .. ${workspace.bottom}'
          '  h=${workspace.height}',
        );
        debugPrint(
          '  team body  ${body.top} .. ${body.bottom}'
          '  h=${body.height}',
        );

        // Team keeps its command bar fixed above it, so the region it owns
        // is the workspace below that bar. It must fill it, top to bottom.
        final Rect bar = tester.getRect(
          find.byKey(const ValueKey<String>('command-bar')),
        );
        expect(
          body.top,
          inInclusiveRange(bar.bottom, bar.bottom + 2),
          reason: 'flush under the command bar, not floated below it',
        );
        expect(
          body.bottom,
          workspace.bottom,
          reason: 'reaches the bottom of the workspace',
        );
      },
      createHttpClient: (SecurityContext? c) => FakeGateway(
        catalog: reviewCatalog(count: 1),
        failures: const <String, int>{'/reels/team': 503},
      ),
    );
  });

  testWidgets('every tab body is handed the full workspace height', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(
      () async {
        await bootConsole(tester, settle: false);
        for (final String tab in <String>[
          'REVIEW',
          'SCHEDULE',
          'STUDIO',
          'RESULTS',
          'ACCOUNTS',
          'TEAM',
        ]) {
          await tapTab(tester, tab);
          final Rect workspace = workspaceRect(tester);
          // The body is whatever the workspace's ColoredBox is wrapping, once
          // the transition has settled. Measuring the outermost render object
          // under it keeps this honest across later refactors of the switcher.
          final RenderBox box = tester.renderObject<RenderBox>(
            find
                .descendant(
                  of: find.byKey(const ValueKey<String>('workspace')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          final Rect body = box.localToGlobal(Offset.zero) & box.size;
          expect(
            body.bottom,
            workspace.bottom,
            reason: '$tab body must reach the bottom of the workspace',
          );
          if (tab != 'TEAM') {
            // These five tabs carry their chrome as slivers, so the scroll
            // view is the whole workspace. That is the 227 pt at text scale
            // 1.0, and 314 pt at 1.5, that the list gets back.
            expect(
              body.height,
              workspace.height,
              reason: '$tab scroll view must be the whole workspace',
            );
          }
          expect(tester.takeException(), isNull, reason: tab);
        }
      },
      createHttpClient: (SecurityContext? c) => FakeGateway(
        catalog: reviewCatalog(count: 1),
        failures: const <String, int>{'/reels/team': 503},
      ),
    );
  });
}
