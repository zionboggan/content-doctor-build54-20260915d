import 'package:flutter_test/flutter_test.dart';
import 'package:iris/trial_credentials.dart';

void main() {
  // Posters and video are built synchronously, so the header lookup must never
  // throw out of build(). A locked session and a non-secure origin both have to
  // come back as "no credential", not as an exception.
  test(
    'mediaHeaders is empty and does not throw when no credential is cached',
    () {
      expect(
        TrialCredentials.cached('https://gateway.example.invalid:8445'),
        isNull,
      );
      expect(
        TrialCredentials.mediaHeaders('https://gateway.example.invalid:8445'),
        isEmpty,
      );
    },
  );

  test('mediaHeaders swallows the non-HTTPS origin rejection', () {
    // read()/attach() deliberately throw for a plain-HTTP origin. The media
    // accessor must degrade to "locked" instead, or every tile crashes.
    expect(TrialCredentials.cached('http://192.0.2.15:8105'), isNull);
    expect(TrialCredentials.mediaHeaders('http://192.0.2.15:8105'), isEmpty);
    expect(TrialCredentials.mediaHeaders('not a url'), isEmpty);
    expect(TrialCredentials.mediaHeaders('http://[malformed'), isEmpty);
  });
}
