import 'package:flutter_test/flutter_test.dart';
import 'package:iris/instagram_connection.dart';

Uri _oauthUri({String host = 'www.instagram.com'}) =>
    Uri.https(host, '/oauth/authorize', <String, String>{
      'client_id': 'app-id',
      'redirect_uri':
          'https://stepping.zionboggan.com/trial-reels/oauth/callback',
      'response_type': 'code',
      'scope': 'instagram_business_basic',
      'state': 'one-time-state',
    });

void main() {
  test('accepts the configured Instagram OAuth endpoint', () {
    expect(isInstagramOAuthUri(_oauthUri()), isTrue);
  });

  test('does not hand a signed-in phone to an untrusted URL', () async {
    bool opened = false;
    final InstagramConnectionLaunch result = await launchInstagramConnection(
      Uri.parse('https://example.test/oauth/authorize?response_type=code'),
      openExternal: (Uri _) async {
        opened = true;
        return true;
      },
    );
    expect(result.opened, isFalse);
    expect(result.message, 'Connection link was not valid. Try again.');
    expect(opened, isFalse);
  });

  test(
    'uses exactly one external handoff and gives a short return message',
    () async {
      Uri? opened;
      final InstagramConnectionLaunch result = await launchInstagramConnection(
        _oauthUri(),
        openExternal: (Uri uri) async {
          opened = uri;
          return true;
        },
      );
      expect(result.opened, isTrue);
      expect(opened, _oauthUri());
      expect(result.message, 'Continue with Instagram, then return here.');
    },
  );

  test(
    'turns an unavailable system handoff into a direct retry message',
    () async {
      final InstagramConnectionLaunch result = await launchInstagramConnection(
        _oauthUri(),
        openExternal: (Uri _) async => false,
      );
      expect(result.opened, isFalse);
      expect(result.message, 'Could not open Instagram. Try again.');
    },
  );
}
