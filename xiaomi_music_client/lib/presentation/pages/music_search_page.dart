import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/music_search_provider.dart';
import '../../data/models/online_music_result.dart';
import 'package:dio/dio.dart' as dio;
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/js_source_provider.dart';
import '../providers/source_settings_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import '../providers/music_library_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_layout.dart';
import '../providers/device_provider.dart';
import '../providers/dio_provider.dart';
import '../../data/models/device.dart';

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
  void _showQualityTip(String message, {bool isError = false}) {
    if (!mounted) return;

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.audiotrack,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
        ],
      ),
      backgroundColor: isError ? Colors.red.shade600 : Colors.blue.shade600,
      duration: Duration(seconds: isError ? 4 : 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

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
    return Center(
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
            style: TextStyle(fontSize: 16, color: onSurface.withOpacity(0.6)),
          ),
        ],
      ),
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
    return ListView.separated(
      key: const ValueKey('online_search_results'),
      padding: EdgeInsets.only(
        bottom: AppLayout.contentBottomPadding(context),
        top: 12,
      ),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
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
    );
  }

  Future<void> _downloadToServer(OnlineMusicResult item) async {
    try {
      await ref
          .read(musicLibraryProvider.notifier)
          .downloadOneMusic(item.title, url: item.url);
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
      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final safeName = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = p.extension(Uri.parse(item.url).path);
      final filePath = p.join(
        dir.path,
        '$safeName${ext.isEmpty ? '.m4a' : ext}',
      );

      final client = dio.Dio();
      await client.download(
        item.url,
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

  Future<void> _playViaResolver(OnlineMusicResult item) async {
    final platform = (item.platform ?? 'qq');
    final id = item.songId ?? '';

    if (id.isEmpty) throw Exception('缺少歌曲标识');

    try {
      String? playUrl;

      // 🎯 检查歌曲来源，使用对应的播放源
      final sourceApi = item.extra?['sourceApi'] as String?;

      if (sourceApi == 'unified') {
        // 🎯 线路1：统一API搜索的歌曲，使用统一API播放
        print('🎵 [Play] 线路1：使用统一API解析播放链接...');
        final unifiedService = ref.read(unifiedApiServiceProvider);
        playUrl = await unifiedService.getMusicUrl(
          songId: id,
          platform: platform,
          quality: '320k',
        );

        if (playUrl != null && playUrl.isNotEmpty) {
          print('✅ [Play] 统一API解析成功: $playUrl');
        } else {
          print('❌ [Play] 统一API解析失败');
        }
      } else if (sourceApi == 'youtube_proxy') {
        // 🎯 线路0：YouTube代理搜索的歌曲，使用YouTube代理播放
        print('🎵 [Play] 线路0：使用YouTube代理解析播放链接...');
        final youtubeService = ref.read(youtubeProxyServiceProvider);
        final settings = ref.read(sourceSettingsProvider);

        playUrl = await youtubeService.getMusicUrl(
          videoId: id,
          quality: settings.youTubeAudioQuality,
          preferredSource: settings.youTubeDownloadSource,
        );

        if (playUrl != null && playUrl.isNotEmpty) {
          print('✅ [Play] YouTube代理解析成功: $playUrl');

          // 检查日志以确定实际使用的音质，并给用户提示
          // 注：实际实现中可以通过回调或返回值获取使用的音质信息
          if (!mounted) return;

          // 如果用户选择了高音质，提供一个通用提示
          if (settings.youTubeAudioQuality == '320k') {
            _showQualityTip(
              '正在播放YouTube音频 (${settings.youTubeAudioQuality})，如遇问题可尝试降低音质',
            );
          } else if (settings.youTubeAudioQuality == '64k') {
            _showQualityTip('正在播放YouTube音频 (节省流量模式)');
          } else {
            _showQualityTip('正在播放YouTube音频 (${settings.youTubeAudioQuality})');
          }
        } else {
          print('❌ [Play] YouTube代理解析失败');

          if (!mounted) return;
          _showQualityTip('YouTube音频获取失败，请检查网络连接或尝试其他下载源', isError: true);
        }
      } else {
        // 🎯 线路2：JS源搜索的歌曲，使用JS源播放
        print('🎵 [Play] 线路2：使用JS源解析播放链接...');
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

      if (playUrl == null || playUrl.isEmpty) throw Exception('解析失败');

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
          final shouldSelectDevice = await _showDeviceSelectionDialog(deviceState.devices);
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
      print('🎵 [Play] 开始直接播放: $playUrl, 设备: $selectedDeviceId');
      final apiService = ref.read(apiServiceProvider);
      if (apiService != null) {
        try {
          await apiService.playUrl(
            did: selectedDeviceId,
            url: playUrl,
          );
          
          print('✅ [Play] 直接播放请求成功');
          
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('正在播放: ${item.title}'),
                backgroundColor: Colors.green,
              ),
            );
          }
          
          // 🎯 新增：播放成功后，可以选择是否下载到音乐库
          if (mounted) {
            final shouldDownload = await _showDownloadConfirmation(item.title);
            if (shouldDownload) {
              await ref
                  .read(musicLibraryProvider.notifier)
                  .downloadOneMusic(item.title, url: playUrl);
              
              if (mounted) {
                AppSnackBar.show(
                  context,
                  SnackBar(
                    content: Text('已添加到音乐库: ${item.title}'),
                    backgroundColor: Colors.blue,
                  ),
                );
              }
            }
          }
          
          return; // 直接播放成功，不需要再走下载逻辑
        } catch (e) {
          print('❌ [Play] 直接播放失败: $e');
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
      }

      // 🎯 原有的下载逻辑作为回退方案
      await ref
          .read(musicLibraryProvider.notifier)
          .downloadOneMusic(item.title, url: playUrl);
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('已提交播放/下载：${item.title}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('解析失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🎯 新增：显示设备选择对话框
  Future<bool> _showDeviceSelectionDialog(List<Device> devices) async {
    if (devices.isEmpty) return false;
    
    final selectedDeviceId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
          children: devices.map((device) {
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
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
  Future<bool> _showDownloadConfirmation(String musicTitle) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '添加到音乐库',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '是否将 "$musicTitle" 添加到音乐库？',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '添加',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }
}
