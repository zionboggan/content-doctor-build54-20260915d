import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_experience.dart';
import 'package:iris/native_editor.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlatform extends VideoPlayerPlatform {
  final List<String?> sources = <String?>[];
  final Map<int, Duration> positions = <int, Duration>{};
  final Set<int> playing = <int>{};
  @override
  Future<void> init() async {}
  @override
  Future<int> create(DataSource source) async {
    sources.add(source.uri);
    return sources.length;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream<VideoEvent>.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 30),
      size: const Size(1080, 1920),
    ),
  );
  @override
  Widget buildView(int playerId) => const SizedBox.expand();
  @override
  Future<void> dispose(int playerId) async {
    playing.remove(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {
    playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    playing.remove(playerId);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
}

void main() {
  testWidgets(
    'caption changes reuse video; song cue changes reuse both players',
    (WidgetTester tester) async {
      final VideoPlayerPlatform previous = VideoPlayerPlatform.instance;
      final FakeVideoPlatform platform = FakeVideoPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previous);

      Widget preview({
        String caption = 'First hook',
        String? song,
        double cue = 0,
      }) => MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: SourcePreview(
            key: const ValueKey<String>('same-source'),
            base: 'https://example.test',
            item: const <String, dynamic>{'id': 'clip', 'library': true},
            caption: caption,
            style: 'center_white',
            captionColor: '#FFFFFF',
            captionX: 50,
            captionY: 50,
            musicAssetId: song,
            musicCueSeconds: cue,
            trimInSeconds: 2,
            trimOutSeconds: 12,
          ),
        ),
      );

      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(platform.sources, hasLength(1));
      // The editor scrubs the original, not the 8s preview proxy — see
      // native_editor.dart's SourcePreview.initState for why.
      expect(platform.sources.single, endsWith('/reels/library/clip/original'));
      expect(platform.positions[1], const Duration(seconds: 2));

      await tester.pumpWidget(preview(caption: 'A better hook'));
      await tester.pumpAndSettle();
      expect(platform.sources, hasLength(1));
      expect(find.text('A better hook'), findsOneWidget);

      await tester.pumpWidget(preview(song: 'approved-song'));
      await tester.pumpAndSettle();
      expect(platform.sources, hasLength(2));

      await tester.pumpWidget(preview(song: 'approved-song', cue: 8));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(platform.sources, hasLength(2));
      // Song cue is relative to the trimmed output, not the source timeline.
      expect(platform.positions[2], const Duration(seconds: 8));

      await tester.tap(find.byTooltip('Play preview'));
      await tester.pump();
      expect(platform.playing, <int>{1, 2});
      await tester.tap(find.byTooltip('Pause preview'));
      await tester.pump();
      expect(platform.playing, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
