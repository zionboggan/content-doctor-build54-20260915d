import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/trial_credentials.dart';

class _Headers extends Fake implements HttpHeaders {
  final Map<String, Object> values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }
}

class _Request extends Fake implements HttpClientRequest {
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('trial_reels/credentials');
  test(
    'Keychain credential is host scoped and write redirects are disabled',
    () async {
      final List<String> origins = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            origins.add((call.arguments as Map)['origin'] as String);
            return origins.last == 'https://allowed.example'
                ? 'test-only-key'
                : null;
          });
      final _Request request = _Request();
      await TrialCredentials.attach(request, 'https://allowed.example');
      expect(
        request.headers.values[HttpHeaders.authorizationHeader],
        'Bearer test-only-key',
      );
      expect(request.followRedirects, isFalse);
      await expectLater(
        TrialCredentials.attach(_Request(), 'https://other.example'),
        throwsA(isA<HttpException>()),
      );
      expect(origins, ['https://allowed.example', 'https://other.example']);
    },
  );
  test(
    'plaintext and credential-bearing origins are rejected before loading secrets',
    () async {
      for (final String url in [
        'http://allowed.example',
        'https://user:pass@allowed.example',
      ]) {
        await expectLater(
          TrialCredentials.attach(_Request(), url),
          throwsA(isA<HttpException>()),
        );
      }
    },
  );
}
