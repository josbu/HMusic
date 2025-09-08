import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/playing_music.dart';
import 'dio_provider.dart';
import 'device_provider.dart';

enum PlayMode {
  sequence, // 顺序播放
  loop, // 循环播放
  random, // 随机播放
  single, // 单曲循环
}

extension PlayModeExtension on PlayMode {
  String get displayName {
    switch (this) {
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.loop:
        return '循环播放';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.single:
        return '单曲循环';
    }
  }

  String get command {
    switch (this) {
      case PlayMode.sequence:
        return 'sequence';
      case PlayMode.loop:
        return 'loop';
      case PlayMode.random:
        return 'random';
      case PlayMode.single:
        return 'single';
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

  const PlaybackState({
    this.currentMusic,
    this.volume = 0, // Initial UI shows volume at 0 before server data arrives
    this.isLoading = false,
    this.error,
    this.playMode = PlayMode.sequence,
    this.hasLoaded = false,
  });

  PlaybackState copyWith({
    PlayingMusic? currentMusic,
    int? volume,
    bool? isLoading,
    String? error,
    PlayMode? playMode,
    bool? hasLoaded,
  }) {
    return PlaybackState(
      currentMusic: currentMusic ?? this.currentMusic,
      volume: volume ?? this.volume,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      playMode: playMode ?? this.playMode,
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  final Ref ref;
  bool _isInitialized = false;
  Timer? _statusRefreshTimer;
  Timer? _localProgressTimer;
  DateTime? _lastUpdateTime;
  // 保存服务器最后返回的原始进度，用于本地预测基准
  int? _lastServerOffset;

  PlaybackNotifier(this.ref)
    : super(const PlaybackState(isLoading: false, hasLoaded: false)) {
    // 禁用自动初始化，避免在未登录时进行网络请求
    // 需要用户手动触发初始化
    debugPrint('PlaybackProvider: 自动初始化已禁用，等待用户手动触发');
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

      print('🎵 最终播放状态: ${currentMusic?.curMusic ?? "无"}');
      print('🎵 当前音量: $volume');

      // 进度同步校准机制
      bool needsRecalibration = false;
      if (state.currentMusic != null && currentMusic != null) {
        final localOffset = state.currentMusic!.offset ?? 0;
        final serverOffset = currentMusic.offset ?? 0;
        final offsetDiff = (serverOffset - localOffset).abs();
        
        // 如果差异超过2秒，说明需要重新校准本地时间基准
        if (offsetDiff > 2) {
          needsRecalibration = true;
          print('🔄 检测到进度跳跃，差异: ${offsetDiff}秒，重新校准时间基准');
        } else if (offsetDiff > 0) {
          print('🔄 平滑同步进度，差异: ${offsetDiff}秒');
        }
      }
      
      state = state.copyWith(
        currentMusic: currentMusic,
        volume: volume,
        error: null,
        isLoading: silent ? state.isLoading : false,
        hasLoaded: true,
      );
      
      // 保存服务器返回的原始进度作为预测基准
      _lastServerOffset = currentMusic?.offset ?? 0;
      
      // 重新校准：当服务器进度与本地预测差异过大时，重置时间基准
      // 这样本地预测就会从服务器的当前进度开始重新计算
      _lastUpdateTime = DateTime.now();
      if (needsRecalibration) {
        print('⏰ 时间基准已重置，本地预测将从服务器进度 ${_lastServerOffset}秒 开始');
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
        duration: state.currentMusic!.duration, ret: '',
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
      // 避免按钮长时间 loading，采用轻量刷新
      state = state.copyWith(isLoading: false);

      final isPlaying = state.currentMusic?.isPlaying ?? false;

      print('🎵 执行播放控制命令: ${isPlaying ? "暂停" : "播放歌曲"}');

      if (isPlaying) {
        await apiService.pauseMusic(did: selectedDid);
      } else {
        await apiService.resumeMusic(did: selectedDid);
      }

      // 等待命令执行后刷新状态
      Future.delayed(
        const Duration(milliseconds: 1000),
        () => refreshStatus(silent: true),
      );

      // 不把按钮锁在 loading
    } catch (e) {
      print('🎵 播放控制失败: $e');
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

  // 选设备交由 deviceProvider

  Future<void> switchPlayMode() async {
    final apiService = ref.read(apiServiceProvider);
    final selectedDid = ref.read(deviceProvider).selectedDeviceId;
    if (apiService == null || selectedDid == null) return;

    // 循环切换播放模式
    final currentMode = state.playMode;
    final nextMode =
        PlayMode.values[(currentMode.index + 1) % PlayMode.values.length];

    try {
      state = state.copyWith(isLoading: true);

      // 使用服务器配置中的正确命令名称
      String command;
      switch (nextMode) {
        case PlayMode.sequence:
          command = 'set_play_type_seq'; // 顺序播放
          break;
        case PlayMode.loop:
          command = 'set_play_type_all'; // 全部循环
          break;
        case PlayMode.single:
          command = 'set_play_type_one'; // 单曲循环
          break;
        case PlayMode.random:
          command = 'set_play_type_rnd'; // 随机播放
          break;
      }

      print('🎵 切换播放模式: ${nextMode.displayName} (命令: $command)');

      await apiService.executeCommand(did: selectedDid, command: command);

      state = state.copyWith(playMode: nextMode, isLoading: false);

      // 延迟刷新状态以确认模式切换
      Future.delayed(
        const Duration(milliseconds: 500),
        () => refreshStatus(silent: true),
      );
    } catch (e) {
      print('🎵 播放模式切换失败: $e');
      state = state.copyWith(
        isLoading: false,
        error: '播放模式切换失败: ${e.toString()}',
      );
    }
  }

  void _startProgressTimer(bool isPlaying) {
    _statusRefreshTimer?.cancel();
    _localProgressTimer?.cancel();

    if (isPlaying && state.currentMusic != null) {
      // 每5秒从服务器获取真实进度（减少频率避免跳跃）
      _statusRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        refreshStatus(silent: true);
      });
      
      // 每500ms更新本地进度预测（降低频率减少抖动）
      _localProgressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _updateLocalProgress();
      });
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
    final elapsedMs = now.difference(_lastUpdateTime!).inMilliseconds;
    
    // 基于服务器最后返回的原始进度进行预测
    final predictedOffset = _lastServerOffset! + (elapsedMs / 1000).floor();
    final duration = state.currentMusic!.duration ?? 0;
    
    // 确保进度不超过总时长且有实际增长
    if (predictedOffset < duration && predictedOffset > _lastServerOffset!) {
      final updatedMusic = PlayingMusic(
        ret: state.currentMusic!.ret,
        curMusic: state.currentMusic!.curMusic,
        curPlaylist: state.currentMusic!.curPlaylist,
        isPlaying: state.currentMusic!.isPlaying,
        offset: predictedOffset,
        duration: state.currentMusic!.duration,
      );
      
      state = state.copyWith(currentMusic: updatedMusic);
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>(
  (ref) {
    return PlaybackNotifier(ref);
  },
);
