import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:iris/main.dart';

// Keep the production HTTPS origin check while routing this test transport to
// its isolated loopback receiver. This adapter is never shipped in the app.
class _LoopbackClient extends Fake implements HttpClient {
  _LoopbackClient(this.client, this.port);
  final HttpClient client;
  final int port;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => client.postUrl(
    Uri(scheme: 'http', host: '127.0.0.1', port: port, path: url.path),
  );
  @override
  Future<HttpClientRequest> getUrl(Uri url) => client.getUrl(
    Uri(scheme: 'http', host: '127.0.0.1', port: port, path: url.path),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('trial_reels/credentials'),
        (MethodCall call) async => 'transport-test-key',
      );
  test(
    'revision transport preserves emoji and smart quotes as UTF-8 JSON',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      const String note = 'I’m just the tech guy 💻 · bigger captions';
      final Future<Map<String, dynamic>> received = server.first.then((
        request,
      ) async {
        expect(request.headers.contentType?.mimeType, 'application/json');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer transport-test-key',
        );
        final Map<String, dynamic> payload =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"intake_verified":true}');
        await request.response.close();
        return payload;
      });
      final dynamic result = await TrialApi(
        'https://transport.example',
        client: _LoopbackClient(client, server.port),
      ).postJson('/trial-message', <String, dynamic>{'text': note});
      expect(result['intake_verified'], isTrue);
      expect((await received)['text'], note);
    },
  );

  test(
    'a confirmed no-content mutation does not become a JSON failure',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      final Future<void> responseHandled = server.first.then((
        HttpRequest request,
      ) async {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });

      final dynamic result = await TrialApi(
        'https://transport.example',
        client: _LoopbackClient(client, server.port),
      ).postJson('/reels/rate', <String, dynamic>{'rating': 5});
      await responseHandled;
      expect(result, isEmpty);
    },
  );

  // A read that answers nothing is a successful read of nothing.
  // snapshotFromCatalog Future.waits four getJson calls, so one 204 from
  // /reels/controls, /reels/schedules, /reels/oauth/status or
  // /reels/revision-status used to throw FormatException out of the whole
  // snapshot and banner an otherwise healthy load as failed. postJson always
  // guarded the empty body; getJson called jsonDecode('').
  test('a 204 read is an empty map, not malformed JSON', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final HttpClient client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    unawaited(
      server.first.then((HttpRequest request) async {
        request.response.statusCode = 204;
        await request.response.close();
      }),
    );
    final dynamic result = await TrialApi(
      'https://transport.example',
      client: _LoopbackClient(client, server.port),
    ).getJson('/reels/controls');
    expect(result, isEmpty);
  });

  // getJson threw before reading the body, so the gateway's own explanation
  // was discarded on every failed read and replaced with a status code.
  test(
    'a failed read surfaces the gateway detail, not a status code',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      unawaited(
        server.first.then((HttpRequest request) async {
          request.response.statusCode = 403;
          request.response.write(
            jsonEncode(<String, String>{'detail': 'Scope is collect-only'}),
          );
          await request.response.close();
        }),
      );
      await expectLater(
        TrialApi(
          'https://transport.example',
          client: _LoopbackClient(client, server.port),
        ).getJson('/reels/library'),
        throwsA(
          isA<HttpException>().having(
            (HttpException e) => e.message,
            'message',
            'Scope is collect-only',
          ),
        ),
      );
    },
  );

  // 23 call sites construct TrialApi, several of them inside closures handed
  // to polling panels, and the class has no close(). Every tick used to leak a
  // client and its connection pool.
  test('every TrialApi shares one HttpClient', () {
    expect(
      identical(
        TrialApi('https://a.example').debugClient,
        TrialApi('https://b.example').debugClient,
      ),
      isTrue,
    );
  });

  test('only an unchanged pending export can expose Move time', () {
    final Map<String, dynamic> reel = <String, dynamic>{
      'id': 'one',
      'sha256': 'abc',
      'caption': '',
      'account': '@zionboggan',
      'status': 'ready_for_review',
    };
    final Map<String, dynamic> pending = <String, dynamic>{
      ...reel,
      'state': 'scheduled',
    };
    expect(exactScheduleMatches(pending, reel), isTrue);
    expect(
      exactScheduleMatches({...pending, 'caption': 'changed'}, reel),
      isFalse,
    );
    expect(
      exactScheduleMatches({...pending, 'sha256': 'other'}, reel),
      isFalse,
    );
    expect(
      exactScheduleMatches({...pending, 'state': 'published'}, reel),
      isFalse,
    );
    expect(
      exactScheduleMatches(pending, {...reel, 'status': 'changes_requested'}),
      isFalse,
    );
  });
}
