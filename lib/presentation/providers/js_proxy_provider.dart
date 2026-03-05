import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/enhanced_js_proxy_executor_service.dart';
import '../../data/models/online_music_result.dart';
import '../../data/models/js_script.dart';
import '../../data/utils/lx_music_info_builder.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/source_settings_provider.dart';
import '../providers/js_script_manager_provider.dart';

/// JS代理执行器状态
class JSProxyState {
  final bool isInitialized;
  final bool isLoading;
  final String? currentScript;
  final Map<String, dynamic> supportedSources;
  final bool hasRequestHandler; // 🎯 是否有 request 处理器注册
  final String? error;

  const JSProxyState({
    this.isInitialized = false,
    this.isLoading = false,
    this.currentScript,
    this.supportedSources = const {},
    this.hasRequestHandler = false, // 🎯 默认为 false
    this.error,
  });

  JSProxyState copyWith({
    bool? isInitialized,
    bool? isLoading,
    String? currentScript,
    Map<String, dynamic>? supportedSources,
    bool? hasRequestHandler, // 🎯 添加到 copyWith
    String? error,
  }) {
    return JSProxyState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      currentScript: currentScript ?? this.currentScript,
      supportedSources: supportedSources ?? this.supportedSources,
      hasRequestHandler: hasRequestHandler ?? this.hasRequestHandler, // 🎯 复制逻辑
      error: error,
    );
  }
}

/// JS代理执行器Provider
class JSProxyNotifier extends StateNotifier<JSProxyState> {
  final Ref _ref;

  JSProxyNotifier(this._ref, {bool autoInit = true})
    : super(const JSProxyState()) {
    if (autoInit) {
      _initializeService();
    }
  }

  final EnhancedJSProxyExecutorService _service =
      EnhancedJSProxyExecutorService();

  /// 🔧 记录是否已经尝试过重新加载脚本，避免无限循环
  bool _hasReloadedScript = false;

