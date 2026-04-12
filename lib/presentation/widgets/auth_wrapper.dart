import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/login_page.dart';
import '../pages/direct_mode_login_page.dart';
import '../pages/playback_mode_selection_page.dart';
import '../pages/main_page.dart';
import '../providers/auth_provider.dart';
import '../providers/js_proxy_provider.dart';
import '../providers/source_settings_provider.dart';
import '../providers/js_script_manager_provider.dart';
import '../providers/initialization_provider.dart';
import '../pages/update_page.dart';
import '../providers/update_provider.dart';
import '../providers/direct_mode_provider.dart';

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _jsPreloadAttempted = false;
  bool _isFirstFrame = true;
  bool _updateChecked = false;
  bool _initTriggered = false;
  @override
  void initState() {
    super.initState();

    bool isTest = false;
    assert(() {
      isTest = true;
      return true;
    }());
    if (isTest) {
      _updateChecked = true;
      return;
    }

    // ✅ iOS已在原生层触发网络权限，这里直接检查更新
    print('[AuthWrapper] 🔍 开始初始化流程...');
    _checkForUpdates();

    // 使用postFrameCallback确保在第一帧渲染后执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isFirstFrame = false;
      _triggerPostUpdateInit();
    });
  }

  void _triggerPostUpdateInit() {
    if (_initTriggered) return;
    _initTriggered = true;
    // 初始化 AudioService（后台执行，不阻塞UI）
    _initializeAudioService();
    _attemptJsPreload();
  }

  /// 检查应用更新
  Future<void> _checkForUpdates() async {
    if (_updateChecked) return;

    print('[AuthWrapper] 🔍 开始检查更新...');

    try {
      // 先写入LeanCloud配置（更新检查需要这些配置）
      await _writeLeanCloudConfig();

      final upd = ref.read(updateProvider.notifier);
      await upd.check();

      final state = ref.read(updateProvider);
      print('[AuthWrapper] 📋 更新检查完成:');
      print('  - needsUpdate: ${state.needsUpdate}');
      print('  - targetVersion: ${state.targetVersion}');
      print('  - force: ${state.force}');
    } catch (e) {
      print('[AuthWrapper] ⚠️ 版本检查失败: $e');
    } finally {
      // 更新检查完成，触发重新构建
      if (mounted) {
        print('[AuthWrapper] ✅ 更新检查完成，触发重新构建');
        setState(() {
          _updateChecked = true;
        });
      }
    }
  }

  /// 写入LeanCloud配置到SharedPreferences
  Future<void> _writeLeanCloudConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lc_base_url', 'https://nu0cttse.lc-cn-n1-shared.com');
      await prefs.setString('lc_app_id', 'nu0CtTsesxoThR70g4Vn9Ypk-gzGzoHsz');
      await prefs.setString('lc_app_key', 'WNNq0Z9pluoS8CRnrqu822xl');
      print('[AuthWrapper] ✅ LeanCloud配置已写入');
    } catch (e) {
      print('[AuthWrapper] ⚠️ 写入LeanCloud配置失败: $e');
    }
  }

  /// 初始化音频服务
  Future<void> _initializeAudioService() async {
    try {
      // 等待更新检查完成
      while (!_updateChecked) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 如果需要更新，则不执行后续初始化
      final s = ref.read(updateProvider);
      if (s.needsUpdate) {
        return;
      }

      // 执行初始化
      final initNotifier = ref.read(initializationProvider.notifier);
      await initNotifier.initialize();

      // 初始化完成后,隐藏原生启动屏将在 initialize() 内部自动调用
    } catch (e) {
      print('[AuthWrapper] ❌ 音频服务初始化失败: $e');
    }
  }

  /// 尝试预加载JS脚本（后台执行，不阻塞UI）
  Future<void> _attemptJsPreload() async {
    // 避免重复预加载
    if (_jsPreloadAttempted) return;
    _jsPreloadAttempted = true;

    final authState = ref.read(authProvider);

    // 只在已登录状态下预加载
    if (authState is! AuthAuthenticated) {
      print('[AuthWrapper] ℹ️ 未登录，跳过JS预加载');
      return;
    }

    try {
      // ✨ 关键修复：等待设置加载完成
      final settingsNotifier = ref.read(sourceSettingsProvider.notifier);
      int waitCount = 0;
      while (!settingsNotifier.isLoaded && waitCount < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      if (!settingsNotifier.isLoaded) {
        print('[AuthWrapper] ⚠️ 设置加载超时，跳过预加载');
        return;
      }

      // 现在设置已经加载完成，可以安全读取
      final settings = ref.read(sourceSettingsProvider);
      print('[AuthWrapper] 📋 音源设置: primarySource=${settings.primarySource}');

      if (settings.primarySource != 'js_external') {
        print('[AuthWrapper] ℹ️ 未启用JS音源，跳过预加载');
        return;
      }

      // 获取选中的脚本
      final scriptManager = ref.read(jsScriptManagerProvider.notifier);
      final selectedScript = scriptManager.selectedScript;

      if (selectedScript == null) {
        print('[AuthWrapper] ⚠️ 未选择JS脚本，跳过预加载');
        return;
      }

      // 🎯 后台预加载JS脚本（只预加载实际使用的 jsProxyProvider）
      print('[AuthWrapper] 🚀 开始预加载JS脚本: ${selectedScript.name}');

      try {
        final jsProxyNotifier = ref.read(jsProxyProvider.notifier);
        final success = await jsProxyNotifier.loadScriptByScript(
          selectedScript,
        );

        if (success) {
          // 获取加载后的状态
          final jsProxyState = ref.read(jsProxyProvider);
          print('[AuthWrapper] ✅ JS脚本预加载完成');
          print(
            '[AuthWrapper] 📋 支持的音源: ${jsProxyState.supportedSources.keys.join(", ")}',
          );
        } else {
          print('[AuthWrapper] ⚠️ JS脚本预加载失败');
        }
      } catch (e) {
        print('[AuthWrapper] ❌ JS脚本预加载异常: $e');
      }
    } catch (e) {
      print('[AuthWrapper] ❌ JS预加载异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final updState = ref.watch(updateProvider);
    // 🎯 新增：监听当前播放模式和直连模式状态
    final playbackMode = ref.watch(playbackModeProvider);
    final directModeState = ref.watch(directModeProvider);
    final initState = ref.watch(initializationProvider); // 🎯 监听初始化状态

    print('[AuthWrapper] 🎨 build - _updateChecked: $_updateChecked, needsUpdate: ${updState.needsUpdate}');
    print('[AuthWrapper] 🎯 当前模式: $playbackMode, authState: ${authState.runtimeType}, directState: ${directModeState.runtimeType}');
    print('[AuthWrapper] 🎯 初始化状态: progress=${initState.progress}, completed=${initState.isCompleted}');

    // 等待更新检查完成后再决定显示什么
    // 如果还在检查中，显示空白页面或加载指示器
    if (!_updateChecked) {
      print('[AuthWrapper] ⏳ 显示加载指示器（等待更新检查）');
      return const Scaffold(
        backgroundColor: Color(0xFF090E17),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (updState.needsUpdate) {
      print('[AuthWrapper] 🔄 显示更新页面');
      return UpdatePage(
        title: updState.title,
        message: updState.message,
        downloadUrl: updState.downloadUrl,
        force: updState.force,
        targetVersion: updState.targetVersion,
      );
    }

    // 🎯 等待初始化完成（避免直连模式静默登录时显示登录页）
    if (!initState.isCompleted) {
      print('[AuthWrapper] ⏳ 等待初始化完成...');
      if (_updateChecked && !_initTriggered) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _triggerPostUpdateInit();
        });
      }
      return const Scaffold(
        backgroundColor: Color(0xFF090E17),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 监听登录状态变化，成功登录后重置预加载标记
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous is! AuthAuthenticated && next is AuthAuthenticated) {
        print('[AuthWrapper] 🔑 检测到登录成功，准备预加载JS');
        _jsPreloadAttempted = false;

        // 延迟一小段时间再预加载，让其他Provider先初始化
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _attemptJsPreload();
          }
        });
      }
    });

    // 🎯 优先检查登录状态：已登录直接进入主页（支持自动登录场景）
    if (playbackMode == PlaybackMode.xiaomusic && authState is AuthAuthenticated) {
      return const MainPage();
    }
    if (playbackMode == PlaybackMode.miIoTDirect && directModeState is DirectModeAuthenticated) {
      return const MainPage();
    }

    // 🎯 未登录：检查当前会话是否已选择模式
    // _hasSelectedMode 仅在用户手动选择时为 true，APP 重启后为 false
    final modeNotifier = ref.read(playbackModeProvider.notifier);
    if (!modeNotifier.hasSelectedMode) {
      return const PlaybackModeSelectionPage();
    }

    // 🎯 当前会话已选模式但未登录 → 展示对应登录页
    if (playbackMode == PlaybackMode.xiaomusic) {
      return const LoginPage();
    } else {
      return const DirectModeLoginPage();
    }
  }
}
