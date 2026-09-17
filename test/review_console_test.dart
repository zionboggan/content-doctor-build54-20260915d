// Fold-budget and disclosure checks for the Review screen.
//
// A 200 is not proof and neither is a compile. These render the real shell at
// 390x844 against a 162-item catalog and measure what a phone would show: the
// y of the first reel row, how many controls sit above it, how many rows the
// list actually builds, and that no video player exists outside the Reel view.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart' show tutorialSeenKey;
import 'package:iris/console_shell.dart';
import 'package:iris/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

// A 1x1 PNG, so a poster request resolves the way it does on the device.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
  'IQAAAABJRU5ErkJggg==',
);

const int catalogSize = 162;

List<Map<String, dynamic>> _catalog() => List<Map<String, dynamic>>.generate(
  catalogSize,
  (int i) => <String, dynamic>{
    'id': 'reel$i',
    'sha256': 'sha$i',
    'account': i.isEven ? '@zionboggan' : '@barcrawling',
    'title': 'Yacht sequence v$i',
    'caption': 'A caption for reel $i',
    'status': 'ready_for_review',
    'duration_seconds': 23,
    'created_at': '2026-09-1${i % 3}T14:02:00Z',
  },
);

class _Headers implements HttpHeaders {
  final Map<String, String> _values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = '$value';
  @override
  String? value(String name) => _values[name.toLowerCase()];
  @override
  ContentType? contentType;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes, this.code);
  final List<int> bytes;
  final int code;

  @override
  int get statusCode => code;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.method);
  @override
  final Uri uri;
  @override
  final String method;
  final _Headers _headers = _Headers();
  final List<int> _body = <int>[];

  @override
  HttpHeaders get headers => _headers;
  @override
  bool followRedirects = true;
  @override
  void add(List<int> data) => _body.addAll(data);
  @override
  void write(Object? object) => _body.addAll(utf8.encode('$object'));

  @override
  Future<HttpClientResponse> close() async {
    final String path = uri.path;
    if (path.endsWith('.poster')) return _Response(_png, 200);
    final Object body = switch (path) {
      '/trial-auth' => <String, dynamic>{
        'authenticated': true,
        'role': 'owner',
      },
      '/reels/catalog' => _catalog(),
      '/reels/controls' => <String, dynamic>{'accounts': <dynamic>[]},
      '/reels/schedules' => <String, dynamic>{'entries': <dynamic>[]},
      '/reels/oauth/status' => <String, dynamic>{
        'accounts': <dynamic>[
          <String, dynamic>{
            'account': '@zionboggan',
            'connected': true,
            'enabled': true,
          },
          <String, dynamic>{
            'account': '@barcrawling',
            'connected': true,
            'enabled': true,
          },
        ],
      },
      '/reels/revision-status' => <String, dynamic>{},
      _ => <String, dynamic>{},
    };
    return _Response(utf8.encode(jsonEncode(body)), 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Client implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(url, 'GET');
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request(url, 'POST');
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(url, method);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Every control the platform would announce as a button, in tree order.
/// Counted from the widget tree rather than the semantics tree because the
/// semantics owner accessors are deprecated and this measures the same thing:
/// what a screen reader, and therefore the operator, is offered.
Finder get _semanticButtons => find.byWidgetPredicate(
  (Widget w) => w is Semantics && w.properties.button == true,
);

int _buttonsAbove(WidgetTester tester, double y) {
  int count = 0;
  for (final Element element in _semanticButtons.evaluate()) {
    final RenderObject? box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    if (box.localToGlobal(Offset.zero).dy < y) count++;
  }
  return count;
}

Future<void> _boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: 94, bottom: 68);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{
    tutorialSeenKey: true,
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('trial_reels/credentials'),
        (MethodCall call) async => call.method == 'read' ? 'test-token' : null,
      );
  // AppLinks (OAuth deep links): mock native channels for widget tests.
  // messages is a MethodChannel (getInitialLink -> null);
  // events is an EventChannel (uriLinkStream never emits).
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.app_links/messages'),
        (MethodCall call) async => null,
      );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
        const EventChannel('com.llfbandit.app_links/events'),
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {},
        ),
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('trial_reels/credentials'),
          null,
        ),
  );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/messages'),
          null,
        ),
  );

  await tester.pumpWidget(
    const RepaintBoundary(
      key: ValueKey('screenshot-console'),
      child: TrialReelsApp(),
    ),
  );
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Finder get _rows => find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('reel-row-'),
);

