import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/audio_handler_service.dart';
import '../../data/services/local_playback_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

/// 初始化状态
class InitializationState {
  final double progress;
  final String message;
  final bool isCompleted;
  final String? error;

  const InitializationState({
    required this.progress,
    required this.message,
    this.isCompleted = false,
    this.error,
  });

  InitializationState copyWith({
    double? progress,
    String? message,
    bool? isCompleted,
    String? error,
  }) {
    return InitializationState(
      progress: progress ?? this.progress,
      message: message ?? this.message,
      isCompleted: isCompleted ?? this.isCompleted,
      error: error ?? this.error,
    );
  }

}

/// 初始化 Provider
class InitializationNotifier extends StateNotifier<InitializationState> {
  static const platform = MethodChannel('com.hupc.hmusic/splash');

  InitializationNotifier()
      : super(const InitializationState(
          progress: 0.0,
          message: '准备启动...',
        ));

  /// 执行完整的初始化流程
  Future<void> initialize() async {
    try {
      // 步骤 1: 检查基础环境
      state = state.copyWith(progress: 0.15, message: '检查环境...');
      await Future.delayed(const Duration(milliseconds: 200));

      // 步骤 2: 加载本地配置
      state = state.copyWith(progress: 0.3, message: '加载配置...');
      await _writeLeanCloudConfig();
      await Future.delayed(const Duration(milliseconds: 200));

      // 步骤 3: 初始化音频服务（真实操作）
      state = state.copyWith(progress: 0.5, message: '初始化音频服务...');
      await _initializeAudioService();

      // 步骤 4: 请求权限
      state = state.copyWith(progress: 0.7, message: '请求必要权限...');
      await _requestPermissions();

      // 步骤 5: 连接服务
      state = state.copyWith(progress: 0.85, message: '连接服务...');
      await Future.delayed(const Duration(milliseconds: 300));

      // 步骤 6: 准备就绪
      state = state.copyWith(progress: 1.0, message: '准备就绪...', isCompleted: true);
      await Future.delayed(const Duration(milliseconds: 200));

      // 通知原生层隐藏启动屏
      await _hideSplashScreen();
    } catch (e) {
      debugPrint('❌ [Initialization] 初始化失败: $e');
      state = state.copyWith(
        progress: 1.0,
        message: '初始化完成',
        isCompleted: true,
        error: e.toString(),
      );

      // 即使失败也要隐藏启动屏
      await _hideSplashScreen();
    }
  }

  Future<void> _writeLeanCloudConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lc_base_url', 'https://nu0cttse.lc-cn-n1-shared.com');
      await prefs.setString('lc_app_id', 'nu0CtTsesxoThR70g4Vn9Ypk-gzGzoHsz');
      await prefs.setString('lc_app_key', 'WNNq0Z9pluoS8CRnrqu822xl');
    } catch (e) {
      debugPrint('⚠️ [Initialization] 写入 LeanCloud 配置失败: $e');
    }
  }

  /// 隐藏原生启动屏
  Future<void> _hideSplashScreen() async {
    try {
      await platform.invokeMethod('hideSplash');
      debugPrint('✅ [Initialization] 已通知原生层隐藏启动屏');
    } catch (e) {
      debugPrint('⚠️ [Initialization] 隐藏启动屏失败: $e');
    }
  }

  /// 初始化音频服务
  Future<void> _initializeAudioService() async {
    try {
      debugPrint('🎵 [Initialization] 开始初始化 AudioService...');
      final player = AudioPlayer();
      final handler = await AudioService.init(
        builder: () => AudioHandlerService(player: player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.xiaomi.music.channel.audio',
          androidNotificationChannelName: 'HMusic',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: true,
        ),
      );

      if (handler is AudioHandlerService) {
        LocalPlaybackStrategy.sharedAudioHandler = handler;
        debugPrint('✅ [Initialization] AudioService 初始化成功');
      } else {
        debugPrint(
          '❌ [Initialization] AudioService 类型不匹配: ${handler.runtimeType}',
        );
      }
    } catch (e) {
      debugPrint('❌ [Initialization] AudioService 初始化失败: $e');
      rethrow;
    }
  }

  /// 请求必要权限
  Future<void> _requestPermissions() async {
    try {
      debugPrint('📱 [Initialization] 开始请求权限...');

      // iOS平台：先触发网络权限弹窗（国际区iOS需要）
      if (Platform.isIOS) {
        await _triggerNetworkPermission();
      }

      // 请求通知权限
      debugPrint('📱 [Initialization] 请求通知权限...');
      final notificationStatus = await Permission.notification.request();
      debugPrint('📱 [Initialization] 通知权限状态: $notificationStatus');

      // iOS 14+ 本地网络权限会在首次访问时自动弹出
      // 不需要手动请求
      debugPrint('📱 [Initialization] iOS 本地网络权限将在首次网络访问时自动弹出');

      // 检查当前权限状态
      final notification = await Permission.notification.status;
      debugPrint('📱 [Initialization] 最终权限状态:');
      debugPrint('   - 通知: $notification');

    } catch (e, stackTrace) {
      debugPrint('⚠️ [Initialization] 权限请求失败: $e');
      debugPrint('⚠️ [Initialization] 堆栈跟踪: $stackTrace');
      // 权限失败不影响继续
    }
  }

  /// 触发iOS网络权限弹窗（国际区iOS需要）
  /// 通过发起一个简单的网络请求来触发系统的WiFi/蜂窝数据权限对话框
  Future<void> _triggerNetworkPermission() async {
    try {
      debugPrint('🌐 [Initialization] 触发iOS网络权限检查...');

      // 创建一个简单的HTTP请求来触发网络权限弹窗
      // 使用一个可靠的轻量级端点
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);

      try {
        final request = await client.getUrl(Uri.parse('https://www.apple.com/library/test/success.html'));
        final response = await request.close();
        debugPrint('🌐 [Initialization] 网络连接成功，状态码: ${response.statusCode}');
        await response.drain();
      } catch (e) {
        debugPrint('🌐 [Initialization] 网络请求失败（可能是用户拒绝权限或网络不可用）: $e');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('⚠️ [Initialization] 触发网络权限失败: $e');
    }
  }
}

/// 初始化状态 Provider
final initializationProvider =
    StateNotifierProvider<InitializationNotifier, InitializationState>(
  (ref) => InitializationNotifier(),
);
