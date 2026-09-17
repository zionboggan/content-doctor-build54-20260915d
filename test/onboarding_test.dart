// The first-run tour, and the promises it makes about the app.
//
// Two of these tests exist because the tour was built and then never shown:
// `shouldShowTutorial()` and `completeTutorial()` were written to gate a
// first launch and nothing called either of them, so the only way to the tour
// was Accounts -> Replay tutorial. A fresh install has to open it by itself,
// and a returning operator has to never be handed it again unasked. Both are
// checked against the real shell, booted over a fake gateway.
//
// All data is synthetic. No provider route, credential or network resource is
// used.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/flyer_composer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/console_harness.dart';

class _FlyerBackend {
  Future<dynamic> read(String path) async => path == '/flyers/renderer'
      ? <String, dynamic>{
          'reachable': true,
          'message': 'Render host is answering.',
        }
      : <String, dynamic>{'status': 'unknown'};

  Future<dynamic> write(String path, Map<String, dynamic> payload) async =>
      <String, dynamic>{'job_id': 'flyer-doc-1', 'status': 'queued'};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'first-run tour and persistent tips are independent preferences',
    () async {
      expect(await TutorialPreferences.shouldShowTutorial(), isTrue);
      expect(await TutorialPreferences.alwaysShowTips(), isFalse);
      await TutorialPreferences.completeTutorial();
      await TutorialPreferences.saveAlwaysShowTips(true);
      expect(await TutorialPreferences.shouldShowTutorial(), isFalse);
      expect(await TutorialPreferences.alwaysShowTips(), isTrue);
      await TutorialPreferences.saveAlwaysShowTips(false);
      expect(await TutorialPreferences.alwaysShowTips(), isFalse);
      expect(await TutorialPreferences.shouldShowTutorial(), isFalse);
    },
  );

  testWidgets('tour can be skipped immediately', (WidgetTester tester) async {
    int finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: TutorialPage(onFinish: () => finished++),
      ),
    );
    await tester.tap(find.text('Skip'));
    expect(finished, 1);
  });

  testWidgets('every tour step stays usable on a small phone with larger text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: TutorialPage(onFinish: () => finished++),
      ),
    );
    for (int index = 0; index < tutorialSteps.length; index++) {
      expect(find.text(tutorialSteps[index].title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.text(
          index == tutorialSteps.length - 1 ? 'Start reviewing' : 'Next',
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(finished, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contextual tip opens the replayable tour', (
    WidgetTester tester,
  ) async {
    int replayed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: ContextTip(section: 'Schedule', onHelp: () => replayed++),
        ),
      ),
    );
    expect(find.text('Choose the moment'), findsOneWidget);
    expect(
      find.textContaining('Each reel needs your confirmation.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Choose the moment'));
    expect(replayed, 1);
  });

  testWidgets(
    'full guide preserves the quick tour position and back navigation',
    (WidgetTester tester) async {
      int finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: TutorialPage(onFinish: () => finished++),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 7'), findsOneWidget);
      await tester.tap(find.text('Full guide'));
      await tester.pumpAndSettle();
      expect(find.text('Your field guide'), findsOneWidget);
      await tester.tap(find.text('Back to quick tour'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 7'), findsOneWidget);
      expect(find.text('Watch the whole reel'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Your content, your call'), findsOneWidget);
      expect(finished, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every full-guide chapter is readable with large text and reduced motion',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      int finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              disableAnimations: true,
              accessibleNavigation: true,
            ),
            child: child!,
          ),
          home: TutorialPage(onFinish: () => finished++),
        ),
      );
      await tester.tap(find.text('Full guide'));
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      for (final chapter in guideChapters) {
        await tester.scrollUntilVisible(
          find.text(chapter.title),
          180,
          scrollable: scroll,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(chapter.title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(chapter.title));
        await tester.pumpAndSettle();
        for (final paragraph in chapter.steps) {
          await tester.scrollUntilVisible(
            find.text(paragraph),
            140,
            scrollable: scroll,
          );
          await tester.pumpAndSettle();
          expect(find.text(paragraph), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.tap(find.text('Done'));
      expect(finished, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('guide covers all workspaces without promising unavailable sending', () {
    expect(guideChapters.length, 15);
    final copy = guideChapters.expand((chapter) => chapter.steps).join(' ');
    expect(copy, contains('Saving a draft does not send'));
    expect(copy, contains('Automatic replies are not active'));
    expect(copy, contains('Queued means waiting'));
    expect(copy, contains('Missing or stale data is not zero'));
    expect(copy, contains('250 MB'));
  });

  // ---------------------------------------------------------------------
  // PART 1: the tour has to reach a new user without being hunted for.
  // ---------------------------------------------------------------------

  testWidgets('a fresh install is shown the tour without asking for it', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, firstLaunch: true);
      // Nobody tapped anything. The tour is on screen because the catalog
      // loaded on a device that has never seen it.
      expect(find.byType(TutorialPage), findsOneWidget);
      expect(find.text('Your content, your call'), findsOneWidget);
      expect(find.text('Step 1 of ${tutorialSteps.length}'), findsOneWidget);
      // And it is not yet marked seen, because it has not been closed.
      expect(await TutorialPreferences.shouldShowTutorial(), isTrue);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  testWidgets('a returning operator is never handed the tour again', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      // The default boot is a device whose tutorial-seen flag is already set.
      await bootConsole(tester);
      expect(await TutorialPreferences.shouldShowTutorial(), isFalse);
      expect(find.byType(TutorialPage), findsNothing);
      // Still nothing after a refresh, which runs the same load path that
      // decides whether to show it.
      await tester.tap(find.bySemanticsLabel('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialPage), findsNothing);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  testWidgets('closing the tour is what makes it stop coming back', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester, firstLaunch: true);
      expect(find.byType(TutorialPage), findsOneWidget);
      // Skip is a dismissal, not a completion, and it still counts.
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialPage), findsNothing);
      expect(await TutorialPreferences.shouldShowTutorial(), isFalse);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  testWidgets('Replay tutorial still opens the tour for someone who saw it', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await bootConsole(tester);
      expect(find.byType(TutorialPage), findsNothing);
      await tapTab(tester, 'ACCOUNTS');
      await tester.scrollUntilVisible(find.text('Replay tutorial'), 200);
      // Center the row above the persistent bottom navigation before tapping.
      await Scrollable.ensureVisible(
        tester.element(find.text('Replay tutorial')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replay tutorial'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialPage), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialPage), findsNothing);
    }, createHttpClient: (SecurityContext? c) => FakeGateway());
  });

  // ---------------------------------------------------------------------
  // PART 2: what the tour says about the flyer composer has to be true.
  // ---------------------------------------------------------------------

  testWidgets('the flyer step describes the screen that is actually there', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FlyerComposerPage(
          accounts: const <String>['@zionboggan'],
          read: _FlyerBackend().read,
          write: _FlyerBackend().write,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final TutorialStep step = tutorialSteps.firstWhere(
      (TutorialStep step) => step.section == 'Flyers',
    );
    // "In Studio, choose Make a flyer" - that is the screen's own title, and
    // the Studio row that opens it carries the same words.
    expect(step.action, 'Studio · Create · Make a flyer');
    expect(find.text('Make a flyer'), findsOneWidget);
    // "Pick the account, name the flyer"
    expect(step.body, contains('Pick the account, name the flyer'));
    expect(find.byKey(const ValueKey<String>('flyer-account')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('flyer-deck-name')),
      findsOneWidget,
    );
    expect(find.text('Flyer name'), findsOneWidget);
    // "One slide is a flyer, two to ten slides are a carousel"
    expect(step.body, contains('One slide is a flyer'));
    expect(step.body, contains('two to ten slides are a carousel'));
    expect(
      find.text(
        'One slide is a flyer. Two to ten slides are a carousel. Every result '
        'waits for review.',
      ),
      findsOneWidget,
    );
    expect(flyerMaxSlides, 10);
    // "slide order is the posting order"
    expect(step.body, contains('slide order is the posting order'));
    expect(find.text('Slide order is the posting order.'), findsOneWidget);
    // "Render for review sends it to review, never to Instagram."
    expect(step.body, contains('Render for review'));
    expect(find.text('Render for review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the flyer guide chapter matches the composer control by control',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: FlyerComposerPage(
            accounts: const <String>['@zionboggan'],
            read: _FlyerBackend().read,
            write: _FlyerBackend().write,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final GuideChapter chapter = guideChapters.firstWhere(
        (GuideChapter chapter) => chapter.title == 'Make a flyer or carousel',
      );
      expect(chapter.location, 'Studio · Create · Make a flyer');
      final String copy = chapter.steps.join(' ');

      // Every control the chapter names is on the screen, by the name it uses.
      expect(copy, contains('destination account first'));
      expect(copy, contains('lowercase letters, numbers and hyphens'));
      expect(
        find.text('Lowercase letters, numbers and hyphens'),
        findsOneWidget,
      );
      expect(copy, contains('template and brand mark'));
      expect(find.text('Template'), findsOneWidget);
      expect(find.text('Brand mark'), findsOneWidget);
      expect(copy, contains('Add a hook, body or cta slide'));
      for (final String role in <String>['hook', 'body', 'cta']) {
        expect(find.text('Add $role'), findsOneWidget);
        expect(find.byKey(ValueKey<String>('flyer-add-$role')), findsOneWidget);
      }
      expect(copy, contains('move a slide up or down'));
      expect(find.byIcon(CupertinoIcons.arrow_up), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.arrow_down), findsOneWidget);
      expect(copy, contains('remove any slide except the last remaining one'));
      // One slide on open, and its remove control is disabled.
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(CupertinoIcons.delete),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(copy, contains('refused by name'));
      expect(
        find.text(
          'Off, a blank slot is refused by name. On, it renders as [SLOT]. '
          'Nothing is ever guessed for you.',
        ),
        findsOneWidget,
      );
      expect(copy, contains('template demo stamp'));
      expect(find.text('Stamp every slide as a template demo'), findsOneWidget);
      expect(copy, contains('Render for review'));
      expect(find.text('Render for review'), findsOneWidget);
      // The review-only promise, which is the whole reason the chapter exists.
      expect(copy, contains('review-only'));
      expect(copy, contains('no approve, schedule or publish path'));
      expect(find.text('Keep every result review-only.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('the tour covers every Studio create action the shell offers', () {
    final String tour = tutorialSteps
        .map((TutorialStep step) => '${step.title} ${step.body}')
        .join(' ');
    // The four CREATE rows in Studio: import, request, flyer, variations.
    expect(tour, contains('Import a video or audio file'));
    expect(tour, contains('request a reel'));
    expect(tour, contains('Make a flyer'));
    expect(tour, contains('make variations'));
  });

  test('the guide sends people to where Replay tutorial actually lives', () {
    final String copy = guideChapters
        .expand((GuideChapter chapter) => chapter.steps)
        .join(' ');
    final String tour = tutorialSteps
        .map((TutorialStep step) => step.body)
        .join(' ');
    // It is a Help row on the Accounts tab, not a row in the More sheet.
    expect(copy, contains('Accounts tab, under Help'));
    expect(copy, contains('Accounts → Replay tutorial'));
    expect(tour, contains('Accounts → Replay tutorial'));
    expect('$copy $tour', isNot(contains('More → Replay tutorial')));
    // And the tour now says it opens itself, because it does.
    expect(copy, contains('opens by itself the first time'));
  });
}
