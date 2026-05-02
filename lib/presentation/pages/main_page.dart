import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'control_panel_page.dart';
import 'playlist_page.dart';
import 'music_search_page.dart';
import '../providers/music_search_provider.dart';
import 'music_library_page.dart';
import '../providers/auth_provider.dart';
import '../providers/music_library_provider.dart';
import '../widgets/app_snackbar.dart';
import '../providers/ssh_settings_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/usage_stats_provider.dart';
import '../providers/direct_mode_provider.dart';
import '../providers/device_provider.dart'; // 🎯 新增：播放模式
import '../providers/local_playlist_provider.dart'; // 🎯 新增：直连模式歌单
import '../providers/navigation_provider.dart'; // 🎯 新增：Tab 索引管理
import '../widgets/sponsor_prompt_dialog.dart';
import '../widgets/app_layout.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  late AnimationController _heartbeatController;
  late Animation<double> _heartbeatAnimation;
  bool _hasPlayedHeartbeat = false;

  List<Widget> get _pages => [
    const ControlPanelPage(
      key: ValueKey('control_panel_page'),
      showAppBar: false,
    ),
    const MusicSearchPage(key: ValueKey('music_search_page')),
    const PlaylistPage(key: ValueKey('playlist_page')),
    const MusicLibraryPage(key: ValueKey('music_library_page')),
  ];

  void _onItemTapped(int index) {
    final wasIndex = _selectedIndex;
    setState(() {
      _selectedIndex = index;
    });

    // 🎯 同步更新 Provider（让其他页面可以感知当前 Tab）
    ref.read(mainTabIndexProvider.notifier).state = index;

    // 当切到"列表"标签（index 2）时触发一次加载
    if (index == 2 && wasIndex != 2) {
      // 🎯 根据播放模式刷新对应的歌单
      final playbackMode = ref.read(playbackModeProvider);

      if (playbackMode == PlaybackMode.miIoTDirect) {
        // 直连模式：刷新本地歌单
        ref.read(localPlaylistProvider.notifier).refreshPlaylists();
      } else {
        // xiaomusic 模式：检查登录后刷新服务器歌单
        final auth = ref.read(authProvider);
        if (auth is AuthAuthenticated) {
          ref.read(playlistProvider.notifier).refreshPlaylists();
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchTextChanged);

    // 初始化心跳动画
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartbeatAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _heartbeatController, curve: Curves.easeInOut),
    );

    // 延迟检查里程碑，避免在初始化时打扰用户
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkMilestones();
      }
    });

    // 延迟播放心跳动画（只播放3次）
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_hasPlayedHeartbeat) {
        _playHeartbeatAnimation();
      }
    });
  }

  /// 播放心跳动画(3次)
  void _playHeartbeatAnimation() async {
    _hasPlayedHeartbeat = true;
    for (int i = 0; i < 3; i++) {
      await _heartbeatController.forward();
      await _heartbeatController.reverse();
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 检查并显示里程碑
  void _checkMilestones() async {
    final usageStats = ref.read(usageStatsProvider.notifier);

    // 检查使用天数里程碑
    if (usageStats.checkDaysMilestone()) {
      final result = await SponsorPromptDialog.showDaysMilestone(context);
      if (result == true || result == 'never') {
        await usageStats.markDaysMilestoneShown();
        await usageStats.updateLastPromptDate();
        if (result == 'never') {
          await usageStats.setNeverShowPrompt(true);
        }
      }
      return; // 一次只显示一个提示
    }

    // 检查播放里程碑
    if (usageStats.checkPlaysMilestone()) {
      final result = await SponsorPromptDialog.showPlaysMilestone(context);
      if (result == true) {
        await usageStats.markPlaysMilestoneShown();
        await usageStats.updateLastPromptDate();
      }
      return;
    }

    // 检查歌词里程碑
    if (usageStats.checkLyricsMilestone()) {
      final result = await SponsorPromptDialog.showLyricsMilestone(context);
      if (result == true) {
        await usageStats.markLyricsMilestoneShown();
        await usageStats.updateLastPromptDate();
      }
      return;
    }

    // 检查30天间隔提示
    final stats = ref.read(usageStatsProvider);
    if (stats.shouldShowIntervalPrompt) {
      final result = await SponsorPromptDialog.showIntervalPrompt(context);
      if (result == true || result == 'never') {
        await usageStats.updateLastPromptDate();
        if (result == 'never') {
          await usageStats.setNeverShowPrompt(true);
        }
      }
    }
  }

  void _handleSearchTextChanged() {
    // 清除按钮的显隐改由 ValueListenableBuilder 驱动，不再 setState 全量重建

    // Ignore input while IME is composing (e.g., Pinyin on macOS)
    if (_searchController.value.composing.isValid) {
      return;
    }

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_searchController.value.composing.isValid) return;
      final text = _searchController.text;
      ref.read(musicSearchProvider.notifier).searchOnline(text);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    _heartbeatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 监听 Tab 索引变化（从其他页面切换 Tab 时触发）
    ref.listen<int>(mainTabIndexProvider, (previous, next) {
      if (next != _selectedIndex) {
        _onItemTapped(next);
      }
    });

    // 是否为亮色模式在此处不再需要单独判断

    // 背景渐变已移除，统一使用 surface 颜色，避免滚动影响顶部底色

    // 状态栏样式已在全局 theme 设置，此处不再单独指定

    return Scaffold(
      key: const ValueKey('main_scaffold'),
      // Keep bottom navigation fixed when keyboard shows
      resizeToAvoidBottomInset: false,
      // 统一背景色为 surface，移除页面级渐变，避免顶部随滚动色彩变化
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: false,
      extendBodyBehindAppBar: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
          statusBarBrightness:
              Theme.of(context).brightness == Brightness.dark
                  ? Brightness.dark
                  : Brightness.light,
        ),
        child: Stack(
          children: [
          // Content column
          SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                // Part 1: Header (Title, Refresh, User Info)
                _buildHeader(context),

                // Part 2: Device Selector or Search Bar
                _buildSecondarySection(),

                // Part 3: Main Content (Player, Lists)
                Expanded(
                  child: IndexedStack(
                    key: const ValueKey('main_indexed_stack'),
                    index: _selectedIndex,
                    children: _pages,
                  ),
                ),
              ],
            ),
          ),

          // Floating blurred bottom navigation overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(child: _buildModernBottomNav()),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildHeader(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: SizedBox(
        height: 44.0, 
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 28, 
              child: AspectRatio(
                aspectRatio: 572 / 210, // 强制保持原始比例
                child: SvgPicture.asset(
                  'assets/hmusic-logo.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const Spacer(),
            // Upload button - only show on music library tab (index 3) in xiaomusic mode
            if (_selectedIndex == 3 &&
                ref.watch(playbackModeProvider) == PlaybackMode.xiaomusic)
              _buildHeaderIcon(
                icon: Icons.upload_rounded,
                onPressed: _showUploadDialog,
                tooltip: '上传音乐文件',
                onSurface: onSurface,
              ),
            // Sponsor button
            _buildHeaderIcon(
              icon: CupertinoIcons.heart,
              onPressed: () => context.push('/settings/sponsor'),
              tooltip: '赞赏支持',
              onSurface: onSurface,
              iconColor: const Color(0xFFFF4D8D).withValues(alpha: 0.9), // 优雅的粉红色
            ),
            // Device Selection button
            _buildHeaderIcon(
              icon: CupertinoIcons.hifispeaker,
              onPressed: () => _showDeviceSelectionDialog(context),
              tooltip: '选择播放设备',
              onSurface: onSurface,
            ),
            _buildHeaderIcon(
              icon: CupertinoIcons.settings,
              onPressed: () => context.push('/settings'),
              tooltip: '设置',
              onSurface: onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIcon({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    required Color onSurface,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(),
        padding: EdgeInsets.zero,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle, // 改为圆形，视觉更简洁
          ),
          child: Icon(
            icon,
            color: iconColor ?? onSurface.withValues(alpha: 0.8),
            size: 19, // 稍微缩小一点，更精致
          ),
        ),
      ),
    );
  }

  Future<void> _showDeviceSelectionDialog(BuildContext context) async {
    final playbackMode = ref.read(playbackModeProvider);
    List<dynamic> devices = [];
    String? currentDeviceId;

    if (playbackMode == PlaybackMode.miIoTDirect) {
      final directState = ref.read(directModeProvider);
      if (directState is DirectModeAuthenticated) {
        devices = directState.devices;
        currentDeviceId = directState.playbackDeviceType;
      }
    } else {
      final deviceState = ref.read(deviceProvider);
      devices = deviceState.devices;
      currentDeviceId = deviceState.selectedDeviceId;
    }

    if (playbackMode != PlaybackMode.miIoTDirect && devices.isEmpty) {
      AppSnackBar.showInfo(context, '没有可用的播放设备');
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    final selectedDeviceId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '选择播放设备',
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (playbackMode == PlaybackMode.miIoTDirect)
                          _buildDeviceSheetItem(
                            context: sheetContext,
                            icon: Icons.smartphone_rounded,
                            title: '本机播放',
                            subtitle: '在当前设备上播放',
                            value: 'local',
                            currentDeviceId: currentDeviceId,
                            activeColor: colorScheme.primary,
                            defaultColor: onSurface,
                          ),
                        if (playbackMode == PlaybackMode.miIoTDirect &&
                            devices.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                            child: Text(
                              '音箱设备',
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ...devices.map((device) {
                          final isMiDevice =
                              playbackMode == PlaybackMode.miIoTDirect;
                          final id = isMiDevice ? device.deviceId : device.id;
                          final name = device.name;
                          final isOnline =
                              isMiDevice ? true : (device.isOnline ?? false);

                          return _buildDeviceSheetItem(
                            context: sheetContext,
                            icon:
                                isMiDevice
                                    ? Icons.speaker_rounded
                                    : Icons.speaker_group_rounded,
                            title: name,
                            subtitle: isOnline ? '在线' : '离线',
                            value: id,
                            currentDeviceId: currentDeviceId,
                            activeColor: colorScheme.primary,
                            defaultColor: onSurface,
                            enabledColor: isOnline ? Colors.green : null,
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selectedDeviceId != null && selectedDeviceId != currentDeviceId) {
      if (playbackMode == PlaybackMode.miIoTDirect) {
        await ref
            .read(directModeProvider.notifier)
            .selectPlaybackDevice(selectedDeviceId);
      } else {
        ref.read(deviceProvider.notifier).selectDevice(selectedDeviceId);
      }
    }
  }

  Widget _buildDeviceSheetItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required String? currentDeviceId,
    required Color activeColor,
    required Color defaultColor,
    Color? enabledColor,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isSelected = value == currentDeviceId;
    final leadingColor =
        isSelected
            ? activeColor
            : (enabledColor ?? defaultColor.withValues(alpha: 0.76));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).pop(value),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? activeColor.withValues(alpha: 0.12)
                      : onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    isSelected
                        ? activeColor.withValues(alpha: 0.8)
                        : onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: leadingColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? activeColor : defaultColor,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: defaultColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: activeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondarySection() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    if (_selectedIndex != 1) {
      return Container(
        key: ValueKey<String>('secondary_section_$_selectedIndex'),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: const SizedBox.shrink(),
      );
    }
    return Container(
      key: ValueKey<String>('secondary_section_$_selectedIndex'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          return TextField(
            key: const ValueKey('online_search_field'),
            controller: _searchController,
            style: TextStyle(color: onSurface),
            decoration: InputDecoration(
              hintText: '在线搜索歌曲...',
              hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.5)),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: onSurface.withValues(alpha: 0.6),
              ),
              suffixIcon:
                  value.text.isNotEmpty
                      ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(musicSearchProvider.notifier).clearSearch();
                        },
                      )
                      : null,
              filled: true,
              fillColor: onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModernBottomNav() {
    final bottomMargin = AppLayout.bottomOverlayBottomMargin(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: bottomMargin,
        top: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: onSurface.withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.65),
            ),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTabItem(
                icon: Icons.play_circle_outline_rounded,
                activeIcon: Icons.play_circle_filled_rounded,
                label: '播放',
                index: 0,
              ),
              _buildTabItem(
                icon: Icons.search_rounded,
                activeIcon: Icons.search_rounded,
                label: '搜索',
                index: 1,
              ),
              _buildTabItem(
                icon: Icons.playlist_play_outlined,
                activeIcon: Icons.playlist_play_rounded,
                label: '列表',
                index: 2,
              ),
              _buildTabItem(
                icon: Icons.library_music_outlined,
                activeIcon: Icons.library_music_rounded,
                label: '曲库',
                index: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.7);

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder:
                    (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                child:
                    index == 0
                        ? _PlayTabIcon(
                          key: ValueKey<String>('play_tab_$isSelected'),
                          isSelected: isSelected,
                        )
                        : Icon(
                          isSelected ? activeIcon : icon,
                          key: ValueKey<String>(
                            'nav_icon_${index}_$isSelected',
                          ),
                          size: 26,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUploadDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        withData: false, // We only need paths for uploads
      );

      if (!mounted) {
        return;
      }

      if (result != null && result.files.isNotEmpty) {
        // Show upload confirmation dialog
        final shouldUpload = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('上传音乐文件'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('已选择 ${result.files.length} 个文件：'),
                    const SizedBox(height: 8),
                    ...result.files
                        .take(5)
                        .map(
                          (file) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• ${file.name}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                    if (result.files.length > 5)
                      Text(
                        '... 还有 ${result.files.length - 5} 个文件',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('上传'),
                  ),
                ],
              ),
        );

        if (shouldUpload == true) {
          await _uploadFiles(result.files);
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, '选择文件失败：$e');
      }
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    try {
      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              title: const Text('上传中...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('正在上传 ${files.length} 个文件'),
                ],
              ),
            ),
      );

      final ssh = ref.read(sshSettingsProvider);
      final useHttp = ssh.useHttpUpload;
      bool ok = false;
      String mode = useHttp ? 'HTTP' : 'SCP';

      if (useHttp) {
        try {
          await ref.read(musicLibraryProvider.notifier).uploadMusics(files);
          ok = true;
        } catch (e) {
          // HTTP 失败则回退到 SCP
          try {
            await ref
                .read(musicLibraryProvider.notifier)
                .uploadViaScp(
                  host: ssh.host,
                  port: ssh.port,
                  username: ssh.username,
                  password: ssh.password,
                  remoteDir: '/opt/xiaomusic/music',
                  files: files,
                  subDir: ssh.subDir,
                );
            ok = true;
            mode = 'SCP(回退)';
          } catch (_) {
            rethrow;
          }
        }
      } else {
        await ref
            .read(musicLibraryProvider.notifier)
            .uploadViaScp(
              host: ssh.host,
              port: ssh.port,
              username: ssh.username,
              password: ssh.password,
              remoteDir: '/opt/xiaomusic/music',
              files: files,
              subDir: ssh.subDir,
            );
        ok = true;
        mode = 'SCP';
      }

      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        if (ok) {
          AppSnackBar.showSuccess(context, '$mode 上传成功：${files.length} 个文件');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        AppSnackBar.showError(context, '上传失败：$e');
      }
    }
  }
}

