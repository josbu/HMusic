import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/playing_music.dart';
import '../../data/models/online_music_result.dart';
import '../../data/services/native_music_search_service.dart';
import 'dio_provider.dart';
import 'device_provider.dart';

// 用于区分"未传入参数"和"传入 null"
const _undefined = Object();

enum PlayMode {
  loop, // 全部循环
  single, // 单曲循环
  random, // 随机播放
  sequence, // 顺序播放
  singlePlay, // 单曲播放
}

extension PlayModeExtension on PlayMode {
  String get displayName {
    switch (this) {
      case PlayMode.loop:
        return '全部循环';
      case PlayMode.single:
        return '单曲循环';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.singlePlay:
        return '单曲播放';
    }
  }

  String get command {
    switch (this) {
      case PlayMode.loop:
        return '全部循环';
      case PlayMode.single:
        return '单曲循环';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.singlePlay:
        return '单曲播放';
    }
  }

  IconData get icon {
    switch (this) {
      case PlayMode.loop:
        return Icons.repeat;
      case PlayMode.single:
        return Icons.repeat_one;
      case PlayMode.random:
        return Icons.shuffle;
      case PlayMode.sequence:
        return Icons.reorder;
      case PlayMode.singlePlay:
        return Icons.looks_one;
    }
  }
}

class PlaybackState {
  final PlayingMusic? currentMusic;
  final int volume;
  final bool isLoading;
  final String? error;
  final PlayMode playMode;
  final bool hasLoaded; // whether initial fetch attempted
  final String? albumCoverUrl; // ✨ 当前播放歌曲的专辑封面图 URL
  final int timerMinutes; // ⏰ 定时关机分钟数（0 表示未设置）
  final bool isFavorite; // ⭐ 当前歌曲是否已收藏
  final List<String> currentPlaylistSongs; // 🎵 当前播放列表的所有歌曲

  const PlaybackState({
    this.currentMusic,
    this.volume = 0, // Initial UI shows volume at 0 before server data arrives
    this.isLoading = false,
    this.error,
    this.playMode = PlayMode.loop, // 默认全部循环
    this.hasLoaded = false,
    this.albumCoverUrl,
    this.timerMinutes = 0, // 默认未设置定时
    this.isFavorite = false, // 默认未收藏
    this.currentPlaylistSongs = const [], // 默认空列表
  });

