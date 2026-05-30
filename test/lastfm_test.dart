import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aetherfin/core/audio/lastfm_playback_reporter.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lastfm/lastfm_client.dart';

class MockPlayerService extends Mock implements AfPlayerService {}

class MockLastFmClient extends Mock implements LastFmClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockPlayerService player;
  late MockLastFmClient client;
  late StreamController<AfTrack?> trackController;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    player = MockPlayerService();
    client = MockLastFmClient();
    trackController = StreamController<AfTrack?>.broadcast();

    // Default player mocks
    when(
      () => player.currentTrackStream,
    ).thenAnswer((_) => trackController.stream);
    when(() => player.listenedDuration).thenReturn(Duration.zero);

    // Default client mocks for nowPlaying and scrobble
    when(
      () => client.updateNowPlaying(
        artist: any(named: 'artist'),
        track: any(named: 'track'),
        album: any(named: 'album'),
        duration: any(named: 'duration'),
      ),
    ).thenAnswer((_) => Future.value());

    when(
      () => client.scrobble(
        artist: any(named: 'artist'),
        track: any(named: 'track'),
        timestamp: any(named: 'timestamp'),
        album: any(named: 'album'),
        duration: any(named: 'duration'),
      ),
    ).thenAnswer((_) => Future.value());
  });

  tearDown(() {
    trackController.close();
  });

  const trackA = AfTrack(
    id: '1',
    title: 'Track A',
    artistName: 'Artist A',
    albumName: 'Album A',
    duration: Duration(minutes: 3),
    imageUrl: null,
    isFavorite: false,
  );

  const trackB = AfTrack(
    id: '2',
    title: 'Track B',
    artistName: 'Artist B',
    albumName: 'Album B',
    duration: Duration(minutes: 4),
    imageUrl: null,
    isFavorite: false,
  );

  group('LastFmPlaybackReporter Now Playing', () {
    test('updates now playing on Last.fm when track starts', () async {
      // Initialize reporter
      final reporter = LastFmPlaybackReporter(player, () => client, () => true);

      // Start playing trackA
      trackController.add(trackA);
      await Future.delayed(Duration.zero);

      verify(
        () => client.updateNowPlaying(
          artist: 'Artist A',
          track: 'Track A',
          album: 'Album A',
          duration: const Duration(minutes: 3),
        ),
      ).called(1);

      await reporter.dispose();
    });

    test('does nothing when client is null', () async {
      final reporter = LastFmPlaybackReporter(player, () => null, () => true);

      trackController.add(trackA);
      await Future.delayed(Duration.zero);

      verifyNever(
        () => client.updateNowPlaying(
          artist: any(named: 'artist'),
          track: any(named: 'track'),
          album: any(named: 'album'),
          duration: any(named: 'duration'),
        ),
      );

      await reporter.dispose();
    });

    test('does nothing when scrobbling is disabled', () async {
      final reporter = LastFmPlaybackReporter(
        player,
        () => client,
        () => false,
      );

      trackController.add(trackA);
      await Future.delayed(Duration.zero);

      verifyNever(
        () => client.updateNowPlaying(
          artist: any(named: 'artist'),
          track: any(named: 'track'),
          album: any(named: 'album'),
          duration: any(named: 'duration'),
        ),
      );

      await reporter.dispose();
    });
  });

  group('LastFmPlaybackReporter Scrobbling Eligibility', () {
    test(
      'does not scrobble if listened duration is too short (< 50% & < 4 mins)',
      () async {
        final reporter = LastFmPlaybackReporter(
          player,
          () => client,
          () => true,
        );

        // Start Track A
        trackController.add(trackA);
        await Future.delayed(Duration.zero);

        // Listened for 30 seconds (duration is 3 mins, 50% is 90s)
        when(
          () => player.listenedDuration,
        ).thenReturn(const Duration(seconds: 30));

        // Switch to Track B (should trigger scrobble check)
        trackController.add(trackB);
        await Future.delayed(Duration.zero);

        verifyNever(
          () => client.scrobble(
            artist: any(named: 'artist'),
            track: any(named: 'track'),
            timestamp: any(named: 'timestamp'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          ),
        );

        await reporter.dispose();
      },
    );

    test(
      'scrobbles if listened duration meets 50% of track duration',
      () async {
        final reporter = LastFmPlaybackReporter(
          player,
          () => client,
          () => true,
        );

        trackController.add(trackA);
        await Future.delayed(Duration.zero);

        // Listened for 95 seconds (50% of 180s is 90s)
        when(
          () => player.listenedDuration,
        ).thenReturn(const Duration(seconds: 95));

        // Switch to Track B
        trackController.add(trackB);
        await Future.delayed(Duration.zero);

        verify(
          () => client.scrobble(
            artist: 'Artist A',
            track: 'Track A',
            timestamp: any(named: 'timestamp'),
            album: 'Album A',
            duration: const Duration(minutes: 3),
          ),
        ).called(1);

        await reporter.dispose();
      },
    );

    test(
      'scrobbles if listened duration is 4 minutes or more (even if < 50% for a long track)',
      () async {
        const longTrack = AfTrack(
          id: '3',
          title: 'Long Track',
          artistName: 'Artist C',
          albumName: 'Album C',
          duration: Duration(minutes: 10), // 50% is 5 mins
          imageUrl: null,
          isFavorite: false,
        );

        final reporter = LastFmPlaybackReporter(
          player,
          () => client,
          () => true,
        );

        trackController.add(longTrack);
        await Future.delayed(Duration.zero);

        // Listened for 4 minutes (240 seconds)
        when(
          () => player.listenedDuration,
        ).thenReturn(const Duration(minutes: 4));

        // Switch to Track B
        trackController.add(trackB);
        await Future.delayed(Duration.zero);

        verify(
          () => client.scrobble(
            artist: 'Artist C',
            track: 'Long Track',
            timestamp: any(named: 'timestamp'),
            album: 'Album C',
            duration: const Duration(minutes: 10),
          ),
        ).called(1);

        await reporter.dispose();
      },
    );

    test('does not scrobble short tracks (< 30s duration)', () async {
      const shortTrack = AfTrack(
        id: '4',
        title: 'Short Track',
        artistName: 'Artist D',
        albumName: 'Album D',
        duration: Duration(seconds: 20),
        imageUrl: null,
        isFavorite: false,
      );

      final reporter = LastFmPlaybackReporter(player, () => client, () => true);

      trackController.add(shortTrack);
      await Future.delayed(Duration.zero);

      // Listened for 15s (75% of duration, meets 50% threshold)
      when(
        () => player.listenedDuration,
      ).thenReturn(const Duration(seconds: 15));

      trackController.add(trackB);
      await Future.delayed(Duration.zero);

      verifyNever(
        () => client.scrobble(
          artist: any(named: 'artist'),
          track: any(named: 'track'),
          timestamp: any(named: 'timestamp'),
          album: any(named: 'album'),
          duration: any(named: 'duration'),
        ),
      );

      await reporter.dispose();
    });
  });

  group('LastFmClient Extended API Endpoints', () {
    late MockDio mockDio;
    late LastFmClient lastFmClient;

    setUp(() {
      mockDio = MockDio();
      lastFmClient = LastFmClient(
        apiKey: 'test_key',
        apiSecret: 'test_secret',
        sessionKey: 'test_session',
        dio: mockDio,
      );
    });

    test('love submits POST with signature', () async {
      when(
        () => mockDio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {},
        ),
      );

      await lastFmClient.love(artist: 'Artist A', track: 'Track A');

      verify(
        () => mockDio.post(
          '/',
          data: any(
            named: 'data',
            that: isA<Map<String, String>>()
                .having((m) => m['method'], 'method', 'track.love')
                .having((m) => m['artist'], 'artist', 'Artist A')
                .having((m) => m['track'], 'track', 'Track A')
                .having((m) => m['sk'], 'session key', 'test_session'),
          ),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('unlove submits POST with signature', () async {
      when(
        () => mockDio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {},
        ),
      );

      await lastFmClient.unlove(artist: 'Artist A', track: 'Track A');

      verify(
        () => mockDio.post(
          '/',
          data: any(
            named: 'data',
            that: isA<Map<String, String>>().having(
              (m) => m['method'],
              'method',
              'track.unlove',
            ),
          ),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('getLovedTracks queries user.getLovedTracks', () async {
      when(
        () =>
            mockDio.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {
            'lovedtracks': {
              'track': [
                {
                  'name': 'Track A',
                  'artist': {'name': 'Artist A'},
                },
              ],
            },
          },
        ),
      );

      final result = await lastFmClient.getLovedTracks(username: 'test_user');
      expect(result.length, 1);
      expect(result.first.title, 'Track A');
      expect(result.first.artist, 'Artist A');
    });

    test('getTopTracks queries user.getTopTracks', () async {
      when(
        () =>
            mockDio.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {
            'toptracks': {
              'track': [
                {
                  'name': 'Track A',
                  'artist': {'name': 'Artist A'},
                  'playcount': '10',
                },
              ],
            },
          },
        ),
      );

      final result = await lastFmClient.getTopTracks(username: 'test_user');
      expect(result.length, 1);
      expect(result.first.playCount, 10);
    });

    test('getArtistInfo queries artist.getInfo', () async {
      when(
        () =>
            mockDio.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {
            'artist': {
              'name': 'Artist A',
              'bio': {'content': 'Biography content'},
            },
          },
        ),
      );

      final result = await lastFmClient.getArtistInfo(artistName: 'Artist A');
      expect(result?['name'], 'Artist A');
      expect(result?['bio']?['content'], 'Biography content');
    });
  });
}