void main() {
  testWidgets('screenshot overlay preserves navigation and larger text', (
    tester,
  ) async {
    for (final entry in <String, String>{
      'Inter': 'assets/fonts/Inter-Variable.ttf',
      'JetBrains Mono': 'assets/fonts/JetBrainsMono-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DoctorAvatar), findsNWidgets(2));
      expect(find.bySemanticsLabel('Search content'), findsOneWidget);
      for (final tab in ['Review', 'Schedule', 'Studio', 'Accounts']) {
        await tester.tap(find.text(tab.toUpperCase()).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
        if (const bool.fromEnvironment('CAPTURE_SCREENSHOTS')) {
          await expectLater(
            find.byKey(const ValueKey('screenshot-console')),
            matchesGoldenFile('previews/${tab.toLowerCase()}_overlay.png'),
          );
        }
      }
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final tab in ['Review', 'Schedule', 'Studio', 'Accounts']) {
        await tester.tap(find.text(tab.toUpperCase()).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab large text');
      }
    }, createHttpClient: (_) => _Client());
  });
  testWidgets('fold budget, measured and printed', (WidgetTester tester) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      final double first = tester.getTopLeft(_rows.first).dy;
      final Size row = tester.getSize(_rows.first);
      debugPrint('MEASURED 390x844 DPR2, 162 assets');
      debugPrint('  first reel row top        ${first.toStringAsFixed(1)}');
      debugPrint(
        '  reel row height           ${row.height.toStringAsFixed(1)}',
      );
      debugPrint('  reel row width            ${row.width.toStringAsFixed(1)}');
      debugPrint('  controls above first row  ${_buttonsAbove(tester, first)}');
      debugPrint('  reel rows built           ${_rows.evaluate().length}');
      debugPrint(
        '  video players in the list ${find.byType(VideoPlayer).evaluate().length}',
      );
      debugPrint(
        '  tab bars                  ${find.byType(ConTabBar).evaluate().length}',
      );
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('Review puts the first reel inside the fold budget', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);

      expect(_rows, findsWidgets, reason: 'the queue rendered');
      final double first = tester.getTopLeft(_rows.first).dy;
      // Spec 3.1 puts row one at 178. The acceptance threshold is 300.
      expect(first, lessThanOrEqualTo(300));
      expect(first, greaterThan(100));

      // Spec 3.5: the row is 128 tall, or 150 when the title wraps to two
      // lines or a failure cause is present.
      final Size row = tester.getSize(_rows.first);
      expect(row.height, inInclusiveRange(128, 150));
      expect(row.width, 390);
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('five non-content controls sit above the first reel', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      final double first = tester.getTopLeft(_rows.first).dy;
      final int above = _buttonsAbove(tester, first);
      // Spec 0: five controls above the first reel, against 32 today.
      expect(above, lessThanOrEqualTo(6));
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('a 162 reel catalog builds a windowed list, not 162 rows', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      final int built = _rows.evaluate().length;
      expect(built, greaterThan(0));
      // Acceptance 7: 24 or fewer rows in the tree with 162 assets.
      expect(built, lessThanOrEqualTo(24));
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('Needs-you Review reaches the last @zionboggan card', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      final Finder finalZionRow = find.byKey(
        const ValueKey<String>('reel-row-reel160'),
      );
      await tester.scrollUntilVisible(
        finalZionRow,
        240,
        maxScrolls: 120,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(finalZionRow, findsOneWidget);

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      final double finalRowOffset = scrollable.position.pixels;
      scrollable.position.jumpTo(0);
      await tester.pump();
      scrollable.position.jumpTo(finalRowOffset);
      await tester.pump();
      expect(finalZionRow, findsOneWidget);
      expect(
        find.ancestor(
          of: finalZionRow,
          matching: find.byWidgetPredicate(
            (Widget widget) => widget is Opacity && widget.opacity < 1,
          ),
        ),
        findsNothing,
        reason: 'later virtualized Review rows must render when reached',
      );
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('no video player exists while the list is displayed', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      // Acceptance 6: exactly one video in the product, and it lives in the
      // Reel view.
      expect(find.byType(VideoPlayer), findsNothing);
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('the shell carries no deleted marketing copy', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      for (final String gone in <String>[
        'Your next great reel starts here.',
        "What's coming up.",
        'Shape the cut. Find the sound.',
        'See how your reels connect.',
        'Your connected accounts.',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // The readout strip is the freshness stamp and the counts, not a title.
      expect(find.byType(Caps), findsWidgets);
    }, createHttpClient: (SecurityContext? c) => _Client());
  });

  testWidgets('the tab bar carries the six Claude handoff destinations', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await _boot(tester);
      expect(find.byType(ConTabBar), findsOneWidget);
      for (final String label in <String>[
        'REVIEW',
        'SCHEDULE',
        'STUDIO',
        'RESULTS',
        'ACCOUNTS',
        'TEAM',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.bySemanticsLabel('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Automations'), findsOneWidget);
      expect(find.text('Accounts'), findsOneWidget);
      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
      expect(find.text('PUBLISHING'), findsWidgets);
    }, createHttpClient: (SecurityContext? c) => _Client());
  });
}
