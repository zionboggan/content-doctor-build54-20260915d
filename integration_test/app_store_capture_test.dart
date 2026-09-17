import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iris/main.dart' as app;
import 'package:iris/console_shell.dart';
import 'package:iris/trial_credentials.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Capture the running app against the restricted review workspace', (
    WidgetTester tester,
  ) async {
    const String gateway = String.fromEnvironment('REVIEW_GATEWAY');
    const String username = String.fromEnvironment('REVIEW_USERNAME');
    const String password = String.fromEnvironment('REVIEW_PASSWORD');
    if (gateway.isEmpty || username.isEmpty || password.isEmpty) {
      throw StateError('Private review configuration is missing');
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(app.hostPrefKey, gateway);
    await TrialCredentials.login(gateway, username, password);
    app.main();
    // Let real network requests finish; never replace them with fixture data.
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (find.byType(ConTabBar).evaluate().isNotEmpty &&
          find
              .textContaining(RegExp('arizona', caseSensitive: false))
              .evaluate()
              .isNotEmpty) {
        break;
      }
    }
    expect(find.byType(ConTabBar), findsOneWidget);
    expect(
      tester.widget<ConTabBar>(find.byType(ConTabBar)).inert,
      isFalse,
      reason: 'Screenshots require a signed-in workspace',
    );
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('01-review');
    // Tap only navigation. Never approve, publish, schedule or send in capture.
    final ConTabBar tabs = tester.widget<ConTabBar>(find.byType(ConTabBar));
    final int schedule = tabs.labels.indexWhere(
      (String value) => value.toLowerCase() == 'schedule',
    );
    if (schedule < 0) throw StateError('Schedule navigation is unavailable');
    tabs.onChanged(schedule);
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('02-schedule');
    final int studio = tabs.labels.indexWhere(
      (String value) => value.toLowerCase() == 'studio',
    );
    if (studio < 0) throw StateError('Studio navigation is unavailable');
    tabs.onChanged(studio);
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('03-studio');
  });
}
