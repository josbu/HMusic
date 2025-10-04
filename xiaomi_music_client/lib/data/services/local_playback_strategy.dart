import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/playing_music.dart';
import '../models/music.dart';
import 'music_api_service.dart';
import 'playback_strategy.dart';

/// 本地播放策略实现
/// 使用 just_audio 在手机本地播放音乐
class LocalPlaybackStrategy implements PlaybackStrategy {
  final MusicApiService _apiService;
  final AudioPlayer _player = AudioPlayer();

  // 播放列表
  List<Music> _playlist = [];
  int _currentIndex = 0;
  String? _currentMusicName;
  String? _currentMusicUrl;

  // 状态流控制器
  final _statusController = StreamController<PlayingMusic>.broadcast();

  LocalPlaybackStrategy({required MusicApiService apiService})
    : _apiService = apiService {
    _initPlayer();
  }

  void _initPlayer() {
    // 监听播放状态变化
    _player.playerStateStream.listen((state) {
      debugPrint(
        '🎵 [LocalPlayback] 播放器状态: ${state.playing}, ${state.processingState}',
      );

      // 自动播放下一首
      if (state.processingState == ProcessingState.completed) {
        debugPrint('🎵 [LocalPlayback] 当前歌曲播放完成，尝试播放下一首');
        next();
      }
    });

    // 监听位置变化（用于更新进度）
    _player.positionStream.listen((position) {
      // 每秒更新一次状态
      if (position.inSeconds % 1 == 0) {
        _emitCurrentStatus();
      }
    });
  }

  @override
  bool get isLocalMode => true;

  @override
  Future<void> play() async {
    debugPrint('🎵 [LocalPlayback] 执行播放');
    await _player.play();
    _emitCurrentStatus();
  }

  @override
  Future<void> pause() async {
    debugPrint('🎵 [LocalPlayback] 执行暂停');
    await _player.pause();
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
    await _player.seek(Duration(seconds: seconds));
    _emitCurrentStatus();
  }

  @override
  Future<void> setVolume(int volume) async {
    debugPrint('🎵 [LocalPlayback] 设置音量: $volume');
    // 音量范围 0-100 转换为 0.0-1.0
    final normalizedVolume = volume / 100.0;
    await _player.setVolume(normalizedVolume.clamp(0.0, 1.0));
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

      // 如果没有提供 URL，说明是服务器本地音乐，需要获取下载链接
      if (playUrl.isEmpty) {
        debugPrint('🎵 [LocalPlayback] 从服务器获取音乐链接: $musicName');
        final musicInfo = await _apiService.getMusicInfo(musicName);
        playUrl = musicInfo['url']?.toString() ?? '';

        if (playUrl.isEmpty) {
          throw Exception('无法获取音乐播放链接');
        }
        debugPrint('🎵 [LocalPlayback] 获取到播放链接: $playUrl');
      }

      // 使用 just_audio 播放
      _currentMusicName = musicName;
      _currentMusicUrl = playUrl;

      await _player.setUrl(playUrl);
      await _player.play();

      debugPrint('✅ [LocalPlayback] 开始播放: $musicName');
      _emitCurrentStatus();
    } catch (e) {
      debugPrint('❌ [LocalPlayback] 播放失败: $e');
      rethrow;
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

    final position = _player.position;
    final duration = _player.duration;
    final isPlaying = _player.playing;

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
    // 返回 0-100 的音量值
    final volume = _player.volume;
    return (volume * 100).round();
  }

  @override
  Future<void> dispose() async {
    debugPrint('🎵 [LocalPlayback] 释放播放器资源');
    await _player.stop();
    await _player.dispose();
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
}
