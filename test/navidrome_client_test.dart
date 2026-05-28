import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:aetherfin/core/subsonic/navidrome_client.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';

void main() {
  group('NavidromeClient', () {
    late NavidromeClient client;
    late List<Map<String, dynamic>> subsonicRequests;
    late List<Map<String, dynamic>> navidromeRequests;

    setUp(() {
      subsonicRequests = [];
      navidromeRequests = [];

      // ignore: prefer_const_constructors — Dio init prevents const
      client = NavidromeClient(
        server: JellyfinServer(baseUrl: 'http://localhost:4533', name: 'Navidrome'),
        username: 'testuser',
        password: 'testpassword',
        clientVersion: '1.0.0-test',
      );

      // Intercept subsonic requests
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            subsonicRequests.add({
              'path': options.path,
              'method': options.method,
              'queryParameters': options.queryParameters,
            });

            if (options.path.contains('ping')) {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'subsonic-response': {
                    'status': 'ok',
                    'version': '1.16.1',
                    'type': 'navidrome',
                    'serverVersion': '0.51.0',
                  }
                },
              ));
              return;
            }
            
            if (options.path.contains('getOpenSubsonicExtensions')) {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'subsonic-response': {
                    'status': 'ok',
                    'openSubsonicExtensions': [
                      {'name': 'formPost'}
                    ]
                  }
                },
              ));
              return;
            }

            handler.next(options);
          },
        ),
      );

      // Intercept Navidrome native API requests
      client.ndDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            navidromeRequests.add({
              'path': options.path,
              'method': options.method,
              'data': options.data,
              'headers': Map<String, dynamic>.from(options.headers),
            });

            if (options.path == 'auth/login') {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {'token': 'test-jwt-token'},
              ));
              return;
            }

            if (options.path == 'queue') {
              if (options.method == 'POST') {
                handler.resolve(Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {},
                ));
              } else if (options.method == 'GET') {
                handler.resolve(Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'current': 1,
                      'position': 5000,
                      'items': [
                        {
                          'id': 'song-1',
                          'title': 'Song One',
                          'artist': 'Artist One',
                          'album': 'Album One',
                          'albumId': 'album-1',
                          'duration': 180,
                          'trackNumber': 2,
                          'suffix': 'mp3',
                          'bitRate': 320,
                          'sampleRate': 44100,
                          'starred': true,
                          'createdAt': '2026-05-28T05:00:00Z',
                        }
                      ]
                    }
                  },
                ));
              }
              return;
            }

            handler.next(options);
          },
        ),
      );
    });

    test('authenticates on ping and passes x-nd-authorization header', () async {
      await client.ping();

      // Check subsonic ping request
      expect(subsonicRequests.any((r) => (r['path'] as String).contains('ping')), isTrue);

      // Check Navidrome REST login request
      final loginReq = navidromeRequests.firstWhere((r) => r['path'] == 'auth/login');
      expect(loginReq['method'], 'POST');
      expect(loginReq['data']['username'], 'testuser');
      expect(loginReq['data']['password'], 'testpassword');

      // Subsequent queue calls should carry Bearer token
      await client.savePlayQueue(['song-1']);
      final queueReq = navidromeRequests.firstWhere((r) => r['path'] == 'queue' && r['method'] == 'POST');
      expect(queueReq['headers']['x-nd-authorization'], 'Bearer test-jwt-token');
    });

    test('savePlayQueue formats payload correctly', () async {
      await client.savePlayQueue(['song-1', 'song-2'], currentIndex: 1, position: const Duration(seconds: 5));

      final req = navidromeRequests.firstWhere((r) => r['path'] == 'queue' && r['method'] == 'POST');
      expect(req['data']['current'], 1);
      expect(req['data']['ids'], ['song-1', 'song-2']);
      expect(req['data']['position'], 5000);
    });

    test('getPlayQueue parses native response into AfTrack list', () async {
      final res = await client.getPlayQueue();

      expect(res, isNotNull);
      expect(res!.currentIndex, 1);
      expect(res.position, const Duration(seconds: 5));
      expect(res.tracks, hasLength(1));

      final track = res.tracks.first;
      expect(track.id, 'song-1');
      expect(track.title, 'Song One');
      expect(track.artistName, 'Artist One');
      expect(track.albumName, 'Album One');
      expect(track.albumId, 'album-1');
      expect(track.duration, const Duration(seconds: 180));
      expect(track.trackNumber, 2);
      expect(track.quality?.sourceCodec, 'mp3');
      expect(track.quality?.bitrateKbps, 320);
      expect(track.isFavorite, isTrue);
      expect(track.dateAdded, DateTime.parse('2026-05-28T05:00:00Z'));
    });
  });
}
