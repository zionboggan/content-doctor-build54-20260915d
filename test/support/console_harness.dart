// A fake gateway and a boot helper, shared by the behaviour tests.
//
// Everything here is synthetic. No provider route, credential or network
// resource is reachable from a test that uses it: every HttpClient call is
// answered from the maps below, and the app's wall clock is pinned so a
// rendered screen is byte-stable rather than stable-until-tomorrow.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart' show tutorialSeenKey;
import 'package:iris/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 1x1 PNG, so a poster request resolves the way it does on the device.
final Uint8List kPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
  'IQAAAABJRU5ErkJggg==',
);

/// A fixed instant every fixture derives its dates from.
final DateTime kPinnedNow = DateTime.utc(2026, 9, 15, 21, 0);

List<Map<String, dynamic>> reviewCatalog({int count = 162}) =>
    List<Map<String, dynamic>>.generate(
      count,
      (int i) => <String, dynamic>{
        'id': 'reel$i',
        'sha256': 'sha$i',
        'account': i.isEven ? '@zionboggan' : '@barcrawling',
        'title': 'Yacht sequence v$i',
        'caption': 'A caption for reel $i',
        'status': 'ready_for_review',
        'duration_seconds': 23,
        'created_at': kPinnedNow
            .subtract(Duration(hours: 3 + (i % 3) * 24))
            .toIso8601String(),
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

/// One request the app made, recorded so a test can assert on intent rather
/// than on a snackbar.
class GatewayCall {
  GatewayCall(this.method, this.path, this.body);
  final String method;
  final String path;
  final String body;
  @override
  String toString() => '$method $path $body';
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.method, this.gateway);
  @override
  final Uri uri;
  @override
  final String method;
  final FakeGateway gateway;
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
    gateway.calls.add(GatewayCall(method, path, utf8.decode(_body)));
    if (path.endsWith('.poster')) return _Response(kPng, 200);
    for (final MapEntry<String, int> entry in gateway.failures.entries) {
      if (path.startsWith(entry.key)) {
        return _Response(
          utf8.encode('{"detail":"synthetic ${entry.value}"}'),
          entry.value,
        );
      }
    }
    final Object Function()? override = gateway.routes[path];
    if (override != null) {
      return _Response(utf8.encode(jsonEncode(override())), 200);
    }
    final Object body = switch (path) {
      '/trial-auth' => <String, dynamic>{
        'authenticated': true,
        'role': 'owner',
      },
      '/reels/catalog' => gateway.catalog,
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

class FakeGateway implements HttpClient {
  FakeGateway({
    List<Map<String, dynamic>>? catalog,
    Map<String, Object Function()>? routes,
    Map<String, int>? failures,
  }) : catalog = catalog ?? reviewCatalog(),
       routes = routes ?? <String, Object Function()>{},
       failures = failures ?? <String, int>{};

  List<Map<String, dynamic>> catalog;

  /// Exact-path overrides, evaluated per request so a route can answer
  /// differently after a write.
  final Map<String, Object Function()> routes;

  /// Path prefix to HTTP status. Anything matching answers with that status.
  final Map<String, int> failures;

  /// Every request the app issued, in order.
  final List<GatewayCall> calls = <GatewayCall>[];

  List<GatewayCall> callsTo(String path) =>
      calls.where((GatewayCall c) => c.path == path).toList();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(url, 'GET', this);
  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _Request(url, 'POST', this);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(url, method, this);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> loadAppFonts() async {
  for (final MapEntry<String, String> entry in <String, String>{
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'JetBrains Mono': 'assets/fonts/JetBrainsMono-Variable.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'packages/cupertino_icons/CupertinoIcons':
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
}

/// A device viewport the suite boots the shell into.
///
/// `logical` is in points, the way iOS reports it; the harness multiplies by
/// the device pixel ratio itself. `top`/`bottom` are the safe-area insets in
/// points — an iPhone 12-class notch is 47/34, every modern iPad is 24/20
/// (status bar and home indicator) in both orientations.
class DeviceView {
  const DeviceView(this.name, this.logical, {this.top = 24, this.bottom = 20});

  final String name;
  final Size logical;
  final double top;
  final double bottom;

  /// The workspace height the shell has to spend: the screen minus the safe
  /// area it honours at the top. The tab bar eats into this from the bottom.
  double get usableHeight => logical.height - top;

  @override
  String toString() =>
      '$name ${logical.width.toInt()}x${logical.height.toInt()}';
}

/// iPhone 12/13/14-class portrait, the size every pre-existing test and both
/// shipped goldens were captured at.
const DeviceView kPhone = DeviceView(
  'iPhone',
  Size(390, 844),
  top: 47,
  bottom: 34,
);

/// The iPad sizes Zion actually has, in both orientations, plus the narrow
/// pane Split View can hand the app while it is still "on an iPad".
const DeviceView kIpadMini = DeviceView('iPad mini portrait', Size(744, 1133));
const DeviceView kIpadMiniLandscape = DeviceView(
  'iPad mini landscape',
  Size(1133, 744),
);
const DeviceView kIpad11 = DeviceView('iPad Pro 11 portrait', Size(834, 1194));
const DeviceView kIpad11Landscape = DeviceView(
  'iPad Pro 11 landscape',
  Size(1194, 834),
);
const DeviceView kIpad129 = DeviceView(
  'iPad Pro 12.9 portrait',
  Size(1024, 1366),
);
const DeviceView kIpad129Landscape = DeviceView(
  'iPad Pro 12.9 landscape',
  Size(1366, 1024),
);

/// Split View's narrow pane. iPadOS hands a docked app a compact width even
/// though the device is an iPad, so anything that assumed "iPad means wide"
/// breaks here and nowhere else.
const DeviceView kSplitNarrow = DeviceView(
  'iPad Split View narrow',
  Size(375, 1133),
);

/// The one-third pane on a 12.9", the widest "compact" case.
const DeviceView kSplitWide = DeviceView(
  'iPad Split View one-third',
  Size(420, 1366),
);

const List<DeviceView> kIpadViewports = <DeviceView>[
  kIpadMini,
  kIpadMiniLandscape,
  kIpad11,
  kIpad11Landscape,
  kIpad129,
  kIpad129Landscape,
  kSplitNarrow,
  kSplitWide,
];

/// Boots the real shell at 390x844 DPR 2 with an iPhone safe area, or at
/// whatever [view] is handed instead.
/// Boot state for first-run onboarding. The shell shows the tour on the first
/// successful catalog load of a device that has never seen it, so a boot has
/// to say which device it is. The default is a returning operator — that is
/// what every behaviour and layout test here means by "the app" — and
/// [firstLaunch] gives the onboarding tests a genuinely fresh install.
Future<void> bootConsole(
  WidgetTester tester, {
  double textScale = 1,
  Key? frameKey,
  bool settle = true,
  DeviceView view = kPhone,
  bool firstLaunch = false,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = view.logical * tester.view.devicePixelRatio;
  tester.view.padding = FakeViewPadding(
    top: view.top * tester.view.devicePixelRatio,
    bottom: view.bottom * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.reset);
  // Set unconditionally. `addTearDown` runs at the end of the test, not
  // between boots, so a test that booted at 1.5 and then booted again at 1.0
  // was silently still at 1.5 for the second measurement.
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  trialNow = () => kPinnedNow;
  addTearDown(() => trialNow = DateTime.now);
  // Watch coverage is a process-global store.
  resetWatchCoverage();
  addTearDown(resetWatchCoverage);

  SharedPreferences.setMockInitialValues(<String, Object>{
    if (!firstLaunch) tutorialSeenKey: true,
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('trial_reels/credentials'),
        (MethodCall call) async => call.method == 'read' ? 'test-token' : null,
      );
  // AppLinks (OAuth deep links): mock native iOS/Android channels for Linux
  // widget tests. getInitialLink -> null; event stream never emits.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.app_links/messages'),
        (MethodCall call) async => null,
      );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.app_links/events'),
        (MethodCall call) async => null,
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('trial_reels/credentials'),
          null,
        ),
  );

  await tester.pumpWidget(
    frameKey == null
        ? const TrialReelsApp()
        : RepaintBoundary(key: frameKey, child: const TrialReelsApp()),
  );
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  if (settle) {
    // Posters decode off the test's synchronous clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
  }
}

/// Every built reel row, keyed `reel-row-<id>`.
Finder get reelRows => find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('reel-row-'),
);

Finder reelRow(String id) => find.byKey(ValueKey<String>('reel-row-$id'));

/// The workspace the shell hands the active tab body.
Rect workspaceRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey<String>('workspace')));

/// The scroll position of the scrollable inside the active tab body.
ScrollPosition tabScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('workspace')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Closes the top route the way the operator's back gesture would.
Future<void> popRoute(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Every reel row currently mounted, by key, including rows belonging to a
/// dormant tab. Used to tell "the same elements came back" from "the page was
/// rebuilt and happens to show the same reels".
Set<String> mountedRowKeys() => reelRows
    .evaluate()
    .map((Element e) => (e.widget.key! as ValueKey<String>).value)
    .toSet();
