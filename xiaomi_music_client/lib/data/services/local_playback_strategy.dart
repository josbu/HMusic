import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playing_music.dart';
import '../models/music.dart';
import 'music_api_service.dart';
import 'playback_strategy.dart';
import 'audio_handler_service.dart';

/// 本地播放策略实现
/// 使用 just_audio 在手机本地播放音乐
class LocalPlaybackStrategy implements PlaybackStrategy {
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
  final MusicApiService _apiService;
  AudioPlayer? _player; // 🔧 改为可空，从共享的静态变量获取
  AudioHandlerService? _audioHandler;
  int _loadToken = 0;
  bool _loading = false;

  // SharedPreferences 缓存 key（与 PlaybackProvider 保持一致）
  static const String _cacheKeyUrl = 'local_playback_url';
  static const String _cacheKeyName = 'local_playback_current_name';

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

  LocalPlaybackStrategy({required MusicApiService apiService})
    : _apiService = apiService {
    _initAudioSession();

    // 🔧 先尝试立即绑定(如果 AudioHandler 已就绪)
    _attachAudioHandlerIfAvailable();

    if (_audioHandler != null && _sharedAudioPlayer != null) {
      // 如果已经绑定成功,立即初始化
      debugPrint('✅ [LocalPlayback] AudioPlayer 已就绪，立即初始化');
      _initPlayer();
      _loadCache();
    } else {
      // 否则等待 AudioHandler 就绪
      debugPrint('⏳ [LocalPlayback] 等待 AudioHandler 就绪...');
      _waitAndAttachAudioHandler().then((_) {
        if (_audioHandler != null && _sharedAudioPlayer != null) {
          debugPrint('✅ [LocalPlayback] AudioHandler 就绪，初始化播放器');
          _player = _sharedAudioPlayer!;
          _initPlayer();
          _loadCache();
        } else {
          debugPrint('❌ [LocalPlayback] AudioHandler 未就绪，初始化失败');
        }
      });
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
    debugPrint('🎵 [LocalPlayback] 跳转到 $seconds 秒');
    final player = _ensurePlayer;
    if (player != null) {
      await player.seek(Duration(seconds: seconds));
      _emitCurrentStatus();
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
    }
  }

  @override
  Future<void> playMusic({
    required String musicName,
    String? url,
    String? platform,
    String? songId,
  }) async {
    try {
      debugPrint('🎵 [LocalPlayback] 播放音乐: $musicName');
      debugPrint('🎵 [LocalPlayback] URL: $url');

      String playUrl = url ?? '';
      if (playUrl.isEmpty) {
        debugPrint('🎵 [LocalPlayback] 从服务器获取音乐链接: $musicName');
        final musicInfo = await _apiService.getMusicInfo(musicName);
        playUrl = musicInfo['url']?.toString() ?? '';
        if (playUrl.isEmpty) {
          throw Exception('无法获取音乐播放链接');
        }
        debugPrint('🎵 [LocalPlayback] 获取到播放链接: $playUrl');
      }

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
      artist: artist,
      album: album,
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
        artist: '未知艺术家',
        album: '本地播放',
      );
    }
  }

  /// 刷新系统通知栏媒体信息（标题、封面、时长）
  void refreshNotification() {
    if (_currentMusicName != null) {
      _updateMediaNotification(
        title: _currentMusicName!,
        artist: '未知艺术家',
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

      await player.stop();
      await player.setUrl(url);
      if (token != _loadToken) {
        debugPrint('⏭️ [LocalPlayback] 加载被新请求取消 (token: $token != $_loadToken)');
        return;
      }
      if (offset > 0) {
        await player.seek(Duration(seconds: offset));
      }
      if ((name ?? '').isNotEmpty) {
        await _updateMediaNotification(
          title: name!,
          artist: artist,
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
}