/// 独立的播放 Tab 图标 — 隔离 playbackProvider 的 watch 范围，
/// 避免播放状态更新触发整个 MainPage 重建。
class _PlayTabIcon extends ConsumerWidget {
  final bool isSelected;

  const _PlayTabIcon({super.key, required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final cover = playback.albumCoverUrl;
    final isPlaying = playback.currentMusic?.isPlaying ?? false;

    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.7);
    final borderColor = (isSelected ? activeColor : inactiveColor).withValues(
      alpha: 0.6,
    );

    // 计算播放进度 (0.0 - 1.0)
    final offset = playback.currentMusic?.offset ?? 0;
    final duration = playback.currentMusic?.duration ?? 0;
    final progress = duration > 0 ? (offset / duration).clamp(0.0, 1.0) : 0.0;

    Widget image = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: inactiveColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_circle_filled_rounded,
        size: 16,
        color: isSelected ? activeColor : inactiveColor,
      ),
    );

    if (cover != null && cover.isNotEmpty) {
      image = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: cover,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          errorWidget:
              (_, __, ___) => Icon(
                Icons.music_note_rounded,
                size: 16,
                color: inactiveColor,
              ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 外围进度圈
        SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.0,
            backgroundColor: borderColor.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              isSelected ? activeColor : inactiveColor,
            ),
          ),
        ),
        // 封面图 (居中)
        Positioned(left: 2, top: 2, child: image),
        // 播放状态指示器
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
              size: 10,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        ),
      ],
    );
  }
}
