import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_id.dart';
import '../../presentation/providers/js_proxy_provider.dart';
import '../../presentation/providers/js_source_provider.dart';
import '../../presentation/providers/source_settings_provider.dart';
import '../models/online_music_result.dart';
import '../models/search_outcome.dart';
import '../utils/lx_music_info_builder.dart';
import 'native_music_search_service.dart';
import 'platform_circuit_breaker.dart';
import 'song_matcher.dart';

class SongResolveRequest {
  const SongResolveRequest({
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    required this.originalPlatform,
    required this.originalSongId,
    this.knownPlatformSongIds = const <String, String>{},
    this.preferredStrategy,
    this.quality = '320k',
  });

  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final int? duration;

  final String originalPlatform;
  final String originalSongId;
  final Map<String, String> knownPlatformSongIds;

  final String? preferredStrategy;
  final String quality;
}

class SongResolveResult {
  const SongResolveResult({
    required this.url,
    required this.platform,
    required this.songId,
    required this.platformSongIds,
    this.duration,
  });

  final String url;
  final String platform;
  final String songId;
  final int? duration;
  final Map<String, String> platformSongIds;
}

class SongResolverService {
  SongResolverService(this._ref);

  final Ref _ref;
  final PlatformCircuitBreaker _breaker = PlatformCircuitBreaker();

  void resetCircuitBreaker() {
    _breaker.reset();
  }

  Future<SongResolveResult?> resolveSong(SongResolveRequest request) async {
    final originalPlatform = PlatformId.normalize(request.originalPlatform);
    final knownIds = <String, String>{
      for (final e in request.knownPlatformSongIds.entries)
        PlatformId.normalize(e.key): e.value,
    };
    knownIds[originalPlatform] = request.originalSongId;

    final strategy =
        request.preferredStrategy ?? _ref.read(sourceSettingsProvider).playlistResolveStrategy;

    var plan = _buildResolvePlatformPlan(
      strategy,
      originalPlatform: originalPlatform,
    );
    plan = _breaker.adjustOrder(plan);

    debugPrint('🔧 [SongResolver] 解析计划: strategy=$strategy, plan=$plan');

    for (final platform in plan) {
      try {
        String? songId = knownIds[platform];
        if (_isLikelyInvalidSongIdForPlatform(platform, songId)) {
          songId = null;
        }

        int? resolvedDuration = request.duration;
        String? resolvedAlbum = request.album;
        String? resolvedCover = request.coverUrl;

        if (songId == null || songId.isEmpty) {
          final outcome = await _searchWithOutcome(
            platform: platform,
            title: request.title,
            artist: request.artist,
          );

          if (!outcome.hasResults) {
            if (outcome.errorType != SearchErrorType.noResults) {
              debugPrint(
                '⚠️ [SongResolver] 平台=$platform 搜索异常: ${outcome.errorType} ${outcome.message ?? ''}',
              );
            }
            continue;
          }

          final best = SongMatcher.bestMatch(
            candidates: outcome.results,
            targetTitle: request.title,
            targetArtist: request.artist,
            targetDuration: request.duration,
          );

          if (best == null || best.songId == null || best.songId!.isEmpty) {
            debugPrint('⚠️ [SongResolver] 平台=$platform 无可信候选');
            continue;
          }

          songId = best.songId!;
          if (_isLikelyInvalidSongIdForPlatform(platform, songId)) {
            debugPrint('⚠️ [SongResolver] 平台=$platform 候选songId无效: $songId');
            continue;
          }

          knownIds[platform] = songId;
          resolvedDuration ??= best.duration;
          resolvedAlbum ??= best.album;
          resolvedCover ??= best.picture;
        }

        final musicInfo = buildLxMusicInfo(
          songId: songId,
          title: request.title,
          artist: request.artist,
          album: resolvedAlbum,
          duration: resolvedDuration,
          coverUrl: resolvedCover,
        );

        final url = await _resolveUrlByJsStack(
          platform: platform,
          songId: songId,
          quality: request.quality,
          musicInfo: musicInfo,
        );

        if (url == null || url.isEmpty) {
          _breaker.recordFailure(platform);
          continue;
        }
        if (_isLikelyInvalidResolvedUrl(url)) {
          debugPrint('⚠️ [SongResolver] 平台=$platform 返回疑似无效音频，继续回退');
          _breaker.recordFailure(platform);
          continue;
        }

        _breaker.recordSuccess(platform);
        return SongResolveResult(
          url: url,
          platform: platform,
          songId: songId,
          duration: resolvedDuration,
          platformSongIds: Map<String, String>.from(knownIds),
        );
      } catch (e) {
        _breaker.recordFailure(platform);
        debugPrint('⚠️ [SongResolver] 平台=$platform 解析异常: $e');
      }
    }

    return null;
  }

