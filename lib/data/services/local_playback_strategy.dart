import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playing_music.dart';
import '../models/music.dart';
import 'music_api_service.dart';
import 'audio_proxy_server.dart';
import 'music_cdn_url_policy.dart';
import 'playback_strategy.dart';
import 'audio_handler_service.dart';

/// 本地播放策略实现
/// 使用 just_audio 在手机本地播放音乐
class LocalPlaybackStrategy implements PlaybackStrategy {
  @override
  String? get lastAudioId => null;

  static AudioHandlerService? _sharedAudioHandler;
  static AudioPlayer? _sharedAudioPlayer; // 🔧 添加静态共享 AudioPlayer
  static final Completer<void> _handlerReadyCompleter = Completer<void>();
  static Future<void> get handlerReady async => _handlerReadyCompleter.future;

  static set sharedAudioHandler(AudioHandlerService? handler) {
    debugPrint('🔧 [LocalPlayback] 设置 sharedAudioHandler: ${handler != null ? "成功" : "null"}');
    _sharedAudioHandler = handler;
    if (handler != null) {
      _sharedAudioPlayer = handler.player; // 🔧 同时获取 AudioPlayer
      debugPrint('🔧 [LocalPlayback] AudioPlayer 已获取: ${_sharedAudioPlayer != null}');
      if (!_handlerReadyCompleter.isCompleted) {
        _handlerReadyCompleter.complete();
        debugPrint('🔧 [LocalPlayback] handlerReady Completer 已完成');
      }
    }
  }

  Future<void> _waitAndAttachAudioHandler() async {
    if (_audioHandler != null && _player != null) return;
    try {
      debugPrint('⏳ [LocalPlayback] 等待 AudioHandler 就绪...');
      await handlerReady.timeout(const Duration(seconds: 5));
      if (_sharedAudioHandler != null && _sharedAudioPlayer != null) {
        _audioHandler = _sharedAudioHandler;
        _player = _sharedAudioPlayer!;
        debugPrint('✅ [LocalPlayback] AudioHandler 已就绪并绑定');
      } else {
        debugPrint('❌ [LocalPlayback] AudioHandler 仍未就绪');
      }
    } on TimeoutException {
      debugPrint('❌ [LocalPlayback] 等待 AudioHandler 超时');
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 等待 AudioHandler 失败: $e');
    }
  }

  static AudioHandlerService? get sharedAudioHandler => _sharedAudioHandler;
  final MusicApiService? _apiService; // 🎯 改为可选参数,支持完全独立模式
  final AudioProxyServer? _audioProxyServer; // 🎯 本地代理服务器（解决 iOS ATS HTTP 限制）
  AudioPlayer? _player; // 🔧 改为可空，从共享的静态变量获取
  AudioHandlerService? _audioHandler;
  int _loadToken = 0;
  bool _loading = false;

  // SharedPreferences 缓存 key（与 PlaybackProvider 保持一致）
  static const String _cacheKeyUrl = 'local_playback_url';
  static const String _cacheKeyName = 'local_playback_current_name';
  static const String _cacheKeyVolume = 'local_playback_volume'; // 🔊 音量缓存key

  // 播放列表
  List<Music> _playlist = [];
  int _currentIndex = 0;
  String? _currentMusicName;
  String? _currentMusicUrl;
  String? _currentAlbumCover; // 当前封面图
  String? _loadingMusicName; // 正在加载的歌曲名

  String? get currentMusicName => _currentMusicName;
  String? get currentMusicUrl => _currentMusicUrl;

  // 状态流控制器
  final _statusController = StreamController<PlayingMusic>.broadcast();

  // 上一首/下一首回调
  Function()? onNext;
  Function()? onPrevious;

