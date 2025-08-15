import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/music.dart';
import '../../data/models/online_music_result.dart';
import '../../data/services/unified_api_service.dart';
import 'source_settings_provider.dart';
import '../../data/adapters/search_adapter.dart';
import 'js_source_provider.dart';

class MusicSearchState {
  final List<Music> searchResults;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final List<OnlineMusicResult> onlineResults;

  const MusicSearchState({
    this.searchResults = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.onlineResults = const [],
  });

  MusicSearchState copyWith({
    List<Music>? searchResults,
    bool? isLoading,
    String? error,
    String? searchQuery,
    List<OnlineMusicResult>? onlineResults,
  }) {
    return MusicSearchState(
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      onlineResults: onlineResults ?? this.onlineResults,
    );
  }
}

class MusicSearchNotifier extends StateNotifier<MusicSearchState> {
  final Ref ref;

  MusicSearchNotifier(this.ref) : super(const MusicSearchState());

  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: [], searchQuery: '', error: null);
      return;
    }

    // 仅保留统一API，不再依赖本地索引
    // 统一API下无需预先读取服务，这里仅等待设置加载

    try {
      state = state.copyWith(isLoading: true, searchQuery: query, error: null);
      final unified = ref.read(unifiedApiServiceProvider);
      final results = await unified.searchMusic(query: query, platform: 'qq');
      final musicList = SearchAdapter.parse(results);

      state = state.copyWith(
        searchResults: musicList,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        searchResults: [],
      );
    }
  }

  // 第三方在线搜索
  Future<void> searchOnline(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(onlineResults: [], searchQuery: '', error: null);
      return;
    }

    try {
      print('[XMC] 🔍 searchOnline: start query="$query"');
      state = state.copyWith(isLoading: true, searchQuery: query, error: null);

      // 等待音源设置完成加载，避免读取到默认值
      final settingsNotifier = ref.read(sourceSettingsProvider.notifier);
      int __waitLoops = 0;
      while (!settingsNotifier.isLoaded && __waitLoops < 20) {
        await Future.delayed(const Duration(milliseconds: 50));
        __waitLoops++;
      }
      var settings = ref.read(sourceSettingsProvider);

      print('[XMC] 🔧 [MusicSearch] 主要音源: ${settings.primarySource}');
      // JS音源是否启用由 primarySource 控制，不再单独依赖 enabled
      print(
        '[XMC] 🔧 [MusicSearch] JS音源启用(由primarySource推断): ${settings.primarySource == 'js_external'}',
      );
      print('[XMC] 🔧 [MusicSearch] 使用统一API: ${settings.useUnifiedApi}');
      print('[XMC] 🔧 [MusicSearch] 统一API地址: ${settings.unifiedApiBase}');

      List<OnlineMusicResult> parsed = [];

      // 根据primarySource设置选择音源
      if (settings.primarySource == 'js_external') {
        print('[XMC] 🎵 [MusicSearch] 使用JS外置音源');
        parsed = await _searchUsingJsSource(query, settings, ref);

        // 如果JS音源搜索失败，回退到统一API
        if (parsed.isEmpty && settings.useUnifiedApi) {
          print('[XMC] 🔄 [MusicSearch] JS音源无结果，回退到统一API');
          parsed = await _searchUsingUnifiedAPI(query, settings, ref);
        }
      } else if (settings.primarySource == 'unified' ||
          settings.useUnifiedApi) {
        print('[XMC] 🎵 [MusicSearch] 使用统一API');
        parsed = await _searchUsingUnifiedAPI(query, settings, ref);
      } else {
        print('[XMC] ⚠️ [MusicSearch] 无可用音源，使用默认统一API');
        parsed = await _searchUsingUnifiedAPI(query, settings, ref);
      }

      state = state.copyWith(isLoading: false, onlineResults: parsed);
      print('[XMC] 🔍 searchOnline: done, parsed=${parsed.length}');
    } catch (e) {
      print('[XMC] 🔍 searchOnline: error=$e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        onlineResults: [],
      );
    }
  }

  // JS音源搜索和统一API搜索

  /// 使用JS音源进行搜索
  Future<List<OnlineMusicResult>> _searchUsingJsSource(
    String query,
    SourceSettings settings,
    Ref ref,
  ) async {
    try {
      print('🎵 [MusicSearch] JS音源模式');

      // 先尝试：隐藏 WebView JS（适配落雪/野草🌾）
      try {
        final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
        if (webSvc != null) {
          final results = await webSvc
              .search(
                query,
                // JS 模式下固定为 auto，让脚本自适应平台
                platform: 'auto',
                page: 1,
              )
              .timeout(
                const Duration(seconds: 18),
                onTimeout: () => <Map<String, dynamic>>[],
              );

          if (results.isNotEmpty) {
            print('[XMC] 🔍 [MusicSearch] WebView JS返回 ${results.length} 个结果');
            final converted =
                results.map((item) {
                  return OnlineMusicResult(
                    songId: (item['songmid'] ?? item['id'] ?? '').toString(),
                    title: (item['title'] ?? '未知标题').toString(),
                    author:
                        (item['artist'] ?? item['singer'] ?? '未知艺术家')
                            .toString(),
                    url: (item['url'] ?? item['link'] ?? '').toString(),
                    album: (item['album'] ?? '').toString(),
                    duration: _parseDuration(item['duration']),
                    platform:
                        (item['platform'] ?? settings.platform).toString(),
                    extra: const {'sourceApi': 'js_builtin'},
                  );
                }).toList();
            return converted;
          }
        }
      } catch (e) {
        print('[XMC] ⚠️ [MusicSearch] WebView JS搜索异常: $e');
      }

      // 回退：LocalJS
      try {
        final jsService = await ref.read(jsSourceServiceProvider.future);
        if (jsService == null || !jsService.isReady) {
          print('[XMC] ❌ [MusicSearch] LocalJS 音源不可用');
          return [];
        }
        final results = await jsService
            .search(
              query,
              platform: settings.platform == 'auto' ? 'qq' : settings.platform,
              page: 1,
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => <Map<String, dynamic>>[],
            );
        print('[XMC] 🔍 [MusicSearch] LocalJS 返回 ${results.length} 个结果');
        final converted =
            results.map((item) {
              return OnlineMusicResult(
                songId: item['id']?.toString() ?? '',
                title: item['title']?.toString() ?? '未知标题',
                author: item['artist']?.toString() ?? '未知艺术家',
                url: item['url']?.toString() ?? '',
                album: item['album']?.toString() ?? '',
                duration: _parseDuration(item['duration']),
                platform: item['platform']?.toString() ?? 'js',
                extra: const {'sourceApi': 'js_builtin'},
              );
            }).toList();
        return converted;
      } catch (e) {
        print('[XMC] ❌ [MusicSearch] LocalJS 搜索异常: $e');
        return [];
      }
    } catch (e) {
      print('[XMC] ❌ [MusicSearch] JS音源搜索失败: $e');
      return [];
    }
  }

  /// 解析持续时间
  int _parseDuration(dynamic duration) {
    if (duration == null) return 0;
    if (duration is int) return duration;
    if (duration is double) return duration.round();
    if (duration is String) {
      // 尝试解析 "mm:ss" 格式
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return minutes * 60 + seconds;
      }
      // 尝试直接解析数字
      return int.tryParse(duration) ?? 0;
    }
    return 0;
  }

  /// 使用统一API进行搜索
  Future<List<OnlineMusicResult>> _searchUsingUnifiedAPI(
    String query,
    SourceSettings settings,
    Ref ref,
  ) async {
    try {
      print('🎵 [MusicSearch] 统一API模式');
      final unifiedService = ref.read(unifiedApiServiceProvider);

      try {
        final results = await unifiedService
            .searchMusic(
              query: query,
              platform: settings.platform == 'auto' ? 'qq' : settings.platform,
              page: 1,
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => <OnlineMusicResult>[],
            );

        print('[XMC] 🔍 [MusicSearch] 统一API返回 ${results.length} 个结果');
        return results;
      } catch (e) {
        print('[XMC] ❌ [MusicSearch] 统一API搜索异常: $e');
        return [];
      }
    } catch (e) {
      print('[XMC] ❌ [MusicSearch] 统一API搜索失败: $e');
      return [];
    }
  }

  void clearSearch() {
    state = state.copyWith(searchResults: [], searchQuery: '', error: null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// 统一API服务Provider
final unifiedApiServiceProvider = Provider<UnifiedApiService>((ref) {
  final settings = ref.watch(sourceSettingsProvider);
  return UnifiedApiService(baseUrl: settings.unifiedApiBase);
});

// 移除YouTube代理Provider，仅保留统一API

final musicSearchProvider =
    StateNotifierProvider<MusicSearchNotifier, MusicSearchState>((ref) {
      return MusicSearchNotifier(ref);
    });
