import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/music_search_provider.dart';
import '../../data/models/online_music_result.dart';
import 'package:dio/dio.dart' as dio;
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/js_source_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import '../providers/music_library_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../providers/device_provider.dart';
import '../providers/dio_provider.dart';
import '../../data/models/device.dart';
import '../providers/playback_provider.dart';

class MusicSearchPage extends ConsumerStatefulWidget {
  const MusicSearchPage({super.key});

  @override
  ConsumerState<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<MusicSearchPage> {
  // legacy dialog removed

  // legacy play removed
  late final WebViewController _wvController;
  @override
  void initState() {
    super.initState();
    _wvController = WebViewController();
    // 提供给 Provider 使用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webviewJsSourceControllerProvider.notifier).state =
          _wvController;
    });
  }

  /// 显示音质相关提示信息

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(musicSearchProvider);

    return Scaffold(
      key: const ValueKey('music_search_scaffold'),
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            _buildContent(searchState),
            // 隐藏的 WebView 用于本地 JS 音源网络请求
            Offstage(
              offstage: true,
              child: SizedBox(
                height: 1,
                width: 1,
                child: WebViewWidget(controller: _wvController),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(MusicSearchState searchState) {
    if (searchState.isLoading) {
      return _buildLoadingIndicator();
    }
    if (searchState.error != null) {
      return _buildErrorState(searchState.error!);
    }
    if (searchState.onlineResults.isNotEmpty) {
      return _buildOnlineResultsList(searchState.onlineResults);
    }
    return _buildInitialState();
  }

  Widget _buildInitialState() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        // 模拟曲库页面的顶部布局间距，保持垂直位置一致
        const SizedBox(height: 20), // 对应曲库页面的顶部间距
        const SizedBox(height: 40), // 模拟搜索框高度 (TextField实际高度)
        const SizedBox(height: 16), // 对应曲库页面搜索框后的间距
        const SizedBox(height: 32), // 模拟统计信息区域的高度
        const SizedBox(height: 8), // 对应曲库页面统计信息后的间距
        Expanded(
          child: Center(
            key: const ValueKey('search_initial'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 80,
                  color: onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 20),
                Text(
                  '开始搜索音乐',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: onSurface.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '输入歌曲、艺术家或专辑名称',
                  style: TextStyle(
                    fontSize: 16,
                    color: onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      key: const ValueKey('search_loading'),
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorState(String error) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      key: const ValueKey('search_error'),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            Text(
              '哦豁，出错了',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(fontSize: 15, color: onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineResultsList(List<OnlineMusicResult> results) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final searchState = ref.watch(musicSearchProvider);
    final isLoadingMore = searchState.isLoadingMore;
    final hasMore = searchState.hasMore;

    final totalCount = results.length + (isLoadingMore ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (hasMore &&
              !isLoadingMore &&
              metrics.pixels >= metrics.maxScrollExtent - 200) {
            ref.read(musicSearchProvider.notifier).loadMore();
          }
        }
        return false;
      },
      child: ListView.separated(
        key: const ValueKey('online_search_results'),
        padding: EdgeInsets.only(
          bottom: AppLayout.contentBottomPadding(context),
          top: 12,
        ),
        itemCount: totalCount,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (isLoadingMore && index == totalCount - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final item = results[index];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: onSurface.withOpacity(0.08),
              child: const Icon(Icons.audiotrack_rounded, size: 18),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              item.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
            ),
            trailing: PopupMenuButton<String>(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: (value) async {
                switch (value) {
                  case 'server':
                    await _downloadToServer(item);
                    break;
                  case 'local':
                    await _downloadToLocal(item);
                    break;
                  case 'play':
                    await _playViaResolver(item);
                    break;
                }
              },
              itemBuilder:
                  (context) => const [
                    PopupMenuItem(value: 'play', child: Text('解析直链并播放')),
                    PopupMenuItem(value: 'server', child: Text('下载到服务器')),
                    PopupMenuItem(value: 'local', child: Text('下载到本地')),
                  ],
              icon: Icon(
                Icons.more_vert_rounded,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                size: 18,
              ),
            ),
            onTap: () => _playViaResolver(item),
          );
        },
      ),
    );
  }

  Future<void> _downloadToServer(OnlineMusicResult item) async {
    try {
      var url = item.url;
      if (url.isEmpty) {
        url = await _resolvePlayUrlForItem(item) ?? '';
      }

      if (url.isEmpty) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('❌ 无法解析直链，下载失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 使用"歌曲名 - 作者名"作为服务端下载名称
      final safeTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeAuthor = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final serverName =
          safeAuthor.isNotEmpty ? '$safeTitle - $safeAuthor' : safeTitle;

      await ref
          .read(musicLibraryProvider.notifier)
          .downloadOneMusic(serverName, url: url);
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('已提交下载任务：${item.title}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('下载失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadToLocal(OnlineMusicResult item) async {
    try {
      var url = item.url;
      if (url.isEmpty) {
        url = await _resolvePlayUrlForItem(item) ?? '';
      }

      if (url.isEmpty) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('❌ 无法解析直链，无法下载'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final titlePart = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final authorPart = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName =
          authorPart.isNotEmpty ? '$titlePart - $authorPart' : titlePart;
      final ext = p.extension(Uri.parse(url).path);
      final filePath = p.join(
        dir.path,
        '$safeName${ext.isEmpty ? '.m4a' : ext}',
      );

      final client = dio.Dio();
      await client.download(
        url,
        filePath,
        options: dio.Options(
          responseType: dio.ResponseType.bytes,
          followRedirects: true,
        ),
      );

      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('已保存到本地: ${p.basename(filePath)}'),
            backgroundColor: Colors.green,
          ),
        );
        await OpenFilex.open(filePath);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('本地下载失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _resolvePlayUrlForItem(OnlineMusicResult item) async {
    try {
      final platform = (item.platform ?? 'qq');
      final id = item.songId ?? '';
      if (id.isEmpty) return null;

      // 优先使用隐藏WebView JS解析
      try {
        final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
        if (webSvc != null) {
          final url = await webSvc.resolveMusicUrl(
            platform: platform,
            songId: id,
            quality: '320k',
          );
          if (url != null && url.isNotEmpty) return url;
        }
      } catch (_) {}

      // 回退到内置 LocalJS 解析
      try {
        final jsSvc = await ref.read(jsSourceServiceProvider.future);
        if (jsSvc != null && jsSvc.isReady) {
          final js = """
            (function(){
              try{
                if (!lx || !lx.EVENT_NAMES) return '';
                function mapPlat(p){ p=(p||'').toLowerCase(); if(p==='qq'||p==='tencent') return 'tx'; if(p==='netease'||p==='163') return 'wy'; if(p==='kuwo') return 'kw'; if(p==='kugou') return 'kg'; if(p==='migu') return 'mg'; return p; }
                var payload = { action: 'musicUrl', source: mapPlat('$platform'), info: { type: '320k', musicInfo: { songmid: '$id', hash: '$id' } } };
                var res = lx.emit(lx.EVENT_NAMES.request, payload);
                if (res && typeof res.then === 'function') return '';
                if (typeof res === 'string') return res;
                if (res && res.url) return res.url;
                return '';
              }catch(e){ return '' }
            })()
          """;
          final url = jsSvc.evaluateToString(js);
          if (url.isNotEmpty) return url;
        }
      } catch (_) {}

      // 最后回退到统一API解析
      try {
        final unifiedService = ref.read(unifiedApiServiceProvider);
        final url = await unifiedService.getMusicUrl(
          songId: id,
          platform: platform,
          quality: '320k',
        );
        if (url != null && url.isNotEmpty) return url;
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _playViaResolver(OnlineMusicResult item) async {
    final platform = (item.platform ?? 'qq');
    final id = item.songId ?? '';

    if (id.isEmpty) {
      if (mounted) {
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text('❌ 缺少歌曲标识，无法播放'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      String? playUrl;
      // 保留设置读取逻辑如后续需要；当前未使用，移除避免未使用告警

      // 🎯 检查歌曲来源，使用对应的播放源
      final sourceApi = item.extra?['sourceApi'] as String?;
      print('[XMC] 🎵 [Play] 开始解析播放链接，来源: $sourceApi, 平台: $platform, ID: $id');

      if (sourceApi == 'js_builtin') {
        // 🎯 线路0（组合模式）：优先使用 WebView JS 解析 → 回退内置JS
        print('[XMC] 🎵 [Play] 线路0：优先使用WebView JS解析播放链接...');
        try {
          final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
          if (webSvc != null) {
            final resolved = await webSvc.resolveMusicUrl(
              platform: platform,
              songId: id,
              quality: '320k',
            );
            if (resolved != null && resolved.isNotEmpty) {
              playUrl = resolved;
              print('[XMC] ✅ [Play] WebView JS解析成功: $playUrl');
            }
          }
        } catch (e) {
          print('[XMC] ⚠️ [Play] WebView JS解析异常: $e');
        }

        if (playUrl == null || playUrl.isEmpty) {
          print('[XMC] 🎵 [Play] 回退到内置JS脚本解析播放链接...');
          final jsSvc = await ref.read(jsSourceServiceProvider.future);
          if (jsSvc == null || !jsSvc.isReady) {
            throw Exception('内置JS脚本服务未就绪');
          }
          final js = """
            (function(){
              try{
                if (!lx || !lx.EVENT_NAMES) return '';
                var payload = { action: 'musicUrl', source: 'tx', info: { type: '320k', musicInfo: { songmid: '$id', hash: '$id' } } };
                var res = lx.emit(lx.EVENT_NAMES.request, payload);
                if (res && typeof res.then === 'function') return '';
                if (typeof res === 'string') return res;
                if (res && res.url) return res.url;
                return '';
              }catch(e){ console.log('内置脚本解析错误:', e); return ''; }
            })()
          """;
          playUrl = jsSvc.evaluateToString(js);
          if (playUrl.isNotEmpty) {
            print('[XMC] ✅ [Play] 内置JS脚本解析成功: $playUrl');
          } else {
            print('[XMC] ❌ [Play] 内置JS脚本解析失败');
            throw Exception('内置JS脚本无法解析播放链接，请检查歌曲是否可用');
          }
        }
      } else if (sourceApi == 'unified') {
        // 🎯 线路1：统一API搜索的歌曲，使用统一API播放
        print('[XMC] 🎵 [Play] 线路1：使用统一API解析播放链接...');
        final unifiedService = ref.read(unifiedApiServiceProvider);

        playUrl = await unifiedService.getMusicUrl(
          songId: id,
          platform: platform,
          quality: '320k',
        );

        if (playUrl != null && playUrl.isNotEmpty) {
          print('[XMC] ✅ [Play] 统一API解析成功: $playUrl');
        } else {
          print('[XMC] ❌ [Play] 统一API解析失败，尝试备用方案');
          // 🎯 备用方案：尝试使用JS源解析
          try {
            final webSvc = await ref.read(
              webviewJsSourceServiceProvider.future,
            );
            if (webSvc != null) {
              print('[XMC] 🔄 [Play] 尝试JS源备用解析...');
              playUrl = await webSvc.resolveMusicUrl(
                platform: platform,
                songId: id,
              );
              if (playUrl != null && playUrl.isNotEmpty) {
                print('[XMC] ✅ [Play] JS源备用解析成功: $playUrl');
              }
            }
          } catch (e) {
            print('[XMC] ⚠️ [Play] JS源备用解析失败: $e');
          }
        }
      } else if (sourceApi == 'youtube_proxy') {
        // 🎯 线路0：已移除YouTube代理，直接跳过到JS源
        print('[XMC] 🎵 [Play] 线路0：YouTube代理已禁用，改用JS源');
        // 不做任何操作，后续走JS源解析
      } else {
        // 🎯 线路2：JS源搜索的歌曲，使用JS源播放
        print('[XMC] 🎵 [Play] 线路2：使用JS源解析播放链接...');
        final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
        final jsSvc = await ref.read(jsSourceServiceProvider.future);

        if (webSvc == null && jsSvc == null) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('JS解析服务未就绪'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (webSvc != null) {
          playUrl = await webSvc.resolveMusicUrl(
            platform: platform,
            songId: id,
          );
        }
        if ((playUrl == null || playUrl.isEmpty) && jsSvc != null) {
          // 走本地 JS 的回退：构造一段 eval 取 URL
          final js = """
        (function(){
          try{
            if (!lx || !lx.EVENT_NAMES) return '';
            // 平台映射
            function mapPlat(p){ p=(p||'').toLowerCase(); if(p==='qq'||p==='tencent') return 'tx'; if(p==='netease'||p==='163') return 'wy'; if(p==='kuwo') return 'kw'; if(p==='kugou') return 'kg'; if(p==='migu') return 'mg'; return p; }
            var payload = { action: 'musicUrl', source: mapPlat('$platform'), info: { type: '320k', musicInfo: { songmid: '$id', hash: '$id' } } };
            var res = lx.emit(lx.EVENT_NAMES.request, payload);
            if (res && typeof res.then === 'function') return '';
            if (typeof res === 'string') return res; if (res && res.url) return res.url; return '';
          }catch(e){ return '' }
        })()
      """;
          final r = jsSvc.isReady ? jsSvc.evaluateToString(js) : '';
          playUrl = r;
        }
      } // 结束线路2：JS源

      if (playUrl == null || playUrl.isEmpty) {
        throw Exception('所有播放源都无法解析播放链接，请检查网络连接或尝试其他歌曲');
      }

      // 🎯 新增：检查是否有可用的播放设备
      final deviceState = ref.read(deviceProvider);
      if (deviceState.devices.isEmpty) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('未找到可用设备，请先在控制页检查设备连接'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 🎯 新增：如果没有选择设备，提示用户选择
      if (deviceState.selectedDeviceId == null) {
        if (mounted) {
          final shouldSelectDevice = await _showDeviceSelectionDialog(
            deviceState.devices,
          );
          if (!shouldSelectDevice) return; // 用户取消选择
        }
      }

      final selectedDeviceId = deviceState.selectedDeviceId;
      if (selectedDeviceId == null) {
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('请先选择播放设备'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 🎯 新增：通过playurl接口直接播放音乐
      print('[XMC] 🎵 [Play] 开始直接播放: $playUrl, 设备: $selectedDeviceId');
      print('[XMC] 🎵 [Play] 播放URL长度: ${playUrl.length}');
      print(
        '🎵 [Play] 播放URL前缀: ${playUrl.startsWith('http') ? 'HTTP链接' : '非HTTP链接'}',
      );

      final apiService = ref.read(apiServiceProvider);
      if (apiService != null) {
        try {
          // 🎯 先显示播放中的提示
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('🎵 正在播放: ${item.title}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }

          print('[XMC] 🎵 [Play] 准备调用 playUrl 接口...');
          print(
            '🎵 [Play] 接口参数: did=$selectedDeviceId, url=${playUrl.substring(0, playUrl.length > 100 ? 100 : playUrl.length)}...',
          );

          // 🎯 调用播放接口
          await apiService.playUrl(did: selectedDeviceId, url: playUrl);

          print('[XMC] ✅ [Play] 直接播放请求成功');

          // 🎯 播放成功后，先停止当前播放，然后等待设备开始播放新歌曲
          try {
            print('[XMC] ⏹️ [Play] 先停止当前播放...');
            try {
              await apiService.executeCommand(
                did: selectedDeviceId,
                command: '停止',
              );
              print('[XMC] ✅ [Play] 停止命令发送成功');
            } catch (e) {
              print('[XMC] ⚠️ [Play] 停止命令失败: $e');
            }

            print('[XMC] ⏳ [Play] 等待设备开始播放新歌曲...');
            await Future.delayed(const Duration(seconds: 3));

            print('[XMC] 🔄 [Play] 开始刷新播放状态...');
            await ref
                .read(playbackProvider.notifier)
                .refreshStatus(silent: true);
            print('[XMC] ✅ [Play] 播放状态刷新成功');

            // 🎯 验证播放状态
            final playbackState = ref.read(playbackProvider);
            if (playbackState.currentMusic != null) {
              print(
                '🎵 [Play] 当前播放状态: ${playbackState.currentMusic!.curMusic}',
              );
              print(
                '🎵 [Play] 是否正在播放: ${playbackState.currentMusic!.isPlaying}',
              );

              // 如果播放状态不正确，再次尝试刷新
              if (!playbackState.currentMusic!.isPlaying) {
                print('[XMC] ⚠️ [Play] 播放状态不正确，再次尝试刷新...');
                await Future.delayed(const Duration(seconds: 2));
                await ref
                    .read(playbackProvider.notifier)
                    .refreshStatus(silent: true);

                // 再次检查播放状态
                final updatedPlaybackState = ref.read(playbackProvider);
                if (updatedPlaybackState.currentMusic != null) {
                  print(
                    '🎵 [Play] 更新后的播放状态: ${updatedPlaybackState.currentMusic!.curMusic}',
                  );
                  print(
                    '🎵 [Play] 更新后是否正在播放: ${updatedPlaybackState.currentMusic!.isPlaying}',
                  );
                }

                // 🎯 如果播放状态仍然不正确，尝试强制播放
                if (updatedPlaybackState.currentMusic == null ||
                    !updatedPlaybackState.currentMusic!.isPlaying ||
                    !updatedPlaybackState.currentMusic!.curMusic.contains(
                      item.title,
                    )) {
                  print('[XMC] ⚠️ [Play] 播放状态仍然不正确，尝试强制播放...');
                  try {
                    // 尝试使用播放列表的方式播放
                    await apiService.playMusicList(
                      deviceId: selectedDeviceId,
                      playlistName: '临时搜索列表',
                      musicName: item.title,
                    );
                    print('[XMC] ✅ [Play] 强制播放命令发送成功');

                    // 等待强制播放生效
                    await Future.delayed(const Duration(seconds: 2));
                    await ref
                        .read(playbackProvider.notifier)
                        .refreshStatus(silent: true);

                    final finalPlaybackState = ref.read(playbackProvider);
                    if (finalPlaybackState.currentMusic != null) {
                      print(
                        '🎵 [Play] 最终播放状态: ${finalPlaybackState.currentMusic!.curMusic}',
                      );
                      print(
                        '🎵 [Play] 最终是否正在播放: ${finalPlaybackState.currentMusic!.isPlaying}',
                      );
                    }
                  } catch (e) {
                    print('[XMC] ❌ [Play] 强制播放失败: $e');
                  }
                }
              }
            }
          } catch (e) {
            print('[XMC] ⚠️ [Play] 播放状态刷新失败: $e');
          }

          // 🎯 播放成功后，自动下载到音乐库（不再询问）
          if (mounted) {
            print('[XMC] 📥 [Play] 自动下载到音乐库...');
            final downloadResult = await _showDownloadWithQualitySelection(
              item.title,
              item,
            );
            if (downloadResult != null &&
                downloadResult['shouldDownload'] == true) {
              final selectedQuality = downloadResult['quality'] as String;
              print('[XMC] 📥 [Play] 自动选择音质: $selectedQuality');

              // 根据选择的音质重新获取播放链接
              final qualityUrl = await _getPlayUrlWithQuality(
                item,
                selectedQuality,
              );
              final downloadUrl = qualityUrl ?? playUrl;

              // 使用"歌曲名 - 作者名"格式作为文件名
              final safeTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
              final safeAuthor = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
              final fileName = safeAuthor.isNotEmpty ? '$safeTitle - $safeAuthor' : safeTitle;

              await ref
                  .read(musicLibraryProvider.notifier)
                  .downloadOneMusic(fileName, url: downloadUrl);

              if (mounted) {
                AppSnackBar.show(
                  context,
                  SnackBar(
                    content: Text('已添加到音乐库: $fileName ($selectedQuality)'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            } else {
              print('[XMC] ❌ [Play] 自动下载失败');
            }
          }

          print('[XMC] ✅ [Play] 播放流程完成，返回');
          return; // 直接播放成功，不需要再走下载逻辑
        } catch (e) {
          print('[XMC] ❌ [Play] 直接播放失败: $e');
          print('[XMC] ❌ [Play] 错误类型: ${e.runtimeType}');
          print('[XMC] ❌ [Play] 错误详情: $e');

          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('直接播放失败，尝试下载到音乐库: $e'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          // 直接播放失败，回退到原来的下载逻辑
        }
      } else {
        print('[XMC] ❌ [Play] API服务未初始化，无法直接播放');
        if (mounted) {
          AppSnackBar.show(
            context,
            const SnackBar(
              content: Text('❌ API服务未初始化，请先登录'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 🎯 原有的下载逻辑作为回退方案
      // 使用"歌曲名 - 作者名"格式
      final safeTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeAuthor = item.author.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fallbackFileName = safeAuthor.isNotEmpty ? '$safeTitle - $safeAuthor' : safeTitle;
      
      await ref
          .read(musicLibraryProvider.notifier)
          .downloadOneMusic(fallbackFileName, url: playUrl);
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('已提交播放/下载：$fallbackFileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[XMC] ❌ [Play] 播放失败: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('❌ 播放失败：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // 🎯 新增：显示设备选择对话框
  Future<bool> _showDeviceSelectionDialog(List<Device> devices) async {
    if (devices.isEmpty) return false;

    final selectedDeviceId = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '选择播放设备',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  devices.map((device) {
                    final isOnline = device.isOnline ?? false;
                    return ListTile(
                      leading: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        device.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        isOnline ? '在线' : '离线',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(device.id),
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
    );

    if (selectedDeviceId != null) {
      ref.read(deviceProvider.notifier).selectDevice(selectedDeviceId);
      return true;
    }

    return false;
  }

  // 🎯 新增：显示下载确认对话框

  Future<Map<String, dynamic>?> _showDownloadWithQualitySelection(
    String musicTitle,
    OnlineMusicResult item,
  ) async {
    // 自动选择最佳音质进行下载，不显示选择对话框
    final autoSelectedQuality = await _selectBestQuality(item);
    
    if (autoSelectedQuality != null) {
      return {
        'shouldDownload': true,
        'quality': autoSelectedQuality,
        'item': item,
      };
    }
    
    // 如果所有音质都无法获取，返回null
    return null;
  }

  /// 自动选择最佳可用音质（320k -> 128k -> flac -> flac24bit）
  Future<String?> _selectBestQuality(OnlineMusicResult item) async {
    // 音质优先级：320k > 128k > flac > flac24bit
    const qualityPriority = ['320k', '128k', 'flac', 'flac24bit'];
    
    for (final quality in qualityPriority) {
      debugPrint('尝试获取音质: $quality');
      try {
        final url = await _getPlayUrlWithQuality(item, quality);
        if (url != null && url.isNotEmpty) {
          debugPrint('✅ 成功获取 $quality 音质链接');
          return quality;
        }
      } catch (e) {
        debugPrint('❌ $quality 音质获取失败: $e');
      }
    }
    
    debugPrint('❌ 所有音质都无法获取，使用默认320k');
    return '320k'; // 回退到默认320k
  }

  /// 根据指定音质获取播放链接
  Future<String?> _getPlayUrlWithQuality(
    OnlineMusicResult item,
    String quality,
  ) async {
    try {
      print('[XMC] 🎵 [QualityDownload] 获取 ${item.title} 的 $quality 音质链接...');

      final webSvc = await ref.read(webviewJsSourceServiceProvider.future);
      if (webSvc == null) {
        throw Exception('WebView服务未就绪');
      }

      // 通过WebView JS源获取指定音质的播放链接
      final directUrl = await webSvc.resolveMusicUrl(
        platform: item.platform == 'auto' ? 'tx' : (item.platform ?? 'tx'),
        songId: item.songId ?? '',
        quality: quality,
      );

      if (directUrl != null && directUrl.isNotEmpty) {
        print('[XMC] ✅ [QualityDownload] 获取 $quality 音质链接成功');
        return directUrl;
      }

      throw Exception('获取音质链接失败');
    } catch (e) {
      print('[XMC] ❌ [QualityDownload] 获取 $quality 音质链接失败: $e');
      // 如果指定音质获取失败，返回null（使用原有链接）
      return null;
    }
  }
}