  LocalPlaybackStrategy({MusicApiService? apiService, AudioProxyServer? audioProxyServer})
    : _apiService = apiService,
      _audioProxyServer = audioProxyServer {
    _initAudioSession();

    // 🔧 先尝试立即绑定(如果 AudioHandler 已就绪)
    _attachAudioHandlerIfAvailable();

    if (_audioHandler != null && _sharedAudioPlayer != null) {
      // 如果已经绑定成功,立即初始化
      debugPrint('✅ [LocalPlayback] AudioPlayer 已就绪，立即初始化');
      _clearRemoteCallbacks(); // 🔧 清除远程播放的回调
      _initPlayer();
      _loadCache();
    } else {
      // 否则等待 AudioHandler 就绪
      debugPrint('⏳ [LocalPlayback] 等待 AudioHandler 就绪...');
      _waitAndAttachAudioHandler().then((_) {
        if (_audioHandler != null && _sharedAudioPlayer != null) {
          debugPrint('✅ [LocalPlayback] AudioHandler 就绪，初始化播放器');
          _player = _sharedAudioPlayer!;
          _clearRemoteCallbacks(); // 🔧 清除远程播放的回调
          _initPlayer();
          _loadCache();
        } else {
          debugPrint('❌ [LocalPlayback] AudioHandler 未就绪，初始化失败');
        }
      });
    }
  }

  /// 🔧 清除远程播放设置的回调,确保本地播放不会调用远程播放
  void _clearRemoteCallbacks() {
    if (_audioHandler != null) {
      _audioHandler!.onPlay = null;
      _audioHandler!.onPause = null;
      // 🔧 重新启用本地播放器监听
      _audioHandler!.setListenToLocalPlayer(true);
      debugPrint('🔧 [LocalPlayback] 已清除远程播放回调,本地播放将使用 AudioPlayer');
    }
  }

