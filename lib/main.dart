import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'app_router.dart';
import 'presentation/providers/js_proxy_provider.dart';
import 'presentation/providers/usage_stats_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/audio_proxy_provider.dart';
import 'data/services/audio_proxy_server.dart';
import 'core/utils/app_logger.dart';
import 'core/constants/app_constants.dart';
import 'dart:async';

// 🎯 全局代理服务器实例
AudioProxyServer? _globalProxyServer;

void main() {
  // 🎯 关键修复：所有初始化和 runApp 必须在同一个 zone 中
  // 避免 Zone mismatch 错误
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await AppLogger.init();

      try {
        // warm-up by touching singleton instance
        // ignore: unnecessary_statements
        DefaultCacheManager();
      } catch (_) {}

      // 🎯 启动代理服务器（用于音频流转发）
      await _startProxyServer();

      // 初始化SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // 禁用Flutter调试边框和调试信息
      debugPaintSizeEnabled = false;
      debugRepaintRainbowEnabled = false;
      debugPaintLayerBordersEnabled = false;

      // 配置系统UI样式。导航栏保持透明，由 Flutter 根背景铺到底部手势区。
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // 添加全局错误处理
      FlutterError.onError = (FlutterErrorDetails details) {
        final errorString = details.exception.toString();

        // 过滤掉已知的Flutter问题和非关键错误
        if (errorString.contains('mouse_tracker.dart') ||
            errorString.contains('_debugDuringDeviceUpdate') ||
            errorString.contains(
              'Cannot hit test a render box that has never been laid out',
            ) ||
            errorString.contains('Cannot hit test a render box with no size') ||
            errorString.contains('RenderBox was not laid out') ||
            errorString.contains('_RenderDeferredLayoutBox') ||
            errorString.contains('!_debugDoingThisLayout') ||
            errorString.contains('DropdownButtonFormField') &&
                errorString.contains('performLayout') ||
            errorString.contains('RenderSemanticsAnnotations') &&
                errorString.contains('size: MISSING')) {
          // 忽略这些已知的Flutter Web问题和布局问题
          return;
        }

        AppLogger.instance.e(
          'FlutterError',
          error: details.exception,
          stack: details.stack,
          tag: 'Flutter',
        );
        // 其他错误正常处理
        FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.instance.e(
          'PlatformError',
          error: error,
          stack: stack,
          tag: 'Platform',
        );
        return true;
      };

      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        originalDebugPrint(message, wrapWidth: wrapWidth);
      };

      await _logStartupContext(prefs);
      AppLogger.instance.i('App start', tag: 'App');
      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            usageStatsProvider.overrideWith((ref) => UsageStatsNotifier(prefs)),
            // 🎯 提供全局代理服务器实例
            audioProxyServerProvider.overrideWithValue(_globalProxyServer),
          ],
          child: const MyApp(),
        ),
      );
    },
    (error, stack) {
      AppLogger.instance.e(
        'ZoneError',
        error: error,
        stack: stack,
        tag: 'Zone',
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        AppLogger.instance.i(line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _logStartupContext(SharedPreferences prefs) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final installId = await _ensureInstallId(prefs);
    final deviceInfo = await _collectDeviceInfo();
    final playbackMode = prefs.getString('playback_mode') ?? 'xiaomusic';
    final xiaomusicUser = _maskUserIdentifier(
      prefs.getString(AppConstants.prefsUsername),
    );
    final directModeAccount = _maskUserIdentifier(
      prefs.getString('direct_mode_account'),
    );

    final context = <String, dynamic>{
      'app_name': packageInfo.appName,
      'app_version': packageInfo.version,
      'build_number': packageInfo.buildNumber,
      'package_name': packageInfo.packageName,
      'platform': Platform.operatingSystem,
      'platform_version': Platform.operatingSystemVersion,
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'timezone': DateTime.now().timeZoneName,
      'install_id': installId,
      'playback_mode': playbackMode,
      'xiaomusic_user': xiaomusicUser ?? '',
      'direct_mode_account': directModeAccount ?? '',
      ...deviceInfo,
    };

    await AppLogger.instance.saveSessionContext(context);
    AppLogger.instance.i('session_context_begin', tag: 'Session');
    for (final entry in context.entries) {
      AppLogger.instance.i('${entry.key}: ${entry.value}', tag: 'Session');
    }
    AppLogger.instance.i(
      'session_context_json=${jsonEncode(context)}',
      tag: 'Session',
    );
    AppLogger.instance.i('session_context_end', tag: 'Session');
  } catch (e, stack) {
    AppLogger.instance.e(
      'SessionContextLogFailed',
      error: e,
      stack: stack,
      tag: 'Session',
    );
  }
}

Future<String> _ensureInstallId(SharedPreferences prefs) async {
  const key = 'app_install_id';
  final existing = prefs.getString(key);
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }
  final generated = const Uuid().v4();
  await prefs.setString(key, generated);
  return generated;
}