  PlaybackState copyWith({
    PlayingMusic? currentMusic,
    int? volume,
    bool? isLoading,
    String? error,
    PlayMode? playMode,
    bool? hasLoaded,
    Object? albumCoverUrl = _undefined,
    int? timerMinutes,
    bool? isFavorite,
    List<String>? currentPlaylistSongs,
  }) {
    return PlaybackState(
      currentMusic: currentMusic ?? this.currentMusic,
      volume: volume ?? this.volume,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      playMode: playMode ?? this.playMode,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      albumCoverUrl:
          albumCoverUrl == _undefined
              ? this.albumCoverUrl
              : albumCoverUrl as String?,
      timerMinutes: timerMinutes ?? this.timerMinutes,
      isFavorite: isFavorite ?? this.isFavorite,
      currentPlaylistSongs: currentPlaylistSongs ?? this.currentPlaylistSongs,
    );
  }
}

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  final Ref ref;
  bool _isInitialized = false;
  Timer? _statusRefreshTimer;
  Timer? _localProgressTimer;
  DateTime? _lastUpdateTime;
  DateTime? _lastProgressUpdate; // 上次UI进度更新时间
  DateTime? _lastRefreshTime; // 上次状态刷新时间
  // 保存服务器最后返回的原始进度，用于本地预测基准
  int? _lastServerOffset;

  // 🖼️ 封面图自动搜索相关
  final _searchService = NativeMusicSearchService();
  final Map<String, String> _coverCache = {}; // 歌曲名 -> 封面URL 的缓存
  static const String _coverCacheKey = 'album_cover_cache';
  static const int _maxCacheSize = 200; // 最多缓存200首歌的封面

  PlaybackNotifier(this.ref)
    : super(const PlaybackState(isLoading: false, hasLoaded: false)) {
    // 禁用自动初始化，避免在未登录时进行网络请求
    // 需要用户手动触发初始化
    debugPrint('PlaybackProvider: 自动初始化已禁用，等待用户手动触发');
    // 🖼️ 异步加载封面图缓存
    _loadCoverCache();
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    _localProgressTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      await ref.read(deviceProvider.notifier).loadDevices();
      await refreshStatus();
    } catch (e) {
      // 初始化失败，设置错误状态但不抛出异常
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: '初始化失败: ${e.toString()}',
      );
    }
  }

  // 公共方法，允许手动触发初始化
  Future<void> ensureInitialized() async {
    await _initialize();
  }

  // 设备加载由 deviceProvider 负责

  Future<void> refreshStatus({bool silent = false}) async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) {
      if (state.isLoading) {
        state = state.copyWith(isLoading: false, hasLoaded: true);
      } else {
        state = state.copyWith(hasLoaded: true);
      }
      return;
    }

    // 防止过于频繁的刷新请求
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!).inMilliseconds < 500) {
      print('🎵 跳过过于频繁的状态刷新请求');
      return;
    }
    _lastRefreshTime = now;

    try {
      if (!silent) {
        state = state.copyWith(isLoading: true);
      }
      print('🎵 正在获取播放状态...');

      // 直接使用播放状态API获取完整信息
      final currentPlayingResponse = await apiService.getCurrentPlaying(
        did: selectedDid,
      );
      print('🎵 播放状态API响应: $currentPlayingResponse');

      PlayingMusic? currentMusic;

      if (currentPlayingResponse['ret'] == 'OK') {
        currentMusic = PlayingMusic.fromJson(currentPlayingResponse);
        print(
          '🎵 解析后的播放状态: 音乐=${currentMusic.curMusic}, 播放中=${currentMusic.isPlaying}, 进度=${currentMusic.offset}/${currentMusic.duration}',
        );
      } else {
        print('🎵 API返回错误或无播放内容');
      }

      final volumeResponse = await apiService.getVolume(did: selectedDid);
      print('🎵 音量响应: $volumeResponse');

      final volume = volumeResponse['volume'] as int? ?? state.volume;

      // 获取当前播放列表
      List<String> playlistSongs = [];
      try {
        final playlistResponse = await apiService.getCurrentPlaylist(
          did: selectedDid,
        );
        print('🎵 播放列表API响应: $playlistResponse');

        if (playlistResponse['cur_playlist'] != null) {
          final songs = playlistResponse['cur_playlist'] as List?;
          if (songs != null) {
            playlistSongs = songs.map((s) => s.toString()).toList();
            print('🎵 当前播放列表有 ${playlistSongs.length} 首歌曲');
          }
        }
      } catch (e) {
        print('🎵 获取播放列表失败: $e');
        // 即使失败也继续，保留原有列表
        playlistSongs = state.currentPlaylistSongs;
      }

      print('🎵 最终播放状态: ${currentMusic?.curMusic ?? "无"}');
      print('🎵 当前音量: $volume');

      // 🎯 检测歌曲切换
      bool isSongChanged = false;
      if (state.currentMusic != null && currentMusic != null) {
        final oldSongName = state.currentMusic!.curMusic;
        final newSongName = currentMusic.curMusic;
        if (oldSongName != newSongName) {
          isSongChanged = true;
          print('🎵 检测到歌曲切换: "$oldSongName" -> "$newSongName"');
        }
      }

      // 智能进度同步校准机制
      bool needsRecalibration = false;
      bool useSmoothing = false;

      if (isSongChanged) {
        // 🎯 歌曲切换：立即重置进度基准
        needsRecalibration = true;
        print('🔄 歌曲已切换，重置进度基准');
      } else if (state.currentMusic != null && currentMusic != null) {
        final localOffset = state.currentMusic!.offset;
        final serverOffset = currentMusic.offset;
        final offsetDiff = (serverOffset - localOffset).abs();

        // 智能校准策略：
        // - 差异 > 5秒：立即重新校准（可能是跳转或切歌）
        // - 差异 2-5秒：使用平滑过渡
        // - 差异 < 2秒：正常预测继续
        if (offsetDiff > 5) {
          needsRecalibration = true;
          print('🔄 检测到大幅进度跳跃，差异: ${offsetDiff}秒，立即重新校准');
        } else if (offsetDiff > 2) {
          useSmoothing = true;
          print('🔄 检测到中等进度差异: ${offsetDiff}秒，使用平滑过渡');
        } else if (offsetDiff > 0.5) {
          print('🔄 微调进度，差异: ${offsetDiff}秒');
        }
      }

      // 🎯 如果歌曲切换，清除旧的封面图和收藏状态
      state = state.copyWith(
        currentMusic: currentMusic,
        volume: volume,
        error: null,
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
        albumCoverUrl: isSongChanged ? null : state.albumCoverUrl,
        isFavorite: isSongChanged ? false : state.isFavorite,
        currentPlaylistSongs: playlistSongs,
      );

      // 智能更新预测基准
      if (needsRecalibration) {
        // 立即重新校准
        _lastServerOffset = currentMusic?.offset ?? 0;
        _lastUpdateTime = DateTime.now();
        print('⏰ 立即重新校准，基准进度: ${_lastServerOffset}秒');
      } else if (useSmoothing) {
        // 使用加权平均进行平滑过渡
        final serverOffset = currentMusic?.offset ?? 0;
        final currentBase = _lastServerOffset ?? 0;
        _lastServerOffset = (currentBase * 0.3 + serverOffset * 0.7).round();
        _lastUpdateTime = DateTime.now();
        print('🔄 平滑过渡到新进度: ${_lastServerOffset}秒');
      } else if (currentMusic != null) {
        // 正常更新，保持预测连续性
        final timeSinceLastUpdate =
            _lastUpdateTime != null
                ? DateTime.now().difference(_lastUpdateTime!).inSeconds
                : 0;

        // 只有当服务器进度合理时才更新基准
        final serverOffset = currentMusic.offset;
        final expectedOffset = (_lastServerOffset ?? 0) + timeSinceLastUpdate;

        if ((serverOffset - expectedOffset).abs() <= 3) {
          _lastServerOffset = serverOffset;
          _lastUpdateTime = DateTime.now();
        }
      }

      // 🖼️ 自动搜索封面图（适用于服务端本地歌曲）
      if (currentMusic != null &&
          (state.albumCoverUrl == null || state.albumCoverUrl!.isEmpty)) {
        // 异步搜索封面图，不阻塞主流程
        _autoFetchAlbumCover(currentMusic.curMusic).catchError((e) {
          print('🖼️ [AutoCover] 异步搜索封面失败: $e');
        });
      }

      // 如果音乐正在播放，启动自动刷新进度
      _startProgressTimer(currentMusic?.isPlaying ?? false);
    } catch (e) {
      print('🎵 获取播放状态失败: $e');

      String errorMessage = '获取播放状态失败';
      if (e.toString().contains('Did not exist')) {
        errorMessage = '设备不存在或离线';
        ref.read(deviceProvider.notifier).selectDevice('');
        state = state.copyWith(error: errorMessage);
      } else {
        state = state.copyWith(error: errorMessage);
      }
      state = state.copyWith(
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
      );
    }
  }

  Future<void> shutdown() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      state = state.copyWith(isLoading: true);

      print('🎵 执行关机命令');

      await apiService.shutdown(did: selectedDid);

      // 关机后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 关机失败: $e');
      state = state.copyWith(isLoading: false, error: '关机失败: ${e.toString()}');
    }
  }

  Future<void> pauseMusic() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    // 🎯 乐观更新：先更新本地UI状态
    if (state.currentMusic != null) {
      final updatedMusic = PlayingMusic(
        curMusic: state.currentMusic!.curMusic,
        curPlaylist: state.currentMusic!.curPlaylist,
        isPlaying: false, // 立即显示为暂停状态
        offset: state.currentMusic!.offset,
        duration: state.currentMusic!.duration,
        ret: '',
      );
      state = state.copyWith(currentMusic: updatedMusic);
      _startProgressTimer(false); // 停止本地进度更新
    }

    try {
      print('🎵 执行暂停命令');
      await apiService.pauseMusic(did: selectedDid);

      // 延迟同步真实状态
      Future.delayed(const Duration(milliseconds: 1500), () {
        refreshStatus(silent: true);
      });
    } catch (e) {
      print('🎵 暂停失败: $e');
      // 如果请求失败，恢复原来的状态
      refreshStatus(silent: true);
      state = state.copyWith(error: '暂停失败: ${e.toString()}');
    }
  }

  Future<void> resumeMusic() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    // 🎯 乐观更新：先更新本地UI状态
    if (state.currentMusic != null) {
      final updatedMusic = PlayingMusic(
        ret: state.currentMusic!.ret,
        curMusic: state.currentMusic!.curMusic,
        curPlaylist: state.currentMusic!.curPlaylist,
        isPlaying: true, // 立即显示为播放状态
        offset: state.currentMusic!.offset,
        duration: state.currentMusic!.duration,
      );
      state = state.copyWith(currentMusic: updatedMusic);
      _lastServerOffset = state.currentMusic!.offset; // 保存当前进度作为基准
      _lastUpdateTime = DateTime.now(); // 重置本地进度计时
      _startProgressTimer(true); // 开始本地进度更新
    }

    try {
      print('🎵 执行播放命令');
      await apiService.resumeMusic(did: selectedDid);

      // 延迟同步真实状态
      Future.delayed(const Duration(milliseconds: 1500), () {
        refreshStatus(silent: true);
      });
    } catch (e) {
      print('🎵 播放失败: $e');
      // 如果请求失败，恢复原来的状态
      refreshStatus(silent: true);
      state = state.copyWith(error: '播放失败: ${e.toString()}');
    }
  }

  Future<void> playPause() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      final isPlaying = state.currentMusic?.isPlaying ?? false;
      print('🎵 执行播放控制命令: ${isPlaying ? "暂停" : "播放歌曲"}');

      // 🎯 立即乐观更新UI，提升响应性
      if (state.currentMusic != null) {
        final updatedMusic = PlayingMusic(
          ret: state.currentMusic!.ret,
          curMusic: state.currentMusic!.curMusic,
          curPlaylist: state.currentMusic!.curPlaylist,
          isPlaying: !isPlaying, // 切换播放状态
          offset: state.currentMusic!.offset,
          duration: state.currentMusic!.duration,
        );
        state = state.copyWith(currentMusic: updatedMusic, isLoading: false);

        // 更新本地进度计时器
        _startProgressTimer(!isPlaying);
        if (!isPlaying) {
          _lastServerOffset = state.currentMusic!.offset;
          _lastUpdateTime = DateTime.now();
        }
      }

      // 异步执行实际命令
      if (isPlaying) {
        await apiService.pauseMusic(did: selectedDid);
      } else {
        await apiService.resumeMusic(did: selectedDid);
      }

      // 延迟同步真实状态，但不影响UI响应
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => refreshStatus(silent: true),
      );
    } catch (e) {
      print('🎵 播放控制失败: $e');
      // 如果请求失败，恢复原状态
      Future.delayed(
        const Duration(milliseconds: 500),
        () => refreshStatus(silent: true),
      );
      state = state.copyWith(
        isLoading: false,
        error: '播放控制失败: ${e.toString()}',
      );
    }
  }

  Future<void> previous() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      state = state.copyWith(isLoading: true);

      print('🎵 执行上一首命令');

      await apiService.executeCommand(
        did: selectedDid,
        command: '上一首', // 使用中文命令
      );

      // 等待命令执行后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 上一首失败: $e');
      state = state.copyWith(isLoading: false, error: '上一首失败: ${e.toString()}');
    }
  }

  Future<void> next() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      state = state.copyWith(isLoading: true);

      print('🎵 执行下一首命令');

      await apiService.executeCommand(
        did: selectedDid,
        command: '下一首', // 使用中文命令
      );

      // 等待命令执行后刷新状态
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 下一首失败: $e');
      state = state.copyWith(isLoading: false, error: '下一首失败: ${e.toString()}');
    }
  }

  Future<void> setVolume(int volume) async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    try {
      await apiService.setVolume(did: selectedDid, volume: volume);

      state = state.copyWith(volume: volume);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // 即时更新 UI 的本地音量值，不触发后端调用
  void setVolumeLocal(int volume) {
    state = state.copyWith(volume: volume);
  }

  Future<void> seekTo(int seconds) async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;
    try {
      await apiService.seek(did: selectedDid, seconds: seconds);
      await Future.delayed(const Duration(milliseconds: 500));
      await refreshStatus(silent: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> playMusic({
    required String deviceId,
    String? musicName,
    String? searchKey,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      state = state.copyWith(error: 'API 服务未初始化');
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      print('🎵 开始播放音乐: $musicName, 设备ID: $deviceId');

      await apiService.playMusic(
        did: deviceId,
        musicName: musicName,
        searchKey: searchKey,
      );

      print('🎵 播放请求成功');

      // 等待一下让播放状态更新
      await Future.delayed(const Duration(milliseconds: 1000));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 播放失败: $e');
      String errorMessage = '播放失败';

      if (e.toString().contains('Did not exist')) {
        errorMessage = '设备不存在或离线，请检查设备状态或重新选择设备';
      } else if (e.toString().contains('Connection')) {
        errorMessage = '网络连接失败，请检查服务器连接';
      } else {
        errorMessage = '播放失败: ${e.toString()}';
      }

      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  /// 播放在线搜索结果（新方法，支持多种格式）
  Future<void> playOnlineResult({
    required String deviceId,
    OnlineMusicResult? singleResult,
    List<OnlineMusicResult>? resultList,
    List<Map<String, dynamic>>? rawResults,
    String playlistName = "在线播放",
    Map<String, String>? defaultHeaders,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      state = state.copyWith(error: 'API 服务未初始化');
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      String songInfo = "";
      if (singleResult != null) {
        songInfo = "${singleResult.title} - ${singleResult.author}";
      } else if (resultList != null && resultList.isNotEmpty) {
        songInfo = "${resultList.first.title} - ${resultList.first.author}";
      } else if (rawResults != null && rawResults.isNotEmpty) {
        final firstResult = rawResults.first;
        final title = firstResult['title'] ?? firstResult['name'] ?? '未知标题';
        final artist =
            firstResult['artist'] ?? firstResult['singer'] ?? '未知艺术家';
        songInfo = "$title - $artist";
      }

      print('🎵 开始播放在线搜索结果: $songInfo, 设备ID: $deviceId');

      await apiService.playOnlineSearchResult(
        did: deviceId,
        singleResult: singleResult,
        resultList: resultList,
        rawResults: rawResults,
        playlistName: playlistName,
        defaultHeaders: defaultHeaders,
      );

      print('🎵 在线播放请求成功');

      // 等待播放状态更新
      await Future.delayed(const Duration(milliseconds: 1500));
      await refreshStatus();

      state = state.copyWith(isLoading: false);
    } catch (e) {
      print('🎵 在线播放失败: $e');
      String errorMessage = '在线播放失败';

      if (e.toString().contains('Did not exist')) {
        errorMessage = '设备不存在或离线，请检查设备状态或重新选择设备';
      } else if (e.toString().contains('Connection')) {
        errorMessage = '网络连接失败，请检查服务器连接';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '音乐格式不支持，请尝试其他歌曲';
      } else {
        errorMessage = '在线播放失败: ${e.toString()}';
      }

      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  // 选设备交由 deviceProvider

  void _startProgressTimer(bool isPlaying) {
    _statusRefreshTimer?.cancel();
    _localProgressTimer?.cancel();

    if (isPlaying && state.currentMusic != null) {
      // 智能刷新策略：根据播放状态调整刷新频率
      final duration = state.currentMusic?.duration ?? 0;
      final refreshInterval = duration > 300 ? 8 : 5; // 长歌曲减少刷新频率

      _statusRefreshTimer = Timer.periodic(Duration(seconds: refreshInterval), (
        _,
      ) {
        refreshStatus(silent: true);
      });

      // 更平滑的本地进度更新
      _localProgressTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        _updateLocalProgress();
      });

      print('⏰ 启动智能进度定时器，刷新间隔: ${refreshInterval}秒');
    } else {
      print('⏸️ 停止进度定时器');
    }
  }

  void _updateLocalProgress() {
    if (state.currentMusic == null ||
        !state.currentMusic!.isPlaying ||
        _lastUpdateTime == null ||
        _lastServerOffset == null) {
      return;
    }

    final now = DateTime.now();
    final elapsedSeconds =
        now.difference(_lastUpdateTime!).inMilliseconds / 1000.0;

    // 更精确的进度预测，支持小数秒
    final predictedOffset = (_lastServerOffset! + elapsedSeconds).clamp(
      0.0,
      double.infinity,
    );
    final duration = state.currentMusic!.duration;
    final currentOffset = state.currentMusic!.offset;

    // 智能更新策略：
    // 1. 确保进度不超过总时长
    // 2. 避免倒退（除非是合理的小幅调整）
    // 3. 限制更新频率避免UI抖动
    final newOffset = predictedOffset.floor();

    if (newOffset < duration &&
        (newOffset > currentOffset || (currentOffset - newOffset).abs() <= 1)) {
      // 避免频繁的微小更新
      if ((newOffset - currentOffset).abs() >= 1 ||
          now.difference(_lastProgressUpdate ?? DateTime(0)).inMilliseconds >=
              500) {
        final updatedMusic = PlayingMusic(
          ret: state.currentMusic!.ret,
          curMusic: state.currentMusic!.curMusic,
          curPlaylist: state.currentMusic!.curPlaylist,
          isPlaying: state.currentMusic!.isPlaying,
          offset: newOffset,
          duration: state.currentMusic!.duration,
        );

        state = state.copyWith(currentMusic: updatedMusic);
        _lastProgressUpdate = now;
      }
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 更新专辑封面图 URL
  void updateAlbumCover(String coverUrl) {
    if (coverUrl.isNotEmpty) {
      state = state.copyWith(albumCoverUrl: coverUrl);
      print('[Playback] 🖼️  封面图已更新: $coverUrl');
    }
  }

  /// 🖼️ 从本地存储加载封面图缓存
  Future<void> _loadCoverCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_coverCacheKey);
      if (cacheJson != null && cacheJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(cacheJson);
        _coverCache.clear();
        decoded.forEach((key, value) {
          if (value is String) {
            _coverCache[key] = value;
          }
        });
        print('🖼️ [CoverCache] 已加载 ${_coverCache.length} 条封面缓存');
      }
    } catch (e) {
      print('🖼️ [CoverCache] 加载缓存失败: $e');
    }
  }

  /// 🖼️ 保存封面图缓存到本地存储
  Future<void> _saveCoverCache() async {
    try {
      // 限制缓存大小，移除最早的条目
      if (_coverCache.length > _maxCacheSize) {
        final keysToRemove =
            _coverCache.keys.take(_coverCache.length - _maxCacheSize).toList();
        for (final key in keysToRemove) {
          _coverCache.remove(key);
        }
        print('🖼️ [CoverCache] 清理缓存，当前大小: ${_coverCache.length}');
      }

      final prefs = await SharedPreferences.getInstance();
      final cacheJson = jsonEncode(_coverCache);
      await prefs.setString(_coverCacheKey, cacheJson);
      print('🖼️ [CoverCache] 已保存 ${_coverCache.length} 条封面缓存');
    } catch (e) {
      print('🖼️ [CoverCache] 保存缓存失败: $e');
    }
  }

  /// 🖼️ 自动搜索并获取歌曲封面图（用于服务端本地歌曲）
  Future<void> _autoFetchAlbumCover(String songName) async {
    // 🎯 先检查缓存
    if (_coverCache.containsKey(songName)) {
      final cachedUrl = _coverCache[songName]!;
      print('🖼️ [AutoCover] 从缓存加载封面: $songName');
      updateAlbumCover(cachedUrl);
      return;
    }

    try {
      print('🖼️ [AutoCover] 开始自动搜索封面: $songName');

      // 优先搜索QQ音乐（封面质量较好）
      List<OnlineMusicResult> results = await _searchService.searchQQ(
        query: songName,
        page: 1,
      );

      // 如果QQ音乐没有结果，尝试网易云音乐
      if (results.isEmpty) {
        print('🖼️ [AutoCover] QQ音乐无结果，尝试网易云音乐');
        results = await _searchService.searchNetease(query: songName, page: 1);
      }

      // 从搜索结果中提取封面图
      if (results.isNotEmpty) {
        final firstResult = results.first;
        if (firstResult.picture != null && firstResult.picture!.isNotEmpty) {
          print('🖼️ [AutoCover] 找到封面: ${firstResult.picture}');
          print(
            '🖼️ [AutoCover] 来源: ${firstResult.title} - ${firstResult.author}',
          );

          // 🎯 保存到缓存
          _coverCache[songName] = firstResult.picture!;
          _saveCoverCache(); // 异步保存，不阻塞主流程

          // 更新封面图（在主线程中）
          updateAlbumCover(firstResult.picture!);
        } else {
          print('🖼️ [AutoCover] 搜索结果无封面图信息');
        }
      } else {
        print('🖼️ [AutoCover] 未找到搜索结果');
      }
    } catch (e) {
      print('🖼️ [AutoCover] 搜索封面失败: $e');
      // 静默失败，不影响播放
    }
  }

  /// 🎵 切换播放模式
  Future<void> switchPlayMode(PlayMode newMode) async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      return;
    }

    try {
      debugPrint('🎵 切换播放模式: ${newMode.displayName} (${newMode.command})');
      await apiService.executeCommand(
        did: selectedDid,
        command: newMode.command,
      );

      // 更新本地状态
      state = state.copyWith(playMode: newMode);
      debugPrint('✅ 播放模式已切换: ${newMode.displayName}');
    } catch (e) {
      debugPrint('❌ 切换播放模式失败: $e');
      state = state.copyWith(error: '切换播放模式失败: ${e.toString()}');
    }
  }

  /// ⭐ 加入收藏
  Future<void> addToFavorites() async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      state = state.copyWith(error: '未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      state = state.copyWith(error: 'API服务未初始化');
      return;
    }

    if (state.currentMusic == null) {
      debugPrint('⚠️  当前没有播放歌曲');
      state = state.copyWith(error: '当前没有播放歌曲');
      return;
    }

    try {
      debugPrint('⭐ 加入收藏: ${state.currentMusic!.curMusic}');
      await apiService.executeCommand(did: selectedDid, command: '加入收藏');
      state = state.copyWith(isFavorite: true);
      debugPrint('✅ 已加入收藏');
    } catch (e) {
      debugPrint('❌ 加入收藏失败: $e');
      state = state.copyWith(error: '加入收藏失败: ${e.toString()}');
    }
  }

  /// 💔 取消收藏
  Future<void> removeFromFavorites() async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      state = state.copyWith(error: '未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      state = state.copyWith(error: 'API服务未初始化');
      return;
    }

    if (state.currentMusic == null) {
      debugPrint('⚠️  当前没有播放歌曲');
      state = state.copyWith(error: '当前没有播放歌曲');
      return;
    }

    try {
      debugPrint('💔 取消收藏: ${state.currentMusic!.curMusic}');
      await apiService.executeCommand(did: selectedDid, command: '取消收藏');
      state = state.copyWith(isFavorite: false);
      debugPrint('✅ 已取消收藏');
    } catch (e) {
      debugPrint('❌ 取消收藏失败: $e');
      state = state.copyWith(error: '取消收藏失败: ${e.toString()}');
    }
  }

  /// ⭐💔 切换收藏状态
  Future<void> toggleFavorites() async {
    if (state.isFavorite) {
      await removeFromFavorites();
    } else {
      await addToFavorites();
    }
  }

  /// ⏰ 设置定时关机
  Future<void> setTimer() async {
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (selectedDid == null) {
      debugPrint('⚠️  未选择设备');
      state = state.copyWith(error: '未选择设备');
      return;
    }

    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      debugPrint('⚠️  API服务未初始化');
      state = state.copyWith(error: 'API服务未初始化');
      return;
    }

    // 循环增加定时：0 -> 10 -> 15 -> 20 -> ... -> 60 -> 0
    int nextMinutes;
    if (state.timerMinutes == 0) {
      nextMinutes = 10; // 初始为 10 分钟
    } else if (state.timerMinutes >= 60) {
      nextMinutes = 0; // 达到 60 分钟后归零（取消定时）
    } else {
      nextMinutes = state.timerMinutes + 5; // 每次增加 5 分钟
    }

    try {
      if (nextMinutes == 0) {
        // 取消定时：发送关机命令（实际上是取消定时）
        debugPrint('⏰ 取消定时关机');
        // 某些服务器可能需要特殊命令来取消，这里先不发送命令
        state = state.copyWith(timerMinutes: 0);
      } else {
        debugPrint('⏰ 设置定时关机: $nextMinutes 分钟');
        await apiService.executeCommand(
          did: selectedDid,
          command: '$nextMinutes分钟后关机',
        );
        state = state.copyWith(timerMinutes: nextMinutes);
        debugPrint('✅ 定时关机已设置: $nextMinutes 分钟');
      }
    } catch (e) {
      debugPrint('❌ 设置定时关机失败: $e');
      state = state.copyWith(error: '设置定时关机失败: ${e.toString()}');
    }
  }

  /// ⏰ 快速取消定时（长按）
  void cancelTimer() {
    debugPrint('⏰ 快速取消定时关机');
    state = state.copyWith(timerMinutes: 0);
  }
}

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) {
    return PlaybackNotifier(ref);
  },
);