  /// 初始化服务
  Future<void> _initializeService() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      await _service.initialize();

      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        error: null,
      );

      print('[JSProxyProvider] ✅ JS代理服务初始化完成');

      // 延迟自动加载，等待其他provider初始化完成
      Future.delayed(const Duration(milliseconds: 1000), () async {
        await _autoLoadSelectedScript();
      });
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '初始化失败: $e');
      print('[JSProxyProvider] ❌ 初始化失败: $e');
    }
  }

  /// 自动加载已选脚本
  Future<void> _autoLoadSelectedScript() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 🛡️ 崩溃保护：检查上次脚本加载是否导致崩溃
      final lastLoadCrashed = prefs.getBool('script_load_in_progress') ?? false;
      if (lastLoadCrashed) {
        print('[JSProxyProvider] ⚠️ 检测到上次脚本加载崩溃，跳过自动加载并清除选中脚本');
        // 清除崩溃标记
        await prefs.setBool('script_load_in_progress', false);
        // 清除选中的脚本，防止下次再次崩溃
        await prefs.remove('selected_script_id');
        // 通知用户
        state = state.copyWith(error: '检测到脚本兼容性问题，已自动禁用。请尝试其他脚本。');
        return;
      }

      final settings = _ref.read(sourceSettingsProvider);
      print(
        '[JSProxyProvider] 📋 检查自动加载条件: primarySource=${settings.primarySource}',
      );

      if (settings.primarySource == 'js_external') {
        final scripts = _ref.read(jsScriptManagerProvider);
        final manager = _ref.read(jsScriptManagerProvider.notifier);
        final selected = manager.selectedScript;

        print('[JSProxyProvider] 📋 脚本列表数量: ${scripts.length}');
        print('[JSProxyProvider] 📋 当前选中ID: ${manager.selectedScriptId}');
        print('[JSProxyProvider] 📋 选中脚本: ${selected?.name ?? 'null'}');

        if (selected != null) {
          print('[JSProxyProvider] 🚀 自动加载已选脚本: ${selected.name}');

          // 🎯 关键修复：APP启动时清除脚本缓存，强制从源重新加载
          // 这样可以确保动态token脚本能够重新初始化获取新token
          final cacheKey = _buildCacheKey(selected);
          final hadCache = prefs.containsKey(cacheKey);
          if (hadCache) {
            await prefs.remove(cacheKey);
            print('[JSProxyProvider] 🧹 已清除脚本缓存，将从源重新加载以获取新token');
          }

          // 🛡️ 设置崩溃保护标记（加载前）
          await prefs.setBool('script_load_in_progress', true);

          final success = await loadScriptByScript(selected);

          // 🛡️ 加载成功，清除崩溃保护标记
          await prefs.setBool('script_load_in_progress', false);

          print('[JSProxyProvider] 📊 自动加载结果: $success');
        } else {
          print('[JSProxyProvider] ⚠️ 未选择脚本或脚本管理器未加载，跳过自动加载');
        }
      } else {
        print('[JSProxyProvider] ℹ️ 不是JS流程，跳过自动加载');
      }
    } catch (e) {
      print('[JSProxyProvider] ❌ 自动加载脚本异常: $e');
      // 🛡️ 异常时也要清除崩溃保护标记
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('script_load_in_progress', false);
      } catch (_) {}
    }
  }

  /// 加载JS脚本
  Future<bool> loadScript(String scriptContent, {String? scriptName}) async {
    if (!state.isInitialized) {
      print('[JSProxyProvider] ⚠️ 服务未初始化');
      return false;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      final success = await _service.loadScript(scriptContent);

      if (success) {
        // 🔧 修复：等待脚本完成异步初始化（某些脚本使用 setTimeout 延迟注册）
        await Future.delayed(const Duration(milliseconds: 500));

        final sources = _service.getSupportedSources();
        var hasHandler = _service.hasRequestHandler(); // 🎯 检查是否有 request 处理器

        // 🔧 修复：如果没有检测到处理器，再等待一次并重试
        if (!hasHandler) {
          print('[JSProxyProvider] ⏳ 未检测到处理器，等待脚本异步注册...');
          await Future.delayed(const Duration(milliseconds: 1000));
          hasHandler = _service.hasRequestHandler();
          print('[JSProxyProvider] 🔄 重试检测 hasRequestHandler: $hasHandler');
        }

        state = state.copyWith(
          isLoading: false,
          currentScript: scriptName ?? '已加载脚本',
          supportedSources: sources,
          hasRequestHandler: hasHandler, // 🎯 更新状态
          error: null,
        );

        print('[JSProxyProvider] ✅ 脚本加载成功: ${scriptName ?? '未命名脚本'}');
        print('[JSProxyProvider] 📋 支持的音源: ${sources.keys.join(', ')}');
        print('[JSProxyProvider] 🔍 有 request 处理器: $hasHandler'); // 🎯 日志
        return true;
      } else {
        // 🔧 修复：使用 service 的 lastLoadError 提供精确的错误信息
        final errorMsg = _service.lastLoadError ?? '脚本加载失败';
        state = state.copyWith(isLoading: false, error: errorMsg);
        print('[JSProxyProvider] ❌ 脚本加载失败: $errorMsg');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载异常: $e');
      print('[JSProxyProvider] ❌ 脚本加载异常: $e');
      return false;
    }
  }

  /// 根据 JsScript 条目加载脚本（支持URL/本地文件/内置），带本地缓存
  Future<bool> loadScriptByScript(JsScript script) async {
    try {
      String? content;
      String scriptName = script.name;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _buildCacheKey(script);

      // 1) 先尝试读取缓存
      content = prefs.getString(cacheKey);
      if (content != null && content.isNotEmpty) {
        print(
          '[JSProxyProvider] 💾 使用已缓存脚本: ${script.name} (${content.length} chars)',
        );
      }

      // 2) 缓存为空则读取源
      if (content == null || content.isEmpty) {
        if (script.source == JsScriptSource.localFile) {
          final manager = _ref.read(jsScriptManagerProvider.notifier);
          content = await manager.getScriptContent(script);
          if (content != null) {
            print(
              '[JSProxyProvider] 📂 读取本地脚本成功: ${script.content} (${content.length} chars)',
            );
          }
        } else if (script.source == JsScriptSource.url) {
          final url = script.content;
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode == 200) {
            content = utf8.decode(resp.bodyBytes, allowMalformed: true);
            print(
              '[JSProxyProvider] 🌐 下载脚本成功: ${url} (${content.length} chars)',
            );
          }
        } else {
          content = script.content;
          print('[JSProxyProvider] 🏷️ 内置脚本长度: ${content.length}');
        }

        // 3) 成功读取后写入缓存
        if (content != null && content.isNotEmpty) {
          await prefs.setString(cacheKey, content);
          print('[JSProxyProvider] ✅ 已缓存脚本内容: $cacheKey');
        }
      }

      if (content == null || content.trim().isEmpty) {
        print('[JSProxyProvider] ❌ 读取脚本内容失败');
        return false;
      }

      return await loadScript(content, scriptName: scriptName);
    } catch (e) {
      print('[JSProxyProvider] ❌ loadScriptByScript 异常: $e');
      return false;
    }
  }

  String _buildCacheKey(JsScript script) {
    return 'js_cached_content_${script.id}';
  }

  /// 从URL加载JS脚本
  Future<bool> loadScriptFromUrl(String url) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // 这里可以使用现有的网络服务获取脚本内容
      // 暂时先用简单的方式
      print('[JSProxyProvider] 🌐 从URL加载脚本: $url');

      // TODO: 实现从URL获取脚本内容的逻辑
      // final scriptContent = await fetchScriptFromUrl(url);
      // return await loadScript(scriptContent, scriptName: url);

      state = state.copyWith(isLoading: false, error: '从URL加载脚本功能待实现');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '从URL加载失败: $e');
      return false;
    }
  }

  List<String> _buildQualityFallbackList(String quality) {
    final q = quality.toLowerCase();
    final List<String> base;
    switch (q) {
      case 'flac24bit':
      case 'flac24':
        base = ['flac24bit', 'hires', 'flac', '320k', '128k'];
        break;
      case 'lossless':
      case 'flac':
        base = ['flac', '320k', '128k'];
        break;
      case 'hires':
        base = ['hires', 'flac', '320k', '128k'];
        break;
      case '320k':
        base = ['320k', '128k'];
        break;
      case '128k':
        base = ['128k'];
        break;
      default:
        base = [quality, '320k', '128k'];
        break;
    }

    final seen = <String>{};
    final result = <String>[];
    for (final item in base) {
      final key = item.toLowerCase();
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  /// 获取音乐播放链接
  /// 🎯 增强：失败时自动重新加载脚本并重试一次
  Future<String?> getMusicUrl({
    required String source,
    required String songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!state.isInitialized || state.currentScript == null) {
      print('[JSProxyProvider] ⚠️ 服务未初始化或脚本未加载');
      return null;
    }

    // 检查是否支持该音源
    print('[JSProxyProvider] 🔍 当前状态检查:');
    print('[JSProxyProvider] 🔍 isInitialized: ${state.isInitialized}');
    print('[JSProxyProvider] 🔍 currentScript: ${state.currentScript}');
    print(
      '[JSProxyProvider] 🔍 supportedSources count: ${state.supportedSources.length}',
    );
    print(
      '[JSProxyProvider] 🔍 supportedSources keys: ${state.supportedSources.keys.join(', ')}',
    );

    // 尝试重新获取音源（以防状态不同步）
    if (state.supportedSources.isEmpty && state.isInitialized) {
      print('[JSProxyProvider] 🔄 音源列表为空，尝试重新获取...');
      final freshSources = _service.getSupportedSources();
      print('[JSProxyProvider] 🔄 重新获取的音源: ${freshSources.keys.join(', ')}');
      if (freshSources.isNotEmpty) {
        state = state.copyWith(supportedSources: freshSources);
        print('[JSProxyProvider] 🔄 已更新状态中的音源列表');
      }
    }

    // 对于未声明支持列表的脚本，或加密脚本隐藏了sources，放宽校验：记录告警但继续尝试
    if (!state.supportedSources.containsKey(source)) {
      print('[JSProxyProvider] ⚠️ 脚本未声明支持该音源或音源列表为空: $source');
      print(
        '[JSProxyProvider] 📋 已声明的音源: ${state.supportedSources.keys.join(', ')}',
      );
      print('[JSProxyProvider] ℹ️ 继续尝试通过脚本的请求处理器获取链接...');
      // 不再提前返回，后续直接尝试 _service.getMusicUrl
    }

    try {
      final fallbackList = _buildQualityFallbackList(quality);
      for (final q in fallbackList) {
        print('[JSProxyProvider] 🎵 获取音乐链接: $source/$songId/$q');
        final url = await _service.getMusicUrl(
          source: source,
          songId: songId,
          quality: q,
          musicInfo: musicInfo,
        );

        if (url != null && url.isNotEmpty) {
          if (q != quality) {
            print('[JSProxyProvider] ✅ 已降级音质: $quality -> $q');
          } else {
            print('[JSProxyProvider] ✅ 成功获取音乐链接');
          }
          // 🎯 成功后重置重试标记
          _hasReloadedScript = false;
          return url;
        }
      }

      // 🎯 获取失败，尝试重新加载脚本并重试
      if (!_hasReloadedScript) {
        print('[JSProxyProvider] ⚠️ 获取链接失败，尝试重新加载脚本...');
        final reloaded = await _reloadScriptAndRetry();
        if (reloaded) {
          _hasReloadedScript = true;
          print('[JSProxyProvider] 🔄 脚本已重新加载，重试获取链接...');
          // 递归调用自己重试一次
          return getMusicUrl(
            source: source,
            songId: songId,
            quality: quality,
            musicInfo: musicInfo,
          );
        }
      }

      print('[JSProxyProvider] ❌ 获取音乐链接失败（已尝试重新加载脚本）');
      _hasReloadedScript = false; // 重置标记
      return null;
    } catch (e) {
      print('[JSProxyProvider] ❌ 获取音乐链接异常: $e');
      _hasReloadedScript = false; // 重置标记
      return null;
    }
  }

  /// 🎯 重新加载脚本（清除缓存后从源重新获取）
  Future<bool> _reloadScriptAndRetry() async {
    try {
      final scripts = _ref.read(jsScriptManagerProvider);
      final manager = _ref.read(jsScriptManagerProvider.notifier);
      final selected = manager.selectedScript;

      if (selected == null) {
        print('[JSProxyProvider] ⚠️ 无法重新加载：未选择脚本');
        return false;
      }

      print('[JSProxyProvider] 🧹 清除脚本缓存: ${selected.name}');
      // 清除当前脚本的缓存
      await clearCurrentScriptCache();

      print('[JSProxyProvider] 🔄 重新加载脚本: ${selected.name}');
      // 重新加载脚本（会从源获取新内容）
      final success = await loadScriptByScript(selected);

      if (success) {
        print('[JSProxyProvider] ✅ 脚本重新加载成功');
        // 等待脚本初始化完成
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        print('[JSProxyProvider] ❌ 脚本重新加载失败');
      }

      return success;
    } catch (e) {
      print('[JSProxyProvider] ❌ 重新加载脚本异常: $e');
      return false;
    }
  }

  /// 解析OnlineMusicResult为播放链接
  Future<OnlineMusicResult?> resolveOnlineMusicResult(
    OnlineMusicResult result, {
    String? preferredQuality,
  }) async {
    if (!state.isInitialized || state.currentScript == null) {
      return null;
    }

    try {
      // 确定使用的音质
      final quality = preferredQuality ?? '320k';

      // 使用JS代理获取真实播放链接
      final resolvedUrl = await getMusicUrl(
        source: result.platform ?? 'unknown',
        songId: result.songId ?? 'unknown',
        quality: quality,
        musicInfo: buildLxMusicInfoFromOnlineResult(result),
      );

      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        // 返回解析后的结果，创建新的OnlineMusicResult
        return OnlineMusicResult(
          songId: result.songId ?? '',
          title: result.title,
          author: result.author,
          url: resolvedUrl, // 使用解析后的URL
          album: result.album,
          duration: result.duration,
          platform: result.platform ?? 'unknown',
          extra: result.extra,
        );
      }

      return null;
    } catch (e) {
      print('[JSProxyProvider] ❌ 解析OnlineMusicResult失败: $e');
      return null;
    }
  }

  /// 批量解析音乐结果
  Future<List<OnlineMusicResult>> resolveMultipleResults(
    List<OnlineMusicResult> results, {
    String? preferredQuality,
    int maxConcurrent = 3,
  }) async {
    if (!state.isInitialized || state.currentScript == null) {
      return [];
    }

    final resolvedResults = <OnlineMusicResult>[];

    // 分批处理，避免过多并发请求
    for (int i = 0; i < results.length; i += maxConcurrent) {
      final batch = results.skip(i).take(maxConcurrent).toList();

      final futures = batch.map(
        (result) => resolveOnlineMusicResult(
          result,
          preferredQuality: preferredQuality,
        ),
      );

      final batchResults = await Future.wait(futures);

      // 添加成功解析的结果
      for (final resolved in batchResults) {
        if (resolved != null) {
          resolvedResults.add(resolved);
        }
      }

      // 短暂延迟，避免请求过于频繁
      if (i + maxConcurrent < results.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    print(
      '[JSProxyProvider] 📊 批量解析完成: ${resolvedResults.length}/${results.length}',
    );
    return resolvedResults;
  }

  /// 获取支持的音源列表
  List<String> getSupportedSourcesList() {
    return state.supportedSources.keys.toList();
  }

  /// 检查是否支持指定音源
  bool supportsSource(String source) {
    return state.supportedSources.containsKey(source);
  }

  /// 获取音源支持的音质列表
  List<String> getSupportedQualities(String source) {
    final sourceInfo = state.supportedSources[source];
    if (sourceInfo is Map && sourceInfo.containsKey('qualitys')) {
      return List<String>.from(sourceInfo['qualitys'] ?? []);
    }
    return ['128k', '320k', 'flac']; // 默认音质
  }

  /// 清除当前脚本
  void clearScript() {
    state = state.copyWith(
      currentScript: null,
      supportedSources: {},
      error: null,
    );
    print('[JSProxyProvider] 🧹 已清除当前脚本');
  }

  /// 清除当前选中脚本的缓存内容
  Future<bool> clearCurrentScriptCache() async {
    try {
      final scripts = _ref.read(jsScriptManagerProvider);
      final manager = _ref.read(jsScriptManagerProvider.notifier);
      final selected = manager.selectedScript;
      if (selected == null) return false;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _buildCacheKey(selected);
      final ok = await prefs.remove(cacheKey);
      print('[JSProxyProvider] 🧹 已清除缓存: $cacheKey -> $ok');
      return ok;
    } catch (e) {
      print('[JSProxyProvider] ❌ 清除当前脚本缓存失败: $e');
      return false;
    }
  }

  /// 清除所有脚本缓存
  Future<int> clearAllScriptCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs
              .getKeys()
              .where((k) => k.startsWith('js_cached_content_'))
              .toList();
      int removed = 0;
      for (final k in keys) {
        final ok = await prefs.remove(k);
        if (ok) removed++;
      }
      print('[JSProxyProvider] 🧹 已清除 ${removed}/${keys.length} 个脚本缓存');
      return removed;
    } catch (e) {
      print('[JSProxyProvider] ❌ 清除所有脚本缓存失败: $e');
      return 0;
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

/// JS代理执行器Provider
final jsProxyProvider = StateNotifierProvider<JSProxyNotifier, JSProxyState>((
  ref,
) {
  return JSProxyNotifier(ref);
});
