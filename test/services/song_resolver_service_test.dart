import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmusic/data/models/online_music_result.dart';
import 'package:hmusic/data/models/search_outcome.dart';
import 'package:hmusic/data/services/native_music_search_service.dart';
import 'package:hmusic/data/services/song_resolver_service.dart';
import 'package:hmusic/presentation/providers/js_proxy_provider.dart';
import 'package:hmusic/presentation/providers/js_source_provider.dart';

class _FakeNativeMusicSearchService extends NativeMusicSearchService {
  int qqCalls = 0;
  int kuwoCalls = 0;
  int neteaseCalls = 0;

  List<OnlineMusicResult> qqResults = const [];
  List<OnlineMusicResult> kuwoResults = const [];
  List<OnlineMusicResult> neteaseResults = const [];

  @override
  Future<SearchOutcome<OnlineMusicResult>> searchQQWithOutcome({
    required String query,
    required int page,
  }) async {
    qqCalls++;
    if (qqResults.isEmpty) {
      return SearchOutcome.failure(SearchErrorType.noResults);
    }
    return SearchOutcome.success(qqResults);
  }

  @override
  Future<SearchOutcome<OnlineMusicResult>> searchKuwoWithOutcome({
    required String query,
    required int page,
  }) async {
    kuwoCalls++;
    if (kuwoResults.isEmpty) {
      return SearchOutcome.failure(SearchErrorType.noResults);
    }
    return SearchOutcome.success(kuwoResults);
  }

  @override
  Future<SearchOutcome<OnlineMusicResult>> searchNeteaseWithOutcome({
    required String query,
    required int page,
  }) async {
    neteaseCalls++;
    if (neteaseResults.isEmpty) {
      return SearchOutcome.failure(SearchErrorType.noResults);
    }
    return SearchOutcome.success(neteaseResults);
  }
}

class _FakeJSProxyNotifier extends JSProxyNotifier {
  _FakeJSProxyNotifier(super.ref, this.responses) : super(autoInit: false) {
    state = const JSProxyState(
      isInitialized: true,
      currentScript: 'fake-script',
      supportedSources: {'tx': {}, 'kw': {}, 'wy': {}},
      hasRequestHandler: true,
    );
  }

  final Map<String, String?> responses;
  final List<String> calls = <String>[];

  @override
  Future<String?> getMusicUrl({
    required String source,
    required String songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    final key = '$source:$songId';
    calls.add(key);
    return responses[key];
  }
}

OnlineMusicResult _candidate({
  required String platform,
  required String songId,
  required String title,
  required String artist,
  int duration = 0,
}) {
  return OnlineMusicResult(
    title: title,
    author: artist,
    url: '',
    platform: platform,
    songId: songId,
    duration: duration,
  );
}

void main() {
  group('SongResolverService', () {
    test('原平台可解析时优先使用原平台且不触发搜索', () async {
      final fakeSearch = _FakeNativeMusicSearchService();
      late _FakeJSProxyNotifier fakeJs;

      final container = ProviderContainer(
        overrides: [
          nativeMusicSearchServiceProvider.overrideWith((ref) => fakeSearch),
          jsProxyProvider.overrideWith((ref) {
            fakeJs = _FakeJSProxyNotifier(ref, {
              'tx:tx_mid_1': 'https://ok.example/tx.mp3',
            });
            return fakeJs;
          }),
          webviewJsSourceServiceProvider.overrideWith((ref) async => null),
          jsSourceServiceProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final resolver = container.read(songResolverServiceProvider);
      final result = await resolver.resolveSong(
        const SongResolveRequest(
          title: '测试歌曲',
          artist: '测试歌手',
          originalPlatform: 'tx',
          originalSongId: 'tx_mid_1',
          preferredStrategy: 'originalFirst',
        ),
      );

      expect(result, isNotNull);
      expect(result!.platform, 'tx');
      expect(result.songId, 'tx_mid_1');
      expect(result.url, 'https://ok.example/tx.mp3');
      expect(fakeJs.calls, ['tx:tx_mid_1']);
      expect(fakeSearch.qqCalls, 0);
      expect(fakeSearch.kuwoCalls, 0);
      expect(fakeSearch.neteaseCalls, 0);
    });

    test('原平台失败后可跨平台搜索并解析成功', () async {
      final fakeSearch = _FakeNativeMusicSearchService();
      fakeSearch.qqResults = [
        _candidate(
          platform: 'tx',
          songId: 'tx_mid_hit',
          title: '我已经爱上你',
          artist: '洛先生',
          duration: 278,
        ),
      ];

      late _FakeJSProxyNotifier fakeJs;
      final container = ProviderContainer(
        overrides: [
          nativeMusicSearchServiceProvider.overrideWith((ref) => fakeSearch),
          jsProxyProvider.overrideWith((ref) {
            fakeJs = _FakeJSProxyNotifier(ref, {
              'kw:kw_001': null,
              'tx:tx_mid_hit': 'https://ok.example/fallback-tx.mp3',
            });
            return fakeJs;
          }),
          webviewJsSourceServiceProvider.overrideWith((ref) async => null),
          jsSourceServiceProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final resolver = container.read(songResolverServiceProvider);
      final result = await resolver.resolveSong(
        const SongResolveRequest(
          title: '我已经爱上你',
          artist: '洛先生',
          originalPlatform: 'kw',
          originalSongId: 'kw_001',
          preferredStrategy: 'originalFirst',
        ),
      );

      expect(result, isNotNull);
      expect(result!.platform, 'tx');
      expect(result.songId, 'tx_mid_hit');
      expect(result.url, 'https://ok.example/fallback-tx.mp3');
      expect(result.platformSongIds['kw'], 'kw_001');
      expect(result.platformSongIds['tx'], 'tx_mid_hit');
      expect(fakeSearch.qqCalls, 1);
      expect(fakeJs.calls.first, 'kw:kw_001');
      expect(fakeJs.calls.last, 'tx:tx_mid_hit');
    });

    test('连续失败触发熔断后会调整平台优先级', () async {
      final fakeSearch = _FakeNativeMusicSearchService();
      late _FakeJSProxyNotifier fakeJs;

      final container = ProviderContainer(
        overrides: [
          nativeMusicSearchServiceProvider.overrideWith((ref) => fakeSearch),
          jsProxyProvider.overrideWith((ref) {
            fakeJs = _FakeJSProxyNotifier(ref, {
              'tx:tx_bad': null,
              'kw:kw_good': 'https://ok.example/kw.mp3',
            });
            return fakeJs;
          }),
          webviewJsSourceServiceProvider.overrideWith((ref) async => null),
          jsSourceServiceProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final resolver = container.read(songResolverServiceProvider);
      const req = SongResolveRequest(
        title: '测试歌曲',
        artist: '测试歌手',
        originalPlatform: 'tx',
        originalSongId: 'tx_bad',
        knownPlatformSongIds: {'kw': 'kw_good'},
        preferredStrategy: 'originalFirst',
      );

      for (int i = 0; i < 3; i++) {
        fakeJs.calls.clear();
        final result = await resolver.resolveSong(req);
        expect(result, isNotNull);
        expect(fakeJs.calls.first, 'tx:tx_bad');
      }

      fakeJs.calls.clear();
      final result = await resolver.resolveSong(req);
      expect(result, isNotNull);
      expect(fakeJs.calls.first, 'kw:kw_good');
    });
  });
}