  List<String> _buildResolvePlatformPlan(
    String strategy, {
    required String originalPlatform,
  }) {
    final original = PlatformId.normalize(originalPlatform);
    switch (strategy) {
      case 'qqFirst':
        return const [PlatformId.tx, PlatformId.kw, PlatformId.wy];
      case 'kuwoFirst':
        return const [PlatformId.kw, PlatformId.tx, PlatformId.wy];
      case 'neteaseFirst':
        return const [PlatformId.wy, PlatformId.tx, PlatformId.kw];
      case 'originalFirst':
      default:
        return PlatformId.degradeOrder(original);
    }
  }

  Future<SearchOutcome<OnlineMusicResult>> _searchWithOutcome({
    required String platform,
    required String title,
    required String artist,
  }) async {
    final nativeSearch = _ref.read(nativeMusicSearchServiceProvider);
    final query = artist.trim().isEmpty ? title.trim() : '${title.trim()} ${artist.trim()}';
    final canonical = PlatformId.normalize(platform);

    switch (PlatformId.toSearchKey(canonical)) {
      case 'qq':
        return nativeSearch.searchQQWithOutcome(query: query, page: 1);
      case 'kuwo':
        return nativeSearch.searchKuwoWithOutcome(query: query, page: 1);
      case 'netease':
        return nativeSearch.searchNeteaseWithOutcome(query: query, page: 1);
      default:
        return SearchOutcome.failure(
          SearchErrorType.unknown,
          message: 'unsupported platform',
        );
    }
  }

  Future<String?> _resolveUrlByJsStack({
    required String platform,
    required String songId,
    required String quality,
    required Map<String, dynamic> musicInfo,
  }) async {
    String? resolvedUrl;

    try {
      final jsProxy = _ref.read(jsProxyProvider.notifier);
      final jsProxyState = _ref.read(jsProxyProvider);
      if (jsProxyState.isInitialized && jsProxyState.currentScript != null) {
        resolvedUrl = await jsProxy.getMusicUrl(
          source: PlatformId.normalize(platform),
          songId: songId,
          quality: quality,
          musicInfo: musicInfo,
        );
      }
    } catch (e) {
      debugPrint('⚠️ [SongResolver] QuickJS解析失败: $e');
    }

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      try {
        final webSvc = await _ref.read(webviewJsSourceServiceProvider.future);
        if (webSvc != null) {
          resolvedUrl = await webSvc.resolveMusicUrl(
            platform: platform,
            songId: songId,
            quality: quality,
          );
        }
      } catch (e) {
        debugPrint('⚠️ [SongResolver] WebView解析失败: $e');
      }
    }

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      try {
        final jsSvc = await _ref.read(jsSourceServiceProvider.future);
        if (jsSvc != null && jsSvc.isReady) {
          final js = """
            (function(){
              try{
                if (!lx || !lx.EVENT_NAMES) return '';
                var musicInfo = ${jsonEncode(musicInfo)};
                var payload = { action: 'musicUrl', source: '${PlatformId.normalize(platform)}', info: { type: '$quality', musicInfo: musicInfo } };
                var res = lx.emit(lx.EVENT_NAMES.request, payload);
                if (res && typeof res.then === 'function') return '';
                if (typeof res === 'string') return res;
                if (res && res.url) return res.url;
                return '';
              }catch(e){
                return '';
              }
            })()
          """;
          final localResolved = jsSvc.evaluateToString(js);
          if (localResolved.isNotEmpty) {
            resolvedUrl = localResolved;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [SongResolver] 内置JS解析失败: $e');
      }
    }

    return resolvedUrl;
  }

  bool _isLikelyInvalidResolvedUrl(String url) {
    final lower = url.toLowerCase();
    const badKeywords = [
      'trial',
      'vip',
      'member',
      'listen_tip',
      'pay',
      'open',
      'rights',
      'permission',
    ];
    return badKeywords.any((k) => lower.contains(k));
  }

  bool _isLikelyInvalidSongIdForPlatform(String platform, String? songId) {
    if (songId == null || songId.isEmpty) return true;
    final canonical = PlatformId.normalize(platform);
    if (canonical == PlatformId.tx) {
      return RegExp(r'^\d+$').hasMatch(songId);
    }
    return false;
  }
}

final songResolverServiceProvider = Provider<SongResolverService>((ref) {
  final service = SongResolverService(ref);

  ref.listen<String?>(jsProxyProvider.select((s) => s.currentScript), (
    previous,
    next,
  ) {
    if (previous != null && previous != next) {
      service.resetCircuitBreaker();
      debugPrint('🔄 [SongResolver] JS脚本切换，熔断器已重置');
    }
  });

  return service;
});
