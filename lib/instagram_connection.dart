import 'package:url_launcher/url_launcher.dart';

/// The OAuth service returns a provider-owned HTTPS page.  Keep the handoff
/// outside the app so Instagram can use its existing signed-in session and
/// return through the registered server callback.
typedef InstagramUrlOpener = Future<bool> Function(Uri uri);

class InstagramConnectionLaunch {
  const InstagramConnectionLaunch._(this.opened, this.message);

  final bool opened;
  final String message;

  static const InstagramConnectionLaunch openedInInstagram =
      InstagramConnectionLaunch._(
        true,
        'Continue with Instagram, then return here.',
      );
  static const InstagramConnectionLaunch invalidLink =
      InstagramConnectionLaunch._(
        false,
        'Connection link was not valid. Try again.',
      );
  static const InstagramConnectionLaunch couldNotOpen =
      InstagramConnectionLaunch._(
        false,
        'Could not open Instagram. Try again.',
      );
}

/// Only hand off the exact Instagram OAuth endpoint this app is configured to
/// use.  This prevents a bad gateway response from sending a signed-in phone to
/// an arbitrary browser destination.
bool isInstagramOAuthUri(Uri uri) {
  return uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'instagram.com' || uri.host == 'www.instagram.com') &&
      uri.path == '/oauth/authorize' &&
      uri.queryParameters['response_type'] == 'code' &&
      (uri.queryParameters['client_id'] ?? '').isNotEmpty &&
      (uri.queryParameters['redirect_uri'] ?? '').isNotEmpty &&
      (uri.queryParameters['state'] ?? '').isNotEmpty;
}

Future<bool> _openInSystemBrowser(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Starts one native handoff. iOS/Android decide whether an installed
/// Instagram app or the user's default browser owns the provider URL; either
/// preserves the provider's real sign-in and registered callback.
Future<InstagramConnectionLaunch> launchInstagramConnection(
  Uri uri, {
  InstagramUrlOpener? openExternal,
}) async {
  if (!isInstagramOAuthUri(uri)) {
    return InstagramConnectionLaunch.invalidLink;
  }
  try {
    final bool opened = await (openExternal ?? _openInSystemBrowser)(uri);
    return opened
        ? InstagramConnectionLaunch.openedInInstagram
        : InstagramConnectionLaunch.couldNotOpen;
  } on Object {
    return InstagramConnectionLaunch.couldNotOpen;
  }
}
