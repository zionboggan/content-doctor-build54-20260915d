import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/schedule_calendar.dart';

void main() {
  Widget calendar({
    required DateTime? selected,
    required ValueChanged<DateTime?> onSelected,
    bool reduced = false,
    DateTime? today,
  }) => MaterialApp(
    theme: studioTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: CdScheduleCalendar(
        // The widget appends ', today' to a day cell's semantics label when
        // the date is today. Letting `today` default to DateTime.now() made
        // every label assertion below pass or fail according to the calendar
        // date the suite happened to run on. The caller owns the Phoenix wall
        // clock in production too, so the fixture owns it here.
        today: today ?? DateTime(2026, 9, 1),
        scheduledDays: <DateTime>[
          DateTime(2026, 9, 15, 9, 30),
          DateTime(2026, 9, 20, 18, 40),
          DateTime(2026, 9, 20, 20),
        ],
        selectedDay: selected,
        onSelected: onSelected,
      ),
    ),
  );

  testWidgets('selected day springs while reduced motion stays still', (
    tester,
  ) async {
    await tester.pumpWidget(
      calendar(selected: DateTime(2026, 9, 15), onSelected: (_) {}),
    );
    await tester.pumpAndSettle();
    Finder selectedCell() => find.bySemanticsLabel(
      'Tuesday, September 15, 2026, scheduled, selected',
    );
    Finder scale() => find.descendant(
      of: selectedCell(),
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(scale()).scale, 1.08);
    await tester.pumpWidget(
      calendar(
        selected: DateTime(2026, 9, 15),
        onSelected: (_) {},
        reduced: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scale()).scale, 1);
    expect(tester.widget<AnimatedScale>(scale()).duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects actual schedule dates and toggles the selected filter', (
    WidgetTester tester,
  ) async {
    DateTime? selected = DateTime(2026, 9, 15);
    await tester.pumpWidget(
      calendar(
        selected: selected,
        onSelected: (DateTime? day) => selected = day,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Tuesday, September 15, 2026, scheduled, selected'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Sunday, September 20, 2026, scheduled'),
      findsOneWidget,
    );

    await tester.tap(
      find.bySemanticsLabel('Sunday, September 20, 2026, scheduled'),
    );
    expect(selected, DateTime(2026, 9, 20));

    await tester.pumpWidget(
      calendar(
        selected: selected,
        onSelected: (DateTime? day) => selected = day,
      ),
    );
    await tester.tap(
      find.bySemanticsLabel('Sunday, September 20, 2026, scheduled, selected'),
    );
    expect(selected, isNull);
  });

  // The suite used to change verdict with the calendar date: the day cell
  // appends ', today' from its own clock, so on 15 September 2026 every label
  // assertion above failed. Today is now an input, and this test pins the
  // behaviour from both sides so a default can never creep back in.
  testWidgets('the today marker follows the injected day, not the system day', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      calendar(
        selected: null,
        onSelected: (_) {},
        today: DateTime(2026, 9, 15),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Tuesday, September 15, 2026, scheduled, today'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Sunday, September 20, 2026, scheduled'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      calendar(
        selected: null,
        onSelected: (_) {},
        today: DateTime(2026, 9, 20),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Tuesday, September 15, 2026, scheduled'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Sunday, September 20, 2026, scheduled, today'),
      findsOneWidget,
    );
  });

  testWidgets('month navigation and All dates do not invent schedule counts', (
    WidgetTester tester,
  ) async {
    DateTime? selected = DateTime(2026, 9, 15);
    await tester.pumpWidget(
      calendar(
        selected: selected,
        onSelected: (DateTime? day) => selected = day,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);

    await tester.tap(find.text('All dates'));
    expect(selected, isNull);
    expect(find.textContaining('reels'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
