import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a signed-out reviewer can select the public connection', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('trial_reels/credentials'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (_) async => null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    await tester.pumpWidget(const TrialReelsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App Review workspace'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(hostPrefKey),
      'https://content-doctor-review.zionboggan.com',
    );
    expect(find.text('Session locked'), findsOneWidget);
    await tester.tap(find.text('Unlock').last);
    await tester.pumpAndSettle();
    expect(find.text('App Review workspace'), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