  /// 初始化 AudioSession（配置音频焦点）
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      debugPrint('✅ [LocalPlayback] AudioSession 初始化成功');
    } catch (e) {
      debugPrint('❌ [LocalPlayback] AudioSession 初始化失败: $e');
    }
  }

  void _attachAudioHandlerIfAvailable() {
    if (_sharedAudioHandler != null && _sharedAudioPlayer != null) {
      _audioHandler = _sharedAudioHandler;
      _player = _sharedAudioPlayer!;
      debugPrint('✅ [LocalPlayback] 已绑定全局 AudioService 并获取共享 AudioPlayer');
    }
  }

  void _initPlayer() {
    if (_player == null) {
      debugPrint('❌ [LocalPlayback] _player 为 null，无法初始化');
      return;
    }

    // 🔧 连接 AudioHandler 的回调
    if (_audioHandler != null) {
      _audioHandler!.onNext = () {
        debugPrint('🎵 [LocalPlayback] 通知栏触发下一首');
        next();
      };
      _audioHandler!.onPrevious = () {
        debugPrint('🎵 [LocalPlayback] 通知栏触发上一首');
        previous();
      };
      _audioHandler!.onSeek = (position) {
        debugPrint('🎵 [LocalPlayback] 通知栏跳转: ${position.inSeconds}s');
        // seek 已经在 AudioHandler 中直接调用 player.seek 了,这里只需要更新状态
        _emitCurrentStatus();
      };
    }

    // 监听播放状态变化
    _player!.playerStateStream.listen((state) {
      debugPrint(
        '🎵 [LocalPlayback] 播放器状态变化: playing=${state.playing}, processingState=${state.processingState}',
      );

      // 状态变化时立即更新UI
      _emitCurrentStatus();

      // 自动播放下一首
      if (state.processingState == ProcessingState.completed) {
        debugPrint('🎵 [LocalPlayback] 当前歌曲播放完成，尝试播放下一首');
        next();
      }
    });

    // 监听位置变化（用于更新进度）
    int lastEmittedSecond = -1;
    _player!.positionStream.listen((position) {
      final currentSecond = position.inSeconds;
      // 每秒更新一次状态，避免重复更新
      if (currentSecond != lastEmittedSecond) {
        lastEmittedSecond = currentSecond;
        _emitCurrentStatus();
      }
    });
  }

  @override
  bool get isLocalMode => true;

  // 🔧 辅助方法：确保 player 已初始化
  AudioPlayer? get _ensurePlayer {
    if (_player == null && _sharedAudioPlayer != null) {
      _player = _sharedAudioPlayer;
    }
    return _player;
  }

  @override
  Future<void> play() async {
    await _waitAndAttachAudioHandler();
    if (_currentMusicUrl == null || _currentMusicUrl!.isEmpty) {
      await _loadCache();
    }
    if (_currentMusicUrl == null || _currentMusicUrl!.isEmpty) return;

    final player = _ensurePlayer;
    if (player == null) {
      debugPrint('❌ [LocalPlayback] AudioPlayer 未初始化');
      return;
    }

    // 🔧 修复: 如果播放器没有加载任何音频,先加载
    if (player.processingState == ProcessingState.idle) {
      debugPrint('🔧 [LocalPlayback] 播放器空闲,先加载音频: $_currentMusicUrl');
      try {
        await _loadAndMaybePlay(
          url: _currentMusicUrl!,
          name: _currentMusicName,
          autoPlay: true,
        );
        return;
      } catch (e) {
        debugPrint('❌ [LocalPlayback] 加载音频失败: $e');
        return;
      }
    }

    // 🔧 调用 AudioHandler 的 play() 方法,而不是直接调用 _player.play()
    if (_audioHandler != null) {
      await _audioHandler!.play();
    } else if (_ensurePlayer != null) {
      await _ensurePlayer!.play();
    }
    _emitCurrentStatus();
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [LocalPlayback] 执行暂停');
    // 🔧 调用 AudioHandler 的 pause() 方法,而不是直接调用 _player.pause()
    if (_audioHandler != null) {
      await _audioHandler!.pause();
    } else if (_ensurePlayer != null) {
      await _ensurePlayer!.pause();
    }
    _emitCurrentStatus();
  }

  @override
  Future<void> next() async {
    debugPrint('🎵 [LocalPlayback] 播放下一首');
    if (_playlist.isEmpty) {
      debugPrint('⚠️ [LocalPlayback] 播放列表为空');
      return;
    }

    _currentIndex = (_currentIndex + 1) % _playlist.length;
    final nextMusic = _playlist[_currentIndex];
    await playMusic(musicName: nextMusic.name);
  }

  @override
  Future<void> previous() async {
    debugPrint('🎵 [LocalPlayback] 播放上一首');
    if (_playlist.isEmpty) {
      debugPrint('⚠️ [LocalPlayback] 播放列表为空');
      return;
    }

    _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    final prevMusic = _playlist[_currentIndex];
    await playMusic(musicName: prevMusic.name);
  }

  @override
  Future<void> seekTo(int seconds) async {
    debugPrint('🎵 [LocalPlayback] ========== seekTo 被调用 ==========');
    debugPrint('🎵 [LocalPlayback] 目标位置: $seconds 秒');
    final player = _ensurePlayer;
    debugPrint('🎵 [LocalPlayback] player 状态: ${player != null ? "已初始化" : "未初始化"}');
    if (player != null) {
      debugPrint('🎵 [LocalPlayback] 当前位置: ${player.position.inSeconds} 秒');
      debugPrint('🎵 [LocalPlayback] 总时长: ${player.duration?.inSeconds ?? 0} 秒');
      await player.seek(Duration(seconds: seconds));
      debugPrint('🎵 [LocalPlayback] seek 完成，新位置: ${player.position.inSeconds} 秒');
      _emitCurrentStatus();
      debugPrint('🎵 [LocalPlayback] 状态已更新');
    } else {
      debugPrint('❌ [LocalPlayback] player 为 null，无法执行 seek');
    }
  }

  @override
  Future<void> setVolume(int volume) async {
    debugPrint('🎵 [LocalPlayback] 设置音量: $volume');
    final player = _ensurePlayer;
    if (player != null) {
      // 音量范围 0-100 转换为 0.0-1.0
      final normalizedVolume = volume / 100.0;
      await player.setVolume(normalizedVolume.clamp(0.0, 1.0));

      // 🔊 保存音量到缓存
      await _saveVolume(volume);
    }
  }

  @override
  Future<void> playMusic({
    required String musicName,
    String? url,
    String? platform,
    String? songId,
    int? duration,
    int? switchSessionId,
  }) async {
    try {
      debugPrint('🎵 [LocalPlayback] 播放音乐: $musicName');
      debugPrint('🎵 [LocalPlayback] URL: $url');

      String playUrl = url ?? '';
      if (playUrl.isEmpty) {
        // 🎯 如果没有传入 URL,尝试从 xiaomusic 服务器获取(如果配置了的话)
        if (_apiService != null) {
          debugPrint('🎵 [LocalPlayback] 从 xiaomusic 服务器获取音乐链接: $musicName');
          final musicInfo = await _apiService!.getMusicInfo(musicName);
          playUrl = musicInfo['url']?.toString() ?? '';
          if (playUrl.isEmpty) {
            throw Exception('无法从服务器获取音乐播放链接');
          }
          debugPrint('🎵 [LocalPlayback] 获取到播放链接: $playUrl');
        } else {
          // 🎯 完全独立模式:没有 apiService,必须传入 URL
          throw Exception('播放失败:未传入音乐URL,且未配置 xiaomusic 服务器');
        }
      }

      // 🔧 将内网地址替换为登录时的域名(仅对服务器本地音乐,且配置了 apiService 时)
      // 判断是否需要替换: 如果URL不是http/https开头或包含内网IP,才需要替换
      if (_apiService != null && _shouldReplaceWithLoginDomain(playUrl)) {
        playUrl = _replaceWithLoginDomain(playUrl);
        debugPrint('🔄 [LocalPlayback] URL已替换为登录域名');
      } else {
        debugPrint('🌐 [LocalPlayback] 在线音乐URL或完全独立模式,保持原样');
      }

      // 🎯 iOS ATS 修复：规避 iOS ATS 对公网 HTTP URL 的拦截
      // iOS 26+ 即使设置了 NSAllowsArbitraryLoads，AVPlayer 仍会拒绝公网 HTTP URL
      // 策略：网易云/QQ CDN 均支持 HTTPS，直接升级协议；其他 CDN 走本地代理
      final proxyServer = _audioProxyServer;
      if (Platform.isIOS &&
          playUrl.startsWith('http://') &&
          !playUrl.startsWith('http://127.0.0.1') &&
          !playUrl.startsWith('http://localhost')) {
        if (MusicCdnUrlPolicy.isNeteaseCdn(playUrl) || MusicCdnUrlPolicy.isQqCdn(playUrl)) {
          // 网易云 / QQ CDN 均支持 HTTPS，直接升级协议，无需走代理
          // 好处：iOS 本地 just_audio 可直接发 Range 请求，进度条/seek 正常工作
          playUrl = 'https${playUrl.substring(4)}';
          debugPrint('🔀 [LocalPlayback] iOS ATS: HTTP→HTTPS 直接升级');
        } else if (proxyServer != null && proxyServer.isRunning) {
          // 其他 CDN（酷我等）走本地代理
          playUrl = proxyServer.getProxyUrl(playUrl);
          debugPrint('🔀 [LocalPlayback] iOS ATS: HTTP URL 已通过本地代理转发');
        }
      }

      debugPrint('✅ [LocalPlayback] 最终播放链接: $playUrl');

      // 先更新状态和缓存
      _currentMusicName = musicName;
      _currentMusicUrl = playUrl;
      await _saveCache();

      // 然后调用播放
      await _loadAndMaybePlay(
        url: playUrl,
        name: musicName,
        autoPlay: true,
        artist: platform ?? '未知艺术家',
      );
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 播放失败: $e');
      rethrow;
    }
  }

  /// 更新媒体通知信息
  Future<void> _updateMediaNotification({
    required String title,
    String? artist,
    String? album,
  }) async {
    if (_audioHandler == null) return;

    final player = _ensurePlayer;
    await _audioHandler!.setMediaItem(
      title: title,
      artist: '本机播放', // 🔧 固定显示"本机播放"
      album: album ?? '本地播放',
      artUri: _currentAlbumCover,
      duration: player?.duration,
    );
  }

  /// 设置封面图（由 PlaybackProvider 调用）
  void setAlbumCover(String? coverUrl) {
    _currentAlbumCover = coverUrl;
    if (_currentMusicName != null) {
      _updateMediaNotification(
        title: _currentMusicName!,
        album: '本地播放',
      );
    }
  }

  /// 刷新系统通知栏媒体信息（标题、封面、时长）
  void refreshNotification() {
    if (_currentMusicName != null) {
      _updateMediaNotification(
        title: _currentMusicName!,
        album: '本地播放',
      );
    }
  }

  @override
  Future<void> playMusicList({
    required String listName,
    required String musicName,
  }) async {
    debugPrint('🎵 [LocalPlayback] 播放列表: $listName, 歌曲: $musicName');

    // 这里可以扩展为加载整个播放列表
    // 暂时只播放指定的歌曲
    await playMusic(musicName: musicName);
  }

  @override
  Future<PlayingMusic?> getCurrentStatus() async {
    if (_currentMusicName == null) {
      return null;
    }

    final player = _ensurePlayer;
    if (player == null) {
      return null;
    }

    final position = player.position;
    final duration = player.duration;
    final isPlaying = player.playing;

    return PlayingMusic(
      ret: '0', // ret 是 String 类型
      curMusic: _currentMusicName!, // 确保非空
      curPlaylist: '本地播放',
      isPlaying: isPlaying,
      offset: position.inSeconds,
      duration: duration?.inSeconds ?? 0,
    );
  }

  @override
  Future<int> getVolume() async {
    final player = _ensurePlayer;
    if (player == null) return 0;

    // 返回 0-100 的音量值
    final volume = player.volume;
    return (volume * 100).round();
  }

  Future<void> prepareFromCache({required String url, String? name, int offset = 0}) async {
    try {
      debugPrint('🔧 [LocalPlayback] 从缓存预加载: $name, offset: $offset, URL: $url');
      _currentMusicUrl = url;
      if (name != null && name.isNotEmpty) {
        _currentMusicName = name;
      }
      await _saveCache();

      // 🔧 修复: 等待 AudioHandler 就绪后再加载
      await _waitAndAttachAudioHandler();

      // 🔧 修复: 添加延迟,确保播放器完全初始化
      await Future.delayed(const Duration(milliseconds: 300));

      await _loadAndMaybePlay(url: url, name: _currentMusicName, autoPlay: false, offset: offset);
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 预加载失败: $e');
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('🎵 [LocalPlayback] 释放播放器资源');
    // 🔧 不要 dispose 共享的 AudioPlayer,只停止播放
    // _player 是从 AudioHandlerService 共享的,不应该在这里释放
    try {
      final player = _ensurePlayer;
      if (player != null) {
        await player.stop();
      }
    } catch (e) {
      debugPrint('⚠️ [LocalPlayback] 停止播放器失败: $e');
    }
    await _statusController.close();
  }

  /// 发射当前播放状态到流
  void _emitCurrentStatus() {
    getCurrentStatus().then((status) {
      if (status != null && !_statusController.isClosed) {
        _statusController.add(status);
      }
    });
  }

  /// 设置播放列表
  void setPlaylist(List<Music> playlist, {int startIndex = 0}) {
    _playlist = playlist;
    _currentIndex = startIndex;
    debugPrint('🎵 [LocalPlayback] 设置播放列表: ${playlist.length} 首歌曲');
  }

  /// 获取当前播放列表
  List<Music> get playlist => List.unmodifiable(_playlist);

  /// 获取状态流
  Stream<PlayingMusic> get statusStream => _statusController.stream;

  Future<void> _loadAndMaybePlay({
    required String url,
    String? name,
    bool autoPlay = false,
    int offset = 0,
    String artist = '未知艺术家',
  }) async {
    // 如果正在加载且歌曲名相同，跳过重复调用
    if (_loading && _loadingMusicName == name) {
      debugPrint('⏳ [LocalPlayback] 正在加载相同歌曲，跳过重复调用');
      return;
    }

    // 🔧 新增: 如果 URL 和歌曲名都相同，且播放器已就绪，跳过重新加载
    final player = _ensurePlayer;
    if (player != null &&
        url == _currentMusicUrl &&
        name == _currentMusicName &&
        player.processingState != ProcessingState.idle &&
        !autoPlay) {
      debugPrint('✅ [LocalPlayback] URL 和歌曲名未变化，跳过重新加载');
      debugPrint('   - URL: $url');
      debugPrint('   - 歌曲: $name');
      debugPrint('   - 播放器状态: ${player.processingState}');

      // 只执行 seek（如果需要）
      if (offset > 0 && player.position.inSeconds != offset) {
        debugPrint('🎯 [LocalPlayback] 仅执行 seek 到: ${offset}s');
        await player.seek(Duration(seconds: offset));
        _emitCurrentStatus();
      }
      return;
    }

    // 如果正在加载但歌曲名不同，说明是切歌操作，取消之前的加载
    if (_loading) {
      debugPrint('🔄 [LocalPlayback] 检测到切歌请求，取消上一次加载 ($_loadingMusicName -> $name)');
      _loadToken++; // 使旧的加载操作失效
    }

    _loading = true;
    _loadingMusicName = name; // 记录正在加载的歌曲
    await _waitAndAttachAudioHandler();
    final token = ++_loadToken;
    try {
      final player = _ensurePlayer;
      if (player == null) {
        debugPrint('❌ [LocalPlayback] AudioPlayer 未初始化，无法播放');
        return;
      }

      // 🔧 切歌时先更新媒体信息为加载状态,保持通知栏连续性
      if ((name ?? '').isNotEmpty) {
        await _updateMediaNotification(
          title: name!,
          album: '本地播放',
        );
        // 🔧 设置为加载状态,避免通知栏消失
        _audioHandler?.playbackState.add(_audioHandler!.playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
        ));
      }

      // 🔧 使用 setAudioSource 代替 stop + setUrl,更平滑
      try {
        await player.setUrl(url);
      } catch (e) {
        debugPrint('⚠️ [LocalPlayback] setUrl 失败: $e');

        // 🔧 检测是否是链接失效(HTTP 500等错误)
        final errorMsg = e.toString().toLowerCase();
        if (errorMsg.contains('500') || errorMsg.contains('response code') ||
            errorMsg.contains('source error')) {
          debugPrint('🔄 [LocalPlayback] 检测到链接失效,自动跳到下一首');

          // 清理状态
          if (token == _loadToken) {
            _loading = false;
            _loadingMusicName = null;
          }

          // 延迟后自动播放下一首
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_playlist.isNotEmpty) {
              debugPrint('⏭️ [LocalPlayback] 开始播放下一首');
              next();
            }
          });

          return; // 不继续执行后续逻辑
        }

        // 其他错误,尝试重试
        await player.stop();
        await Future.delayed(const Duration(milliseconds: 50));
        await player.setUrl(url);
      }

      if (token != _loadToken) {
        debugPrint('⏭️ [LocalPlayback] 加载被新请求取消 (token: $token != $_loadToken)');
        return;
      }
      if (offset > 0) {
        await player.seek(Duration(seconds: offset));
      }

      // 🔧 更新媒体信息的 duration
      if ((name ?? '').isNotEmpty && player.duration != null) {
        await _updateMediaNotification(
          title: name!,
          album: '本地播放',
        );
      }

      if (autoPlay) {
        // 🔧 调用 AudioHandler 的 play() 方法
        if (_audioHandler != null) {
          await _audioHandler!.play();
        } else {
          await player.play();
        }
      }
      _emitCurrentStatus();
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 加载播放失败: $e');
      // 🔧 发生错误时,确保状态正确
      if (token == _loadToken) {
        _loading = false;
        _loadingMusicName = null;
      }
      rethrow;
    } finally {
      if (token == _loadToken) {
        _loading = false;
      }
    }
  }

  /// 🔧 从缓存加载当前播放的 URL 和歌曲名
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentMusicUrl = prefs.getString(_cacheKeyUrl);
      _currentMusicName = prefs.getString(_cacheKeyName);

      debugPrint('🔧 [LocalPlayback] 从缓存加载:');
      debugPrint('   - 歌曲名: ${_currentMusicName ?? "null"}');
      debugPrint('   - URL: ${_currentMusicUrl ?? "null"}');

      // 🔊 恢复音量
      await _loadVolume();
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 加载缓存失败: $e');
    }
  }

  /// 🔧 保存当前播放的 URL 和歌曲名到缓存
  Future<void> _saveCache() async {
    try {
      if (_currentMusicUrl == null || _currentMusicUrl!.isEmpty) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyUrl, _currentMusicUrl!);
      if (_currentMusicName != null) {
        await prefs.setString(_cacheKeyName, _currentMusicName!);
      }

      debugPrint('💾 [LocalPlayback] 已保存缓存:');
      debugPrint('   - 歌曲名: $_currentMusicName');
      debugPrint('   - URL: $_currentMusicUrl');
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 保存缓存失败: $e');
    }
  }

  /// 🔧 判断URL是否需要替换为登录域名
  ///
  /// 返回 true: 需要替换(服务器本地音乐)
  /// 返回 false: 不需要替换(在线音乐直链)
  bool _shouldReplaceWithLoginDomain(String url) {
    // 🎯 如果没有 apiService,不需要替换
    if (_apiService == null) return false;

    try {
      final uri = Uri.parse(url);
      final loginBaseUrl = _apiService!.baseUrl;
      final loginUri = Uri.parse(loginBaseUrl);

      // 如果URL的域名和登录服务器的域名相同,说明是服务器音乐,需要替换
      // (可能是内网IP,需要替换成外网域名)
      if (uri.host == loginUri.host) {
        return true;
      }

      // 如果是内网IP地址(192.168.x.x, 10.x.x.x, 172.16-31.x.x),需要替换
      final isPrivateIp = RegExp(
        r'^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)',
      ).hasMatch(uri.host);
      if (isPrivateIp) {
        return true;
      }

      // 其他情况(外部域名)不需要替换
      return false;
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 判断URL是否需要替换失败: $e');
      // 出错时保守处理,不替换
      return false;
    }
  }

  /// 🔧 将NAS返回的内网地址替换为登录时的域名
  ///
  /// 例如：
  /// - NAS返回: http://192.168.31.2:8090/music/download/song.mp3
  /// - 登录地址: https://music.example.com:8443
  /// - 替换后: https://music.example.com:8443/music/download/song.mp3
  String _replaceWithLoginDomain(String nasUrl) {
    // 🎯 如果没有 apiService,直接返回原URL
    if (_apiService == null) return nasUrl;

    try {
      // 获取登录时保存的服务器地址
      final loginBaseUrl = _apiService!.baseUrl;
      debugPrint('🔄 [LocalPlayback] URL替换:');
      debugPrint('   - NAS URL: $nasUrl');
      debugPrint('   - 登录地址: $loginBaseUrl');

      final loginUri = Uri.parse(loginBaseUrl);
      final nasUri = Uri.parse(nasUrl);

      // 用登录地址的 scheme/host/port 替换NAS地址的对应部分
      // 保留NAS地址的 path/query/fragment
      final replacedUri = nasUri.replace(
        scheme: loginUri.scheme, // http/https
        host: loginUri.host,     // 域名或IP
        port: loginUri.port,     // 端口（如果有）
      );

      final replacedUrl = replacedUri.toString();
      debugPrint('   - 替换后: $replacedUrl');

      return replacedUrl;
    } catch (e) {
      debugPrint('❌ [LocalPlayback] URL替换失败: $e');
      // 替换失败时返回原URL
      return nasUrl;
    }
  }

  /// 🔊 保存音量到本地存储
  Future<void> _saveVolume(int volume) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cacheKeyVolume, volume);
      debugPrint('💾 [LocalPlayback] 已保存音量: $volume');
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 保存音量失败: $e');
    }
  }

  /// 🔊 从本地存储加载音量
  Future<void> _loadVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVolume = prefs.getInt(_cacheKeyVolume);

      if (savedVolume != null) {
        final player = _ensurePlayer;
        if (player != null) {
          final normalizedVolume = savedVolume / 100.0;
          await player.setVolume(normalizedVolume.clamp(0.0, 1.0));
          debugPrint('🔊 [LocalPlayback] 已恢复音量: $savedVolume');
        }
      } else {
        debugPrint('🔊 [LocalPlayback] 没有保存的音量，使用默认值');
      }
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 加载音量失败: $e');
    }
  }
}