String? _maskUserIdentifier(String? raw) {
  if (raw == null) {
    return null;
  }
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }

  if (value.contains('@')) {
    final parts = value.split('@');
    final name = parts.first;
    final domain = parts.length > 1 ? parts.sublist(1).join('@') : '';
    final maskedName =
        name.length <= 2 ? '${name[0]}*' : '${name.substring(0, 2)}***';
    return domain.isEmpty ? maskedName : '$maskedName@$domain';
  }

  if (RegExp(r'^\d{11}$').hasMatch(value)) {
    return '${value.substring(0, 3)}****${value.substring(7)}';
  }

  if (value.length <= 2) {
    return '${value[0]}*';
  }

  if (value.length <= 6) {
    return '${value.substring(0, 1)}***';
  }

  return '${value.substring(0, 2)}***${value.substring(value.length - 2)}';
}

Future<Map<String, String>> _collectDeviceInfo() async {
  final plugin = DeviceInfoPlugin();

  try {
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return {
        'device_model': info.model,
        'device_name': info.name,
        'device_identifier': info.utsname.machine,
        'device_physical': info.isPhysicalDevice.toString(),
        'os_name': info.systemName,
        'os_version': info.systemVersion,
      };
    }

    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return {
        'device_brand': info.brand,
        'device_model': info.model,
        'device_product': info.product,
        'device_physical': info.isPhysicalDevice.toString(),
        'os_release': info.version.release,
        'sdk_int': info.version.sdkInt.toString(),
      };
    }

    if (Platform.isMacOS) {
      final info = await plugin.macOsInfo;
      return {
        'device_model': info.model,
        'os_release': info.osRelease,
        'arch': info.arch,
      };
    }

    if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      return {
        'device_name': info.computerName,
        'os_release': info.releaseId,
        'display_version': info.displayVersion,
      };
    }

    if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      return {
        'device_name': info.name,
        'version': info.version ?? '',
        'id': info.id,
      };
    }
  } catch (e) {
    return {'device_info_error': e.toString()};
  }

  return {};
}

/// 🎯 启动代理服务器
/// 用于转发音频流，解决小爱音箱无法直接访问某些CDN的问题
Future<void> _startProxyServer() async {
  try {
    debugPrint('🚀 [ProxyServer] 正在启动代理服务器...');

    _globalProxyServer = AudioProxyServer();
    final success = await _globalProxyServer!.start(port: 8090);

    if (success) {
      debugPrint('✅ [ProxyServer] 代理服务器启动成功: ${_globalProxyServer!.serverUrl}');
    } else {
      debugPrint('❌ [ProxyServer] 代理服务器启动失败');
      _globalProxyServer = null;
    }
  } catch (e) {
    debugPrint('❌ [ProxyServer] 代理服务器启动异常: $e');
    _globalProxyServer = null;
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = const Color(0xFF21B0A5); // HMusic Cyan
    final appBarToolbarHeight = Platform.isIOS ? 44.0 : kToolbarHeight;
    final themeMode = ref.watch(themeModeProvider);

    final lightScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
    );

    final darkScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      primary: seed,
      surface: const Color(0xFF090E17), // Deep Navy Blue background
    );

    // 在应用构建阶段预热JS代理（读取provider以触发初始化和自动加载）
    ref.read(jsProxyProvider);

    return MaterialApp.router(
      title: 'HMusic',
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7F9),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: appBarToolbarHeight,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          showDragHandle: true,
          dragHandleSize: const Size(40, 5),
        ),
        dialogTheme: DialogThemeData(
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: const Color(0xFF090E17),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: appBarToolbarHeight,
          scrolledUnderElevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF090E17),
          contentTextStyle: const TextStyle(color: Colors.white),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: const Color(0xFF090E17),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          showDragHandle: true,
          dragHandleColor: Colors.white.withOpacity(0.2),
          dragHandleSize: const Size(40, 5),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF090E17),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF090E17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
        ),
      ),
      routerConfig: ref.read(appRouterProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDarkMode = theme.brightness == Brightness.dark;
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDarkMode ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isDarkMode ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        );

        // 根背景必须铺满整个 FlutterView；透明系统导航栏才不会露出黑底。
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: SizedBox.expand(
              child: MediaQuery(
                data: MediaQuery.of(context),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
