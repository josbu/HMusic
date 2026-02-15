import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hmusic/data/services/playlist_import_service.dart';
import 'package:hmusic/presentation/providers/local_playlist_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubHttpAdapter implements HttpClientAdapter {
  _StubHttpAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (cancelFuture != null) {
      var cancelled = false;
      await Future.any<void>([
        cancelFuture.then((_) => cancelled = true),
        Future<void>.delayed(const Duration(milliseconds: 1)),
      ]);
      if (cancelled) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        );
      }
    }
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> data, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Dio _buildDio(
  ResponseBody Function(RequestOptions options) handler,
) {
  final dio = Dio();
  dio.httpClientAdapter = _StubHttpAdapter(handler);
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaylistImportService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('主接口失败时会走备用接口并成功导入', () async {
      int qqPrimarySummaryCalls = 0;
      int qqFallbackSummaryCalls = 0;
      int qqPrimaryDetailCalls = 0;
      int qqFallbackDetailCalls = 0;

      final dio = _buildDio((options) {
        final uri = options.uri.toString();
        if (uri.contains('c.y.qq.com') && uri.contains('onlysong=1')) {
          qqPrimarySummaryCalls++;
          return _jsonBody(<String, dynamic>{}, statusCode: 500);
        }
        if (uri.contains('i.y.qq.com') && uri.contains('onlysong=1')) {
          qqFallbackSummaryCalls++;
          return _jsonBody({
            'cdlist': [
              {'dissname': '测试歌单', 'songnum': 1},
            ],
          });
        }
        if (uri.contains('c.y.qq.com') && uri.contains('onlysong=0')) {
          qqPrimaryDetailCalls++;
          return _jsonBody(<String, dynamic>{}, statusCode: 500);
        }
        if (uri.contains('i.y.qq.com') && uri.contains('onlysong=0')) {
          qqFallbackDetailCalls++;
          return _jsonBody({
            'cdlist': [
              {
                'dissname': '测试歌单',
                'songlist': [
                  {
                    'songmid': 'song_mid_1',
                    'songname': '歌1',
                    'singer': [
                      {'name': '歌手1'},
                    ],
                  },
                ],
              },
            ],
          });
        }
        return _jsonBody(<String, dynamic>{}, statusCode: 404);
      });

      final container = ProviderContainer(
        overrides: [
          playlistImportDioProvider.overrideWith((ref) => dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(localPlaylistProvider.notifier).loadPlaylists();
      final service = container.read(playlistImportServiceProvider);

      final result = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/123456',
        modeScope: 'xiaomusic',
      );

      expect(result.success, isTrue);
      expect(result.importedCount, 1);
      final playlist = container.read(localPlaylistProvider).playlists.first;
      expect(playlist.sourceUrl, 'https://y.qq.com/n/ryqq/playlist/123456');
      expect(playlist.importedAt, isNotNull);
      expect(qqPrimarySummaryCalls, 1);
      expect(qqFallbackSummaryCalls, 1);
      expect(qqPrimaryDetailCalls, 1);
      expect(qqFallbackDetailCalls, 1);
    });

    test('404 返回会分类为 playlistNotFound', () async {
      final dio = _buildDio((options) {
        if (options.uri.host.contains('music.163.com')) {
          return _jsonBody(<String, dynamic>{}, statusCode: 404);
        }
        return _jsonBody(<String, dynamic>{}, statusCode: 404);
      });

      final container = ProviderContainer(
        overrides: [
          playlistImportDioProvider.overrideWith((ref) => dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(localPlaylistProvider.notifier).loadPlaylists();
      final service = container.read(playlistImportServiceProvider);

      final result = await service.importFromUrl(
        'https://music.163.com/#/playlist?id=987654',
        modeScope: 'xiaomusic',
      );

      expect(result.success, isFalse);
      expect(result.error, ImportError.playlistNotFound);
    });

    test('取消会分类为 cancelled', () async {
      final dio = _buildDio((options) {
        return _jsonBody(<String, dynamic>{}, statusCode: 500);
      });

      final container = ProviderContainer(
        overrides: [
          playlistImportDioProvider.overrideWith((ref) => dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(localPlaylistProvider.notifier).loadPlaylists();
      final service = container.read(playlistImportServiceProvider);

      final cancelToken = CancelToken()..cancel('user_cancelled');
      final result = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/123456',
        modeScope: 'xiaomusic',
        cancelToken: cancelToken,
      );

      expect(result.success, isFalse);
      expect(result.error, ImportError.cancelled);
    });

    test('500首前置确认拒绝时不会进入详情拉取', () async {
      int detailCalls = 0;
      final dio = _buildDio((options) {
        final uri = options.uri.toString();
        if (uri.contains('onlysong=1')) {
          return _jsonBody({
            'cdlist': [
              {'dissname': '大歌单', 'songnum': 800},
            ],
          });
        }
        if (uri.contains('onlysong=0')) {
          detailCalls++;
          return _jsonBody({
            'cdlist': [
              {'dissname': '大歌单', 'songlist': []},
            ],
          });
        }
        return _jsonBody(<String, dynamic>{}, statusCode: 404);
      });

      final container = ProviderContainer(
        overrides: [
          playlistImportDioProvider.overrideWith((ref) => dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(localPlaylistProvider.notifier).loadPlaylists();
      final service = container.read(playlistImportServiceProvider);

      final result = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/123456',
        modeScope: 'xiaomusic',
        onNeedLargePlaylistConfirm: (_) async => false,
      );

      expect(result.success, isFalse);
      expect(result.error, ImportError.cancelled);
      expect(detailCalls, 0);
    });

    test('已导入歌单选择增量更新时只新增新歌', () async {
      int summaryCalls = 0;
      int detailCalls = 0;

      final dio = _buildDio((options) {
        final uri = options.uri.toString();
        if (uri.contains('onlysong=1')) {
          summaryCalls++;
          return _jsonBody({
            'cdlist': [
              {'dissname': '我的歌单', 'songnum': summaryCalls == 1 ? 1 : 2},
            ],
          });
        }
        if (uri.contains('onlysong=0')) {
          detailCalls++;
          if (detailCalls == 1) {
            return _jsonBody({
              'cdlist': [
                {
                  'dissname': '我的歌单',
                  'songlist': [
                    {
                      'songmid': 'song_a',
                      'songname': '歌A',
                      'singer': [
                        {'name': '歌手A'},
                      ],
                    },
                  ],
                },
              ],
            });
          }
          return _jsonBody({
            'cdlist': [
              {
                'dissname': '我的歌单',
                'songlist': [
                  {
                    'songmid': 'song_a',
                    'songname': '歌A',
                    'singer': [
                      {'name': '歌手A'},
                    ],
                  },
                  {
                    'songmid': 'song_b',
                    'songname': '歌B',
                    'singer': [
                      {'name': '歌手B'},
                    ],
                  },
                ],
              },
            ],
          });
        }
        return _jsonBody(<String, dynamic>{}, statusCode: 404);
      });

      final container = ProviderContainer(
        overrides: [
          playlistImportDioProvider.overrideWith((ref) => dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(localPlaylistProvider.notifier).loadPlaylists();
      final service = container.read(playlistImportServiceProvider);

      final first = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/778899',
        modeScope: 'xiaomusic',
      );
      expect(first.success, isTrue);
      expect(first.importedCount, 1);

      final second = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/778899',
        modeScope: 'xiaomusic',
        onImportedConflict: (_) async => ImportAction.mergeUpdate,
      );
      expect(second.success, isTrue);
      expect(second.mergedCount, 1);

      final playlists = container.read(localPlaylistProvider).playlists;
      final playlist = playlists.firstWhere(
        (p) => p.sourcePlaylistId == '778899' && p.sourcePlatform == 'tx',
      );
      expect(playlist.songs.length, 2);
      expect(playlist.songs.any((s) => s.songId == 'song_a'), isTrue);
      expect(playlist.songs.any((s) => s.songId == 'song_b'), isTrue);
    });

    test('已导入歌单选择重新导入时会替换旧歌曲', () async {
      int detailCalls = 0;
      final dio = _buildDio((options) {
        final uri = options.uri.toString();
        if (uri.contains('onlysong=1')) {
          return _jsonBody({
            'cdlist': [
              {'dissname': '替换测试歌单', 'songnum': 1},
            ],
          });
        }
        if (uri.contains('onlysong=0')) {
          detailCalls++;
          if (detailCalls == 1) {
            return _jsonBody({
              'cdlist': [
                {
                  'dissname': '替换测试歌单',
                  'songlist': [
                    {
                      'songmid': 'old_song',
                      'songname': '旧歌',
                      'singer': [
                        {'name': '老歌手'},
                      ],
                    },
                  ],
                },
              ],
            });
          }
          return _jsonBody({
            'cdlist': [
              {
                'dissname': '替换测试歌单',
                'songlist': [
                  {
                    'songmid': 'new_song',
                    'songname': '新歌',
                    'singer': [
                      {'name': '新歌手'},
                    ],
                  },
                ],
              },
            ],
          });
        }
        return _jsonBody(<String, dynamic>{}, statusCode: 404);
      });

      final container = ProviderContainer(
        overrides: [
          playlistImportDioProvider.overrideWith((ref) => dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(localPlaylistProvider.notifier).loadPlaylists();
      final service = container.read(playlistImportServiceProvider);

      final first = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/991122',
        modeScope: 'xiaomusic',
      );
      expect(first.success, isTrue);
      expect(first.importedCount, 1);

      final second = await service.importFromUrl(
        'https://y.qq.com/n/ryqq/playlist/991122',
        modeScope: 'xiaomusic',
        onImportedConflict: (_) async => ImportAction.reimport,
      );
      expect(second.success, isTrue);
      expect(second.importedCount, 1);

      final playlists = container.read(localPlaylistProvider).playlists;
      final sameSource =
          playlists
              .where(
                (p) => p.sourcePlaylistId == '991122' && p.sourcePlatform == 'tx',
              )
              .toList();
      expect(sameSource.length, 1);
      expect(sameSource.first.songs.length, 1);
      expect(sameSource.first.songs.first.songId, 'new_song');
    });
  });
}
