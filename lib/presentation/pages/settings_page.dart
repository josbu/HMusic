import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../providers/auth_provider.dart';
import '../providers/music_library_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/source_settings_provider.dart';
import '../widgets/app_snackbar.dart';
import '../providers/direct_mode_provider.dart';
import '../providers/theme_provider.dart';
import '../../core/utils/app_logger.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;
    final versionText =
        buildNumber.isNotEmpty ? '$version ($buildNumber)' : version;
    if (mounted) {
      setState(() {
        _appVersion = versionText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;
    final settings = ref.watch(sourceSettingsProvider);
    final playbackMode = ref.watch(playbackModeProvider); // 🎯 获取当前播放模式

    // 🎯 判断是否为直连模式
    final isDirectMode = playbackMode == PlaybackMode.miIoTDirect;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 支持分组
          _buildSettingsGroup(
            context,
            title: '支持',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.favorite_rounded,
                title: '赞赏支持',
                subtitle: '支持开发者继续维护',
                onTap: () => context.push('/settings/sponsor'),
                onSurface: onSurface,
                iconColor: const Color(0xFFEF4444).withOpacity(0.8),
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.bug_report_rounded,
                title: '导出日志',
                subtitle: '保存问题日志并发送给开发者',
                onTap: () => _exportLogs(context),
                onSurface: onSurface,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 外观与播放分组
          _buildSettingsGroup(
            context,
            title: '外观与播放',
            children: [
              _buildThemeModeItem(context, onSurface),
              _buildSettingsItem(
                context: context,
                icon: Icons.source_rounded,
                title: '音源与搜索设置',
                subtitle: '配置音乐搜索和播放源优先级',
                onTap: () => context.push('/settings/source'),
                onSurface: onSurface,
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.record_voice_over_rounded,
                title: 'TTS文字转语音',
                subtitle: '配置语音合成设置',
                onTap: () => context.push('/settings/tts'),
                onSurface: onSurface,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 播放模式分组
          _buildSettingsGroup(
            context,
            title: '播放模式',
            children: [_buildPlaybackModeItem(context, onSurface)],
          ),

          const SizedBox(height: 24),

          // 🎯 服务器设置分组（仅 xiaomusic 模式显示）
          if (!isDirectMode) ...[
            _buildSettingsGroup(
              context,
              title: '服务器设置',
              children: [
                _buildSettingsItem(
                  context: context,
                  icon: Icons.http_rounded,
                  title: '服务器账号设置',
                  subtitle: '配置服务器连接信息',
                  onTap: () => context.push('/settings/server'),
                  onSurface: onSurface,
                ),
                _buildSettingsItem(
                  context: context,
                  icon: Icons.cloud_upload_rounded,
                  title: 'SCP 上传设置',
                  subtitle: '配置文件上传方式',
                  onTap: () => context.push('/settings/ssh'),
                  onSurface: onSurface,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // 下载和工具分组
          _buildSettingsGroup(
            context,
            title: '下载与工具',
            children: [
              // 默认下载音质选择
              _buildQualitySelector(context, ref, settings, onSurface),
              // 本地下载路径显示
              _buildDownloadPathDisplay(context, onSurface),
              // 🎯 从链接下载（仅 xiaomusic 模式显示）
              if (!isDirectMode)
                _buildSettingsItem(
                  context: context,
                  icon: Icons.link_rounded,
                  title: '从链接下载',
                  subtitle: '通过链接下载音乐',
                  onTap: () => _showDownloadFromLinkDialog(context, ref),
                  onSurface: onSurface,
                ),
              // 🎯 下载任务（仅 xiaomusic 模式显示）
              if (!isDirectMode)
                _buildSettingsItem(
                  context: context,
                  icon: Icons.download_rounded,
                  title: '下载任务',
                  subtitle: '查看和管理下载任务',
                  onTap: () => context.push('/downloads'),
                  onSurface: onSurface,
                ),
              _buildSettingsItem(
                context: context,
                icon: Icons.code_rounded,
                title: 'JS代理测试',
                subtitle: '测试JavaScript代理功能',
                onTap: () => context.push('/js-proxy-test'),
                onSurface: onSurface,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 关于分组
          _buildSettingsGroup(
            context,
            title: '关于',
            children: [
              _buildAppInfo(context, onSurface),
              _buildDeveloperInfo(context, onSurface),
            ],
          ),

          const SizedBox(height: 24),

          // 账户操作
          _buildSettingsGroup(
            context,
            title: '账户',
            children: [
              _buildSettingsItem(
                context: context,
                icon: Icons.logout_rounded,
                title: '退出登录',
                subtitle: '注销当前账户',
                onTap: () => _showLogoutDialog(context, ref),
                onSurface: onSurface,
                iconColor: const Color(0xFFEF4444).withOpacity(0.8),
              ),
              _buildSettingsItem(
                context: context,
                icon: Icons.swap_horiz_rounded,
                title: '切换模式',
                subtitle: '切换到其他播放模式',
                onTap: () => _showSwitchModeDialog(context, ref),
                onSurface: onSurface,
                iconColor: const Color(0xFFF59E0B).withOpacity(0.8),
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 应用信息展示
  Widget _buildAppInfo(BuildContext context, Color onSurface) {
    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Icon(
          Icons.info_outline_rounded,
          color: onSurface.withOpacity(0.7),
          size: 24,
        ),
      ),
      title: Text(
        '应用版本',
        style: TextStyle(
          color: onSurface.withOpacity(0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _appVersion.isEmpty ? '加载中...' : _appVersion,
        style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  /// 开发者信息展示
  Widget _buildDeveloperInfo(BuildContext context, Color onSurface) {
    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Icon(
          Icons.person_rounded,
          color: onSurface.withOpacity(0.7),
          size: 24,
        ),
      ),
      title: Text(
        '开发者',
        style: TextStyle(
          color: onSurface.withOpacity(0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '胡九九',
        style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outline.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color onSurface,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Icon(
          icon,
          color: iconColor ?? onSurface.withOpacity(0.7),
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: onSurface.withOpacity(0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: onSurface.withOpacity(0.4),
        size: 20,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  /// 播放模式切换项
  Widget _buildThemeModeItem(BuildContext context, Color onSurface) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _buildSettingsItem(
      context: context,
      icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
      title: '应用主题',
      subtitle: themeMode == ThemeMode.system
          ? '跟随系统'
          : (themeMode == ThemeMode.dark ? '深色模式' : '浅色模式'),
      onSurface: onSurface,
      onTap: () {
        showModalBottomSheet(
          context: context,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      '选择应用主题',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('跟随系统'),
                    value: ThemeMode.system,
                    groupValue: themeMode,
                    onChanged: (mode) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode!);
                      Navigator.pop(context);
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('浅色模式'),
                    value: ThemeMode.light,
                    groupValue: themeMode,
                    onChanged: (mode) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode!);
                      Navigator.pop(context);
                    },
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('深色模式'),
                    value: ThemeMode.dark,
                    groupValue: themeMode,
                    onChanged: (mode) {
                      ref.read(themeModeProvider.notifier).setThemeMode(mode!);
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaybackModeItem(BuildContext context, Color onSurface) {
    final playbackMode = ref.watch(playbackModeProvider);
    final directModeState = ref.watch(directModeProvider);

    // 确定当前模式的显示文本和状态
    String modeText;
    String statusText;
    IconData modeIcon;
    Color iconColor;

    if (playbackMode == PlaybackMode.xiaomusic) {
      modeText = 'xiaomusic 模式';
      statusText = '通过服务器控制小爱音箱';
      modeIcon = Icons.dns;
      iconColor = const Color(0xFF21B0A5);
    } else {
      modeText = '直连模式';
      if (directModeState is DirectModeAuthenticated) {
        statusText = '已登录 · ${directModeState.devices.length} 个设备';
        iconColor = const Color(0xFF21B0A5);
      } else {
        statusText = '未登录';
        iconColor = Colors.white54;
      }
      modeIcon = Icons.phone_android;
    }

    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Icon(
          modeIcon,
          color: iconColor,
          size: 24,
        ),
      ),
      title: Text(
        modeText,
        style: TextStyle(
          color: onSurface.withOpacity(0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        statusText,
        style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: onSurface.withOpacity(0.4),
        size: 20,
      ),
      onTap: () => _showPlaybackModeSwitchDialog(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  /// 显示播放模式切换对话框
  Future<void> _showPlaybackModeSwitchDialog(BuildContext context) async {
    final playbackMode = ref.read(playbackModeProvider);

    final result = await showDialog<PlaybackMode>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('切换播放模式'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeOption(
                  context: context,
                  mode: PlaybackMode.xiaomusic,
                  title: 'xiaomusic 模式',
                  subtitle: '通过服务器控制，功能完整',
                  icon: Icons.dns,
                  color: const Color(0xFF21B0A5),
                  isSelected: playbackMode == PlaybackMode.xiaomusic,
                ),
                const SizedBox(height: 12),
                _buildModeOption(
                  context: context,
                  mode: PlaybackMode.miIoTDirect,
                  title: '直连模式',
                  subtitle: '直接控制，无需服务器',
                  icon: Icons.phone_android,
                  color: const Color(0xFF21B0A5),
                  isSelected: playbackMode == PlaybackMode.miIoTDirect,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
    );

    if (result != null && result != playbackMode) {
      // 🎯 切换模式逻辑优化：保留所有模式的登录状态,不互相退出
      final targetMode = result;
      final authState = ref.read(authProvider);
      final directState = ref.read(directModeProvider);

      // 更新播放模式
      ref.read(playbackModeProvider.notifier).setMode(targetMode);

      if (mounted) {
        String message;

        if (targetMode == PlaybackMode.xiaomusic) {
          // 切换到 xiaomusic 模式
          // 🎯 不退出直连模式登录,保留登录状态以便下次切换回来时使用
          if (authState is AuthAuthenticated) {
            message = '已切换到 xiaomusic 模式';
          } else {
            message = '已切换到 xiaomusic 模式，请登录';
          }
        } else {
          // 切换到直连模式
          // 🎯 不退出 xiaomusic 模式登录,保留登录状态以便下次切换回来时使用
          if (directState is DirectModeAuthenticated) {
            message = '已切换到直连模式';
          } else {
            message = '已切换到直连模式，请登录';
          }
        }

        AppSnackBar.showSuccess(context, message);

        // 🎯 统一跳转到根路由,让 AuthWrapper 根据模式和登录状态自动决定显示什么页面
        if (mounted) {
          context.go('/');
        }
      }
    }
  }

  /// 构建模式选项
  Widget _buildModeOption({
    required BuildContext context,
    required PlaybackMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : Colors.white54.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? color.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _showDownloadFromLinkDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final singleNameController = TextEditingController();
    final singleUrlController = TextEditingController();
    final listNameController = TextEditingController();
    final listUrlController = TextEditingController();

    Map<String, String>? result;

    result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: const Text('从链接下载到服务器'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabBar(tabs: [Tab(text: '单曲'), Tab(text: '合集')]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: TabBarView(
                      children: [
                        // 单曲
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: singleNameController,
                              decoration: const InputDecoration(
                                labelText: '歌曲名',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: singleUrlController,
                              decoration: const InputDecoration(
                                labelText: '歌曲链接 URL',
                                hintText: '例如：https://example.com/music.mp3',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                        // 合集
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: listNameController,
                              decoration: const InputDecoration(
                                labelText: '保存目录名（播放列表名）',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: listUrlController,
                              decoration: const InputDecoration(
                                labelText: '合集/歌单链接 URL',
                                hintText: '例如：https://example.com/playlist',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final controller = DefaultTabController.of(context);
                  final isPlaylist = (controller.index) == 1;
                  if (isPlaylist) {
                    final name = listNameController.text.trim();
                    final url = listUrlController.text.trim();
                    if (name.isEmpty || url.isEmpty) return;
                    Navigator.pop<Map<String, String>>(context, {
                      'type': 'playlist',
                      'name': name,
                      'url': url,
                    });
                  } else {
                    final name = singleNameController.text.trim();
                    final url = singleUrlController.text.trim();
                    if (name.isEmpty || url.isEmpty) return;
                    Navigator.pop<Map<String, String>>(context, {
                      'type': 'single',
                      'name': name,
                      'url': url,
                    });
                  }
                },
                child: const Text('下载'),
              ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || result == null) return;

    try {
      if (result['type'] == 'single') {
        await ref
            .read(musicLibraryProvider.notifier)
            .downloadOneMusic(result['name']!, url: result['url']);
        if (context.mounted) {
          AppSnackBar.showSuccess(context, '已提交单曲下载任务');
        }
      } else if (result['type'] == 'playlist') {
        await ref
            .read(playlistProvider.notifier)
            .downloadPlaylist(result['name']!, url: result['url']);
        if (context.mounted) {
          AppSnackBar.showSuccess(context, '已提交整表下载任务');
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.showError(context, '下载失败：$e');
      }
    }
  }

  /// 退出登录对话框（根据当前模式退出对应的登录）
  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    final playbackMode = ref.read(playbackModeProvider);
    final modeName =
        playbackMode == PlaybackMode.xiaomusic ? 'xiaomusic' : '直连模式';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('退出登录'),
            content: Text('确定要退出 $modeName 的登录吗？\n\n退出后将返回登录页面。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();

                  // 🎯 根据当前模式退出对应的登录
                  if (playbackMode == PlaybackMode.xiaomusic) {
                    await ref.read(authProvider.notifier).logout();
                  } else {
                    await ref.read(directModeProvider.notifier).logout();
                  }

                  // 跳转到根路由，AuthWrapper 会根据 playbackMode 显示对应登录页
                  if (context.mounted) context.go('/');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                ),
                child: const Text('退出'),
              ),
            ],
          ),
    );
  }

  /// 切换模式对话框（退出所有登录，清除模式选择）
  void _showSwitchModeDialog(BuildContext context, WidgetRef ref) {
    final playbackMode = ref.read(playbackModeProvider);
    final currentModeName =
        playbackMode == PlaybackMode.xiaomusic ? 'xiaomusic' : '直连模式';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('切换模式'),
            content: Text(
              '当前模式：$currentModeName\n\n'
              '切换模式将：\n'
              '• 退出所有模式的登录\n'
              '• 返回模式选择页面\n'
              '• 可以重新选择播放模式\n\n'
              '确定要继续吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();

                  // 🎯 退出所有模式的登录
                  await ref.read(authProvider.notifier).logout();
                  await ref.read(directModeProvider.notifier).logout();

                  // 🎯 清除模式选择
                  await ref.read(playbackModeProvider.notifier).clearMode();

                  // 跳转到根路由，AuthWrapper 会自动展示模式选择页
                  if (context.mounted) context.go('/');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('切换'),
              ),
            ],
          ),
    );
  }

  Rect _resolveSharePositionOrigin(BuildContext context) {
    Rect? rectFromBox(RenderBox? box) {
      if (box == null || !box.hasSize) {
        return null;
      }
      final size = box.size;
      if (size.width <= 0 || size.height <= 0) {
        return null;
      }
      final origin = box.localToGlobal(Offset.zero);
      return origin & size;
    }

    final currentBox = context.findRenderObject() as RenderBox?;
    final currentRect = rectFromBox(currentBox);
    if (currentRect != null) {
      return currentRect;
    }

    final overlayBox =
        Navigator.of(
              context,
              rootNavigator: true,
            ).overlay?.context.findRenderObject()
            as RenderBox?;
    final overlayRect = rectFromBox(overlayBox);
    if (overlayRect != null) {
      return Rect.fromCenter(center: overlayRect.center, width: 1, height: 1);
    }

    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null &&
        mediaQuery.size.width > 0 &&
        mediaQuery.size.height > 0) {
      return Rect.fromCenter(
        center: mediaQuery.size.center(Offset.zero),
        width: 1,
        height: 1,
      );
    }

    return const Rect.fromLTWH(1, 1, 1, 1);
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final sharePositionOrigin = _resolveSharePositionOrigin(context);
      final level = await _selectLogExportLevel(context);
      if (level == null) {
        return;
      }
      final exportFile = await AppLogger.instance.buildShareableLogFile(
        level: level,
      );
      if (exportFile == null) {
        if (context.mounted) {
          AppSnackBar.showText(context, '暂无日志文件');
        }
        return;
      }
      final xfiles = [XFile(exportFile.path)];
      await Share.shareXFiles(
        xfiles,
        text: 'HMusic 日志（${level.displayName}）',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.showText(context, '导出日志失败: $e');
      }
    }
  }

  Future<LogExportLevel?> _selectLogExportLevel(BuildContext context) async {
    return showModalBottomSheet<LogExportLevel>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.flash_on_rounded),
                  title: const Text('精简导出（推荐）'),
                  subtitle: const Text('仅保留关键状态、告警和错误，体积最小'),
                  onTap:
                      () => Navigator.of(context).pop(LogExportLevel.essential),
                ),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('标准导出'),
                  subtitle: const Text('保留主要流程，过滤调试工具噪音'),
                  onTap:
                      () => Navigator.of(context).pop(LogExportLevel.standard),
                ),
                ListTile(
                  leading: const Icon(Icons.article_rounded),
                  title: const Text('完整导出'),
                  subtitle: const Text('尽量完整保留（仍会去除少量工具噪音）'),
                  onTap: () => Navigator.of(context).pop(LogExportLevel.full),
                ),
              ],
            ),
          ),
    );
  }

  /// 下载音质选择器
  Widget _buildQualitySelector(
    BuildContext context,
    WidgetRef ref,
    SourceSettings settings,
    Color onSurface,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Icon(
          Icons.graphic_eq_rounded,
          color: onSurface.withOpacity(0.7),
          size: 24,
        ),
      ),
      title: const Text('默认下载音质', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: DropdownButton<String>(
          dropdownColor: Theme.of(context).scaffoldBackgroundColor,
          value: settings.defaultDownloadQuality,
          underline: const SizedBox.shrink(),
          isDense: true,
          alignment: AlignmentDirectional.centerEnd,
          icon: const Icon(Icons.arrow_drop_down),
          items: const [
            DropdownMenuItem(
              value: 'hires24',
              child: Text('HI-Res(24bit)', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: 'lossless',
              child: Text('无损音乐(flac)', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: 'high',
              child: Text('高品质(320k)', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: 'standard',
              child: Text('标准音质(128k)', style: TextStyle(fontSize: 12)),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(sourceSettingsProvider.notifier)
                  .save(settings.copyWith(defaultDownloadQuality: value));
            }
          },
        ),
      ),
    );
  }

  /// 本地下载路径显示
  Widget _buildDownloadPathDisplay(BuildContext context, Color onSurface) {
    return FutureBuilder<String>(
      future: _getDownloadPath(),
      builder: (context, snapshot) {
        final path = snapshot.data ?? '加载中...';
        return ListTile(
          leading: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Icon(
              Icons.folder_open_rounded,
              color: onSurface.withOpacity(0.7),
              size: 24,
            ),
          ),
          title: const Text('本地下载路径'),
          subtitle: Text(
            path,
            style: TextStyle(fontSize: 12, color: onSurface.withOpacity(0.6)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: InkWell(
              onTap: () async {
                final actualPath = await _getDownloadPath();
                await Clipboard.setData(ClipboardData(text: actualPath));
                if (context.mounted) {
                  AppSnackBar.showSuccess(context, '已复制到剪贴板');
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
                child: Icon(
                  Icons.copy_rounded,
                  color: onSurface.withOpacity(0.4),
                  size: 20,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 获取下载路径
  Future<String> _getDownloadPath() async {
    try {
      if (Platform.isIOS) {
        // iOS 没有公共下载目录，使用 Documents 目录
        final dir = await getApplicationDocumentsDirectory();
        return '${dir.path}\n(iOS 应用沙盒 Documents 目录)';
      } else {
        // Android 使用公共下载目录
        return '/storage/emulated/0/Download/HMusic';
      }
    } catch (e) {
      return '获取路径失败: $e';
    }
  }
}
