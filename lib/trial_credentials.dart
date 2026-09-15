import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Device Keychain credentials are scoped to one HTTPS gateway origin.
class TrialCredentials {
  static const MethodChannel _channel = MethodChannel(
    'trial_reels/credentials',
  );
  static final Map<String, String> _session = <String, String>{};

  static String _origin(String base) {
    final Uri uri = Uri.parse(base);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const HttpException(
        'Use the secure Tailnet HTTPS connection to unlock editing.',
      );
    }
    return uri.origin;
  }

  static Future<String?> read(String base) async {
    final String origin = _origin(base);
    if (_session.containsKey(origin)) return _session[origin];
    try {
      final String? token = await _channel.invokeMethod<String>('read', {
        'origin': origin,
      });
      if (token != null && token.isNotEmpty) _session[origin] = token;
      return token;
    } on MissingPluginException {
      return null;
    }
  }

  /// Synchronous read of the already-warmed session credential.
  ///
  /// `build()` cannot await, but `Image.network` and `VideoPlayerController`
  /// need their headers at construction time. The session map is populated by
  /// `read()` during boot (`_readSessionRole`), which is awaited before any
  /// catalog, tile or player is built, so by the time a media widget exists
  /// the credential is already here. Returns null rather than throwing when
  /// the origin is not the secure gateway.
  static String? cached(String base) {
    try {
      return _session[_origin(base)];
    } on HttpException {
      return null;
    } on FormatException {
      // A malformed base must degrade to "locked", never crash a build().
      return null;
    }
  }

  /// Headers for media loaded by URL rather than through the API client.
  ///
  /// Empty when locked, so the widget still builds and its error state - not a
  /// crash - reports the missing credential.
  static Map<String, String> mediaHeaders(String base) {
    final String? token = cached(base);
    if (token == null || token.isEmpty) return const <String, String>{};
    return <String, String>{HttpHeaders.authorizationHeader: 'Bearer $token'};
  }

  static Future<void> attach(HttpClientRequest request, String base) async {
    final String? token = await read(base);
    if (token == null || token.isEmpty) {
      throw const HttpException(
        'Tap the lock button to unlock Content Doctor before making changes.',
      );
    }
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }

  /// Scope read responses to the signed-in role when a credential exists.
  static Future<void> attachIfAvailable(
    HttpClientRequest request,
    String base,
  ) async {
    try {
      final String? token = await read(base);
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
    } on HttpException {
      // Diagnostics can still use a read-only LAN endpoint. Credentials and
      // every mutating request remain HTTPS-only.
    }
  }

  static Future<void> validateAndSave(String base, String value) async {
    final String origin = _origin(base);
    final String token = value.trim();
    if (token.isEmpty || token.contains('\n') || token.contains('\r')) {
      throw const FormatException('Enter a valid access key.');
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('$base/trial-auth'),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final String body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          (jsonDecode(body) as Map)['authenticated'] != true) {
        throw const HttpException('The access key was not accepted.');
      }
      // Save only after verification; Keychain failure must not report success.
      await _channel.invokeMethod<void>('write', {
        'origin': origin,
        'token': token,
      });
      _session[origin] = token;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> login(
    String base,
    String username,
    String password,
  ) async {
    _origin(base);
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('$base/trial-login'));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'username': username.trim(), 'password': password}),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(body) as Map;
      if (response.statusCode != 200 ||
          data['authenticated'] != true ||
          data['token'] is! String) {
        throw const HttpException('Username or password was not accepted.');
      }
      await validateAndSave(base, data['token'] as String);
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> clear(String base) async {
    final String origin = _origin(base);
    await _channel.invokeMethod<void>('delete', {'origin': origin});
    _session.remove(origin);
  }
}
