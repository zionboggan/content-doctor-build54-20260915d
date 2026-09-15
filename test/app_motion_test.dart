import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_motion.dart';
import 'package:iris/console_shell.dart';

Widget host(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('counter rolls changed digits but announces only current count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const CdAnimatedCount(value: 19)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(const CdAnimatedCount(value: 20)));
    expect(find.bySemanticsLabel('20'), findsOneWidget);
    expect(find.bySemanticsLabel('19'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('9'), findsNothing);
    await tester.pumpWidget(
      host(const CdAnimatedCount(value: 100), reduced: true),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('100'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    semantics.dispose();
  });
  testWidgets('zero-duration entry is fully visible', (tester) async {
    await tester.pumpWidget(
      host(const CdEnter(duration: Duration.zero, child: Text('Ready'))),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(CdEnter),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
  });
  testWidgets('data pulse starts only on a changed value and settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CdChangePulse(value: 12, child: Text('12'))),
    );
    expect(
      tester
          .widget<Transform>(
            find.descendant(
              of: find.byType(CdChangePulse),
              matching: find.byType(Transform),
            ),
          )
          .transform
          .storage[0],
      1,
    );
    await tester.pumpWidget(
      host(const CdChangePulse(value: 13, child: Text('13'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('13'), findsOneWidget);
    expect(find.text('12'), findsNothing);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      host(const CdChangePulse(value: 13, child: Text('13'))),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets('rejected action moves once and reduced motion remains still', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CdRejectShake(rejection: null, child: Text('Action'))),
    );
    await tester.pumpWidget(
      host(const CdRejectShake(rejection: 1, child: Text('Action'))),
    );
    await tester.pump(const Duration(milliseconds: 38));
    final finder = find.descendant(
      of: find.byType(CdRejectShake),
      matching: find.byType(Transform),
    );
    expect(tester.widget<Transform>(finder).transform.storage[12], lessThan(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      host(
        const CdRejectShake(rejection: 2, child: Text('Action')),
        reduced: true,
      ),
    );
    expect(tester.widget<Transform>(finder).transform.storage[12], 0);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets('entry completes once and does not replay when data refreshes', (
    tester,
  ) async {
    await tester.pumpWidget(host(const CdEnter(child: Text('Ready'))));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(const CdEnter(child: Text('Updated'))));
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(CdEnter),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
  });

  testWidgets(
    'Reduce Motion shows entry immediately without delayed visibility',
    (tester) async {
      await tester.pumpWidget(
        host(
          const CdEnter(
            delay: Duration(milliseconds: 240),
            child: Text('Ready'),
          ),
          reduced: true,
        ),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(CdEnter),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        1,
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('press feedback preserves one real button action', (
    tester,
  ) async {
    int calls = 0;
    await tester.pumpWidget(
      host(
        Center(
          child: ConButton(label: 'Approve', onPressed: () => calls++),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Approve')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .97);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('loading shimmer settles and does not run forever', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ConSkeletonRow()));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet remains dismissible with reduced motion', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showConSheet(
              context,
              (_) =>
                  const ConSheet(title: 'Options', children: [Text('Content')]),
            ),
            child: const Text('Open'),
          ),
        ),
        reduced: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Content'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Content'), findsNothing);
  });
}
