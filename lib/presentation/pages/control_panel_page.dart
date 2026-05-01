import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/playback_provider.dart';
import '../../core/constants/app_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../providers/lyric_provider.dart';
import '../../data/models/device.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_bottom_sheet.dart';
import 'lyrics_page.dart';
import '../providers/direct_mode_provider.dart';
import '../providers/playback_queue_provider.dart';
import '../../data/models/playlist_queue.dart';

import 'package:flutter_svg/flutter_svg.dart';

class ControlPanelPage extends ConsumerStatefulWidget {
  final bool showAppBar;

  const ControlPanelPage({super.key, this.showAppBar = true});

  @override
  ConsumerState<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends ConsumerState<ControlPanelPage>
    with TickerProviderStateMixin {
  AnimationController? _albumAnimationController;
  AnimationController? _buttonAnimationController;
  AnimationController? _bgAnimationController; // 🔧 背景动效控制器
  Color? _dominantColor; // 封面主色调
  String? _lastCoverUrl; // 上一次的封面 URL
  String? _colorExtractedUrl; // 🔧 已提取颜色的封面 URL（防止重复提取）
  double? _draggingValue; // 🔧 拖动进度条时的临时值

  @override
  void initState() {
    super.initState();

    _albumAnimationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );

    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _bgAnimationController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    // 🎯 优化：立即开始加载，避免延迟造成的割裂感
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final authState = ref.read(authProvider);

          if (authState is AuthAuthenticated) {
            // 🔧 优化：移除重复的 loadDevices 调用，ensureInitialized 内部会自动调用
            // 直连模式的设备由 DirectModeProvider 自动加载
            ref.read(playbackProvider.notifier).ensureInitialized();
          } else {
            debugPrint('ControlPanel: 用户未登录，跳过自动加载设备');
          }
        } catch (e) {
          debugPrint('初始化错误: $e');
        }
      }
    });
  }

  /// 根据当前播放模式获取设备列表状态
  DeviceState _getDeviceStateByMode(
    PlaybackMode mode,
    DeviceState xiaoMusicState,
    DirectModeState directState,
  ) {
    if (mode == PlaybackMode.miIoTDirect) {
      // 直连模式：从 DirectModeProvider 获取设备列表
      if (directState is DirectModeAuthenticated) {
        // 将 MiDevice 转换为 Device 格式
        final miDevices =
            directState.devices.map((miDevice) {
              return Device(
                id: miDevice.deviceId,
                name: miDevice.name,
                isOnline: true, // 假设直连设备都是在线的
                type: miDevice.hardware, // 将 hardware 映射到 type 字段
              );
            }).toList();

        return DeviceState(
          devices: miDevices,
          selectedDeviceId:
              directState.playbackDeviceType, // 🔧 修复：使用 playbackDeviceType
          isLoading: false,
        );
      } else {
        // 未登录或未找到设备
        return const DeviceState(
          devices: [],
          selectedDeviceId: null,
          isLoading: false,
        );
      }
    } else {
      // xiaomusic 模式：使用原有的设备列表
      return xiaoMusicState;
    }
  }

  @override
  void dispose() {
    _albumAnimationController?.dispose();
    _buttonAnimationController?.dispose();
    _bgAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackProvider);
    final authState = ref.watch(authProvider);
    final xiaoMusicDeviceState = ref.watch(deviceProvider); // xiaomusic模式的设备列表
    final directModeState = ref.watch(directModeProvider); // 直连模式的状态
    final playbackMode = ref.watch(playbackModeProvider); // 当前播放模式

    final deviceState = _getDeviceStateByMode(
      playbackMode,
      xiaoMusicDeviceState,
      directModeState,
    );

    final coverUrl = playbackState.albumCoverUrl;
    if (coverUrl != _lastCoverUrl) {
      _lastCoverUrl = coverUrl;
      _dominantColor = null;
      _colorExtractedUrl = null;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _albumAnimationController != null) {
        if (playbackState.currentMusic?.isPlaying ?? false) {
          if (!_albumAnimationController!.isAnimating) {
            _albumAnimationController!.repeat();
          }
        } else {
          if (_albumAnimationController!.isAnimating) {
            _albumAnimationController!.stop();
          }
        }
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // 适配主题背景
      appBar: widget.showAppBar ? _buildAppBar(context) : null,
      body: Stack(
        children: [
          SafeArea(
            bottom: true,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  sliver: SliverList.list(
                    children: [
                      if (widget.showAppBar) const SizedBox(height: 0),
                      _buildIntegratedPlayerCard(
                        playbackState,
                        deviceState,
                        authState,
                        playbackMode,
                      ),
                      if (playbackState.error != null)
                        _buildErrorMessage(playbackState),
                    ],
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SizedBox(
                    height: AppLayout.bottomOverlayHeight(context) + 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        '小米音乐',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface.withOpacity(0.9),
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed('/now-playing'),
          icon: Icon(
            Icons.queue_music_rounded,
            color: onSurface.withOpacity(0.8),
          ),
          tooltip: '正在播放',
        ),
        IconButton(
          onPressed: () async {
            try {
              // 🎯 根据播放模式刷新对应的设备列表
              final playbackMode = ref.read(playbackModeProvider);
              if (playbackMode == PlaybackMode.miIoTDirect) {
                await ref.read(directModeProvider.notifier).refreshDevices();
              } else {
                await ref.read(deviceProvider.notifier).loadDevices();
              }
              await ref.read(playbackProvider.notifier).refreshStatus();
            } catch (e) {
              // Ignore refresh errors
            }
          },
          icon: Icon(Icons.refresh_rounded, color: onSurface.withOpacity(0.8)),
        ),
      ],
    );
  }

  Widget _buildIntegratedPlayerCard(
    PlaybackState playbackState,
    DeviceState deviceState,
    AuthState authState,
    PlaybackMode playbackMode,
  ) {
    final currentMusic = playbackState.currentMusic;
    final isPlaying = currentMusic?.isPlaying ?? false;
    final contentWidth =
        (MediaQuery.of(context).size.width - 48).clamp(240.0, 360.0).toDouble();

    // 获取屏幕高度以决定是否需要自适应间距
    final screenHeight = MediaQuery.of(context).size.height;
    // Smooth proportional scaling
    final double scale = (screenHeight / 700.0).clamp(0.9, 1.3);

    final double topGap = 6.0 * scale;
    final double coverInfoGap = 20.0 * scale;

    // Balance the gaps above and below the progress bar
    // Decrease the top gap and increase the bottom gap to achieve visual symmetry.
    final double infoProgressGap = 16.0 * scale;
    final double progressControlsGap = 40.0 * scale;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: topGap),
          // 1. 顶部大封面
          _buildAlbumArtwork(currentMusic, isPlaying, contentWidth),

          SizedBox(height: coverInfoGap),

          // 2. 歌曲信息 (音量和收藏整合在这里)
          SizedBox(
            width: contentWidth,
            child: _buildSongInfo(
              playbackState,
              authState is AuthAuthenticated,
            ),
          ),

          SizedBox(height: infoProgressGap),

          // 3. 进度条
          SizedBox(
            width: contentWidth,
            child:
                currentMusic == null
                    ? _buildInitialProgressBar()
                    : _buildProgressBar(currentMusic),
          ),

          SizedBox(height: progressControlsGap),

          // 4. 播放控制 (包含模式和定时)
          SizedBox(
            width: contentWidth,
            child: _buildPlaybackControls(playbackState),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceArea(DeviceState deviceState, PlaybackMode playbackMode) {
    if (deviceState.isLoading && deviceState.devices.isEmpty) {
      // 加载中且没有设备：显示加载占位符
      return _buildDeviceLoadingPlaceholder();
    } else if (deviceState.devices.isNotEmpty) {
      // 有设备：显示设备选择器
      return _buildDeviceSelector(deviceState, playbackMode);
    } else {
      // 加载完成但没有设备：显示提示
      return _buildNoDeviceHint(playbackMode);
    }
  }

  /// 🎯 加载中的占位符（保持与设备选择器相同的高度）
  Widget _buildDeviceLoadingPlaceholder() {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(onSurface.withOpacity(0.6)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在加载设备...',
            style: TextStyle(
              color: onSurface.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  double _stableCardFixedHeight(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final artworkSize = screenWidth * 0.46; // matches _buildAlbumArtwork

    const double deviceSelectorHeight = 36; // approx row height with padding
    const double titleFontSize = 24;
    const double titleLineHeight = 1.3;
    const int titleLines = 2;
    const double subtitleFontSize = 16;
    const double subtitleLineHeight = 1.25;
    final double titleBlock =
        titleFontSize * titleLineHeight * titleLines; // ~62
    final double subtitleBlock = subtitleFontSize * subtitleLineHeight; // ~20

    const double sliderBlock = 56; // slider + time row + paddings
    const double controlsBlock = 56; // main play button area height
    const double volumeBlock = 44; // volume row with slider thickness

    // Vertical spacings present in the card
    const double vSpace = 12 + 12 + 8 + 8 + 8; // between sections

    // Card internal padding top+bottom = 24 (see Container padding: 12 all)
    const double cardVerticalPadding = 24;
    // Additional hint line under slider (~18px)
    const double seekHintHeight = 18;

    final double base =
        deviceSelectorHeight +
        artworkSize +
        titleBlock +
        subtitleBlock +
        sliderBlock +
        seekHintHeight +
        controlsBlock +
        volumeBlock +
        vSpace +
        cardVerticalPadding;

    // Small buffer to prevent fractional rounding causing wrap
    return base + 6;
  }

  Widget _buildDeviceSelector(DeviceState state, PlaybackMode playbackMode) {
    // 🎯 根据播放模式获取选中的设备信息
    final Device selectedDevice;
    final bool isOnline;

    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 直连模式：根据 playbackDeviceType 判断
      final directState = ref.watch(directModeProvider);

      if (directState is DirectModeAuthenticated) {
        final playbackDeviceType = directState.playbackDeviceType;

        if (playbackDeviceType == 'local') {
          // 本地播放
          selectedDevice = Device(id: 'local', name: '本地播放', isOnline: true);
          isOnline = true;
        } else {
          // 小爱音箱
          selectedDevice = state.devices.firstWhere(
            (d) => d.id == playbackDeviceType,
            orElse: () => Device(id: '', name: '选择播放设备', isOnline: false),
          );
          isOnline = selectedDevice.isOnline ?? false;
        }
      } else {
        selectedDevice = Device(id: '', name: '选择播放设备', isOnline: false);
        isOnline = false;
      }
    } else {
      // xiaomusic 模式：使用原有逻辑
      selectedDevice = state.devices.firstWhere(
        (d) => d.id == state.selectedDeviceId,
        orElse: () => Device(id: '', name: '选择一个设备', isOnline: false),
      );
      isOnline = selectedDevice.isOnline ?? false;
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () => _showDeviceSelectionSheet(context, state, playbackMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isOnline ? Colors.greenAccent : Colors.redAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isOnline ? Colors.greenAccent : Colors.redAccent)
                        .withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedDevice.name,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: onSurface.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  /// 🎯 没有找到设备时的提示
  Widget _buildNoDeviceHint(PlaybackMode playbackMode) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orangeAccent.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.orangeAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未找到播放设备，请检查设置',
              style: TextStyle(
                color: onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: Colors.orangeAccent,
              size: 18,
            ),
            onPressed: () async {
              try {
                // 🎯 根据播放模式刷新对应的设备列表
                if (playbackMode == PlaybackMode.miIoTDirect) {
                  await ref.read(directModeProvider.notifier).refreshDevices();
                } else {
                  await ref.read(deviceProvider.notifier).loadDevices();
                }
              } catch (e) {
                // ignore
              }
            },
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _showDeviceSelectionSheet(
    BuildContext context,
    DeviceState state,
    PlaybackMode playbackMode,
  ) {
    showAppBottomSheet(
      context: context,
      builder: (context) {
        final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

        return AppBottomSheet(
          title: '选择设备',
          trailing: IconButton(
            onPressed: () async {
              try {
                // 🎯 根据播放模式刷新对应的设备列表
                if (playbackMode == PlaybackMode.miIoTDirect) {
                  await ref.read(directModeProvider.notifier).refreshDevices();
                } else {
                  await ref.read(deviceProvider.notifier).loadDevices();
                }
              } catch (e) {
                // ignore
              }
            },
            icon: Icon(Icons.refresh_rounded, color: onSurfaceColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isLoading && state.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      '未找到设备',
                      style: TextStyle(color: onSurfaceColor.withOpacity(0.7)),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // 🎵 直连模式：在设备列表顶部添加本地播放���项
                      if (playbackMode == PlaybackMode.miIoTDirect)
                        _buildLocalPlaybackOption(context, onSurfaceColor),

                      // 🎯 设备列表
                      ...state.devices.map((device) {
                        final isSelected =
                            playbackMode == PlaybackMode.miIoTDirect
                                ? _isDeviceSelectedInDirectMode(device.id)
                                : state.selectedDeviceId == device.id;

                        return ListTile(
                          leading: Icon(
                            // 🎯 根据设备类型显示不同图标
                            device.isLocalDevice
                                ? Icons
                                    .phone_android_rounded // 本机设备
                                : Icons.speaker_group_rounded, // 播放设备
                            color:
                                (device.isOnline ?? false)
                                    ? Colors.greenAccent
                                    : onSurfaceColor.withOpacity(0.4),
                          ),
                          title: Text(
                            device.name,
                            style: TextStyle(color: onSurfaceColor),
                          ),
                          trailing:
                              isSelected
                                  ? Icon(
                                    Icons.check_circle_rounded,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )
                                  : null,
                          onTap: () {
                            // 🎯 根据播放模式选择对应的Provider
                            if (playbackMode == PlaybackMode.miIoTDirect) {
                              // 直连模式：设置播放设备为小爱音箱
                              ref
                                  .read(directModeProvider.notifier)
                                  .selectPlaybackDevice(device.id);
                            } else {
                              // xiaomusic模式：使用 DeviceProvider
                              ref
                                  .read(deviceProvider.notifier)
                                  .selectDevice(device.id);
                            }
                            Navigator.pop(context);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 🎵 构建本地播放选项（仅直连模式）
  Widget _buildLocalPlaybackOption(BuildContext context, Color onSurfaceColor) {
    final directState = ref.watch(directModeProvider);

    // 检查本地播放是否被选中
    final isSelected =
        directState is DirectModeAuthenticated &&
        directState.playbackDeviceType == 'local';

    return ListTile(
      leading: Icon(
        Icons.smartphone_rounded,
        color:
            isSelected
                ? Theme.of(context).colorScheme.primary
                : onSurfaceColor.withOpacity(0.8),
      ),
      title: Text(
        '本地播放',
        style: TextStyle(
          color: onSurfaceColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '在手机上播放音乐',
        style: TextStyle(color: onSurfaceColor.withOpacity(0.6), fontSize: 12),
      ),
      trailing:
          isSelected
              ? Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
              )
              : null,
      onTap: () {
        // 设置播放设备为本地播放
        ref.read(directModeProvider.notifier).selectPlaybackDevice('local');
        Navigator.pop(context);
      },
    );
  }

  /// 🎯 检查设备是否在直连模式下被选中
  bool _isDeviceSelectedInDirectMode(String deviceId) {
    final directState = ref.read(directModeProvider);

    if (directState is DirectModeAuthenticated) {
      // 播放设备类型如果等于设备ID，说明这个设备被选中
      return directState.playbackDeviceType == deviceId;
    }

    return false;
  }

  void _openLyricsPage() {
    final current = ref.read(playbackProvider).currentMusic;
    if (current == null || current.curMusic.isEmpty) {
      AppSnackBar.showWarning(context, '当前没有播放歌曲');
      return;
    }
    ref.read(lyricProvider.notifier).loadLyrics(current.curMusic);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const LyricsPage()));
  }

  Widget _buildAlbumArtwork(
    dynamic currentMusic,
    bool isPlaying,
    double contentWidth,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // Use the exact contentWidth logic to perfectly align with the song info below.
    final coverSize = contentWidth * 0.65;
    // The record disc peeks out from the right.
    final recordSize = coverSize * 0.95;
    final coverTop = 2.0;
    final recordTop = coverTop + (coverSize - recordSize) / 2;

    // ✨ 获取封面图 URL
    final playbackState = ref.watch(playbackProvider);
    final coverUrl = playbackState.albumCoverUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: GestureDetector(
        onTap: () {
          _openLyricsPage();
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: contentWidth,
          height: coverSize + 14,
          child: Stack(
            children: [
              Positioned(
                right: 0,
                top: recordTop,
                child: RotationTransition(
                  turns: _albumAnimationController ?? kAlwaysCompleteAnimation,
                  child: Container(
                    width: recordSize,
                    height: recordSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 在浅色模式下使用更加明亮的深灰色，深色模式下使用略浅的黑灰色，避免与纯黑背景完全融合
                      color: isDark ? const Color(0xFF222222) : const Color(0xFF3D3D3D),
                      border: Border.all(
                        color: isDark 
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                        // 🎯 梦幻补光：外围微弱光晕
                        BoxShadow(
                          color:
                              (_dominantColor ?? Colors.black).withValues(
                                alpha: 0.08,
                              ),
                          blurRadius: 50,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (final factor in [0.88, 0.74, 0.60])
                          Container(
                            width: recordSize * factor,
                            height: recordSize * factor,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark 
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.white.withValues(alpha: 0.1),
                                width: 0.8,
                              ),
                            ),
                          ),
                        Container(
                          width: recordSize * 0.34,
                          height: recordSize * 0.34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: onSurface.withValues(alpha: 0.08),
                            // 中间的黑线圈，与外侧音轨圈保持一致
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white.withValues(alpha: 0.1),
                              width: 0.8,
                            ),
                          ),
                          child: ClipOval(
                            child:
                                coverUrl != null && coverUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      placeholder:
                                          (context, url) => Container(
                                            color: onSurface.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),
                                      errorWidget:
                                          (context, url, error) =>
                                              _buildDefaultArtwork(context, 
                                                recordSize,
                                                onSurface,
                                              ),
                                    )
                                    : _buildDefaultArtwork(context, 
                                      recordSize,
                                      onSurface,
                                    ),
                          ),
                        ),
                        Container(
                          width: recordSize * 0.06,
                          height: recordSize * 0.06,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: coverTop,
                child: Container(
                  width: coverSize,
                  height: coverSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: onSurface.withValues(alpha: 0.1),
                    boxShadow: [
                      // 主要投影：稍微变淡，保持柔和
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                        blurRadius: 24,
                        offset: const Offset(8, 8),
                      ),
                      // 辅助投影：轻微晕染
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
                        blurRadius: 12,
                        spreadRadius: 1,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        coverUrl != null && coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              width: coverSize,
                              height: coverSize,
                              imageBuilder: (context, imageProvider) {
                                if (_colorExtractedUrl != coverUrl) {
                                  _colorExtractedUrl = coverUrl;
                                  Future.delayed(
                                    const Duration(milliseconds: 300),
                                    () {
                                      if (mounted &&
                                          coverUrl ==
                                              playbackState.albumCoverUrl) {
                                        _extractDominantColorFromProvider(
                                          imageProvider,
                                        );
                                      }
                                    },
                                  );
                                }
                                return Image(
                                  image: imageProvider,
                                  fit: BoxFit.cover,
                                );
                              },
                              placeholder:
                                  (context, url) => _buildDefaultArtwork(context, 
                                    coverSize,
                                    onSurface,
                                  ),
                              errorWidget:
                                  (context, url, error) => _buildDefaultArtwork(context, 
                                    coverSize,
                                    onSurface,
                                  ),
                            )
                            : _buildDefaultArtwork(context, coverSize, onSurface),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultArtwork(BuildContext context, double artworkSize, Color onSurface) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: artworkSize,
      height: artworkSize,
      color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F0F0),
      child: Center(
        child: SvgPicture.asset(
          'assets/hmusic-logo-square.svg',
          width: artworkSize * 0.5,
          height: artworkSize * 0.5,
        ),
      ),
    );
  }

  ({String title, String artist}) _splitSongDisplayName(String? rawName) {
    final displayName = rawName?.trim() ?? '';
    if (displayName.isEmpty) {
      return (title: '暂无播放', artist: '');
    }

    final separatorIndex = displayName.lastIndexOf(' - ');
    if (separatorIndex <= 0 || separatorIndex >= displayName.length - 3) {
      return (title: displayName, artist: '');
    }

    final title = displayName.substring(0, separatorIndex).trim();
    final artist = displayName.substring(separatorIndex + 3).trim();
    if (title.isEmpty || artist.isEmpty) {
      return (title: displayName, artist: '');
    }

    return (title: title, artist: artist);
  }

  Widget _buildSongInfo(PlaybackState state, bool hasLoaded) {
    final currentMusic = state.currentMusic;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final playbackMode = ref.read(playbackModeProvider);
    final bool hasSelectedDevice;
    if (playbackMode == PlaybackMode.miIoTDirect) {
      final directState = ref.read(directModeProvider);
      hasSelectedDevice =
          directState is DirectModeAuthenticated &&
          directState.playbackDeviceType.isNotEmpty;
    } else {
      hasSelectedDevice = ref.read(deviceProvider).selectedDeviceId != null;
    }
    final enabled = hasSelectedDevice;
    final favoriteEnabled = enabled && currentMusic != null;
    // Determine source text logic. Check queue source type directly.
    String sourceText;
    if (currentMusic != null) {
      // 🎯 优先通过队列的 source 类型判断是否为搜索播放
      final queueState = ref.read(playbackQueueProvider);
      final isSearchSource = queueState.queue?.source == PlaylistSource.searchResult;
      if (isSearchSource) {
        sourceText = '🔍 搜索播放';
      } else if (currentMusic.curPlaylist.isNotEmpty) {
        sourceText = currentMusic.curPlaylist;
      } else {
        sourceText = '本地播放';
      }
    } else {
      sourceText = hasLoaded ? '本地播放' : '正在同步';
    }

    final mediaQuery = MediaQuery.of(context);
    final isCompactWidth = mediaQuery.size.width < 380;
    final isTightHeight = mediaQuery.size.height < 760;
    final useThreeLineLayout = !isCompactWidth && !isTightHeight;
    final songInfo = _splitSongDisplayName(currentMusic?.curMusic);
    final titleText = songInfo.title;
    final artistText = songInfo.artist;
    final compactSecondLine =
        artistText.isNotEmpty ? '$artistText · $sourceText' : sourceText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titleText,
                style: TextStyle(
                  fontSize: useThreeLineLayout ? 24 : 20,
                  fontWeight: FontWeight.w800,
                  color: onSurface.withValues(alpha: 0.94),
                  height: 1.15,
                  letterSpacing: 0.4, // 微笑增加字距，提升高级感
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (useThreeLineLayout) ...[
                const SizedBox(height: 6),
                Text(
                  artistText,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: onSurface.withValues(alpha: 0.82),
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        sourceText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.4), // 降低不重要信息的亮度
                          height: 1.0,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: _PlaybackModeBadge(),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        compactSecondLine,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.52),
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const _PlaybackModeBadge(),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: const Icon(Icons.volume_up_rounded),
              iconSize: 24,
              color: onSurface.withValues(alpha: 0.62),
              onPressed:
                  enabled ? () => _showVolumeBottomSheet(context, state) : null,
            ),
            const SizedBox(width: 2),
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: Icon(
                state.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              iconSize: 28,
              color:
                  favoriteEnabled
                      ? (state.isFavorite
                          ? Colors.pinkAccent
                          : Theme.of(context).colorScheme.primary)
                      : onSurface.withValues(alpha: 0.3),
              onPressed:
                  favoriteEnabled
                      ? () =>
                          ref.read(playbackProvider.notifier).toggleFavorites()
                      : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar(dynamic currentMusic) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accentColor = Theme.of(context).colorScheme.primary;
    final currentTime = currentMusic.offset ?? 0;
    final totalTime = currentMusic.duration ?? 0;

    final displayTime =
        _draggingValue != null
            ? (_draggingValue! * totalTime).round()
            : currentTime;

    final progress =
        (totalTime > 0) ? (displayTime / totalTime).clamp(0.0, 1.0) : 0.0;

    final seekEnabled = ref.watch(playbackProvider).seekEnabled;
    final canSeek = totalTime > 0 && seekEnabled;
    debugPrint(
      '🎯 [ControlPanel-ProgressBar] canSeek=$canSeek, progress=$progress, currentTime=$currentTime, totalTime=$totalTime, dragging=${_draggingValue != null}',
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            activeTrackColor: accentColor,
            inactiveTrackColor: onSurface.withValues(alpha: 0.14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            thumbColor: Colors.white,
            overlayColor: accentColor.withValues(alpha: 0.16),
            trackShape: const _CustomTrackShape(),
          ),
          child: Slider(
            value: progress,
            onChanged:
                canSeek
                    ? (value) {
                      debugPrint(
                        '🎯 [ControlPanel-ProgressBar] onChanged: $value',
                      );
                      setState(() {
                        _draggingValue = value;
                      });
                    }
                    : null,
            onChangeEnd:
                canSeek
                    ? (value) {
                      final newPos = (value * totalTime).round();
                      debugPrint(
                        '🎯 [ControlPanel-ProgressBar] onChangeEnd: $value, seekTo: $newPos seconds',
                      );
                      setState(() {
                        _draggingValue = null;
                      });
                      ref.read(playbackProvider.notifier).seekTo(newPos);
                    }
                    : null,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildProgressTimeText(
                totalTime > 0 ? _formatDuration(displayTime) : '--:--',
                onSurface,
              ),
              _buildProgressTimeText(
                totalTime > 0 ? _formatDuration(totalTime) : '--:--',
                onSurface,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Initial progress area before first server data: fixed UI values
  /// to keep layout identical with real state.
  Widget _buildInitialProgressBar() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            inactiveTrackColor: onSurface.withValues(alpha: 0.14),
            activeTrackColor: onSurface.withValues(alpha: 0.14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
            thumbColor: onSurface.withValues(alpha: 0.28),
            overlayColor: Colors.transparent,
            trackShape: const _CustomTrackShape(),
          ),
          child: Slider(value: 0, min: 0, max: 1, onChanged: null),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildProgressTimeText('0:00', onSurface),
              _buildProgressTimeText('0:00', onSurface),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressTimeText(String text, Color onSurface) {
    return Text(
      text,
      style: TextStyle(
        color: onSurface.withValues(alpha: 0.58),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildPlaybackControls(PlaybackState state) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final playbackMode = ref.read(playbackModeProvider);
    final bool hasSelectedDevice;

    if (playbackMode == PlaybackMode.miIoTDirect) {
      final directState = ref.read(directModeProvider);
      hasSelectedDevice =
          directState is DirectModeAuthenticated &&
          directState.playbackDeviceType.isNotEmpty;
    } else {
      hasSelectedDevice = ref.read(deviceProvider).selectedDeviceId != null;
    }

    final enabled = hasSelectedDevice && !state.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Transform.translate(
            offset: const Offset(-11, 0),
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(state.playMode.icon),
                iconSize: 22,
                color:
                    enabled
                        ? onSurface.withValues(alpha: 0.62)
                        : onSurface.withValues(alpha: 0.3),
                onPressed:
                    enabled
                        ? () {
                          final currentMode = state.playMode;
                          final nextMode =
                              PlayMode.values[(currentMode.index + 1) %
                                  PlayMode.values.length];
                          ref
                              .read(playbackProvider.notifier)
                              .switchPlayMode(nextMode);
                        }
                        : null,
                tooltip: state.playMode.displayName,
              ),
            ),
          ),
          _buildControlButton(
            icon: Icons.skip_previous_rounded,
            size: 32,
            enabled: enabled,
            color: onSurface,
            onPressed: () => ref.read(playbackProvider.notifier).previous(),
          ),
          _buildMainPlayButton(
            state,
            enabled,
            state.currentMusic?.isPlaying ?? false,
          ),
          _buildControlButton(
            icon: Icons.skip_next_rounded,
            size: 32,
            enabled: enabled,
            color: onSurface,
            onPressed: () => ref.read(playbackProvider.notifier).next(),
          ),
          Transform.translate(
            offset: const Offset(11, 0),
            child: SizedBox(
              width: 44,
              height: 44,
              child: GestureDetector(
                onLongPress:
                    enabled && state.timerMinutes > 0
                        ? () {
                          ref.read(playbackProvider.notifier).cancelTimer();
                        }
                        : null,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.timer_outlined),
                      iconSize: 22,
                      color:
                          enabled
                              ? (state.timerMinutes > 0
                                  ? Colors.orangeAccent
                                  : onSurface.withValues(alpha: 0.62))
                              : onSurface.withValues(alpha: 0.3),
                      onPressed:
                          enabled
                              ? () => _showTimerBottomSheet(context, state)
                              : null,
                    ),
                    if (state.timerMinutes > 0)
                      Positioned(
                        top: -1,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            '$state.timerMinutes',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required bool enabled,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon),
        iconSize: size,
        color: enabled ? color : onSurface.withValues(alpha: 0.35),
        onPressed: enabled ? onPressed : null,
      ),
    );
  }

  Widget _buildMainPlayButton(
    PlaybackState state,
    bool enabled,
    bool isPlaying,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _buttonAnimationController != null) {
        if (isPlaying) {
          _buttonAnimationController!.forward();
        } else {
          _buttonAnimationController!.reverse();
        }
      }
    });

    final accentColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap:
          enabled
              ? () {
                if (isPlaying) {
                  ref.read(playbackProvider.notifier).pauseMusic();
                } else {
                  ref.read(playbackProvider.notifier).resumeMusic();
                }
              }
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width:
            MediaQuery.of(context).size.width * 0.18 > 72
                ? 72
                : (MediaQuery.of(context).size.width * 0.18 < 60
                    ? 60
                    : MediaQuery.of(context).size.width * 0.18),
        height:
            MediaQuery.of(context).size.width * 0.18 > 72
                ? 72
                : (MediaQuery.of(context).size.width * 0.18 < 60
                    ? 60
                    : MediaQuery.of(context).size.width * 0.18),
        decoration: BoxDecoration(
          gradient:
              enabled
                  ? LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.9),
                      Color.lerp(accentColor, Colors.orangeAccent, 0.25)!
                          .withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                  : null,
          color:
              !enabled
                  ? Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.1)
                  : null,
          shape: BoxShape.circle,
          boxShadow:
              enabled
                  ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 32,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: -2,
                      offset: const Offset(0, 0),
                    ),
                  ]
                  : [],
        ),
        child: Center(
          child:
              state.isLoading
                  ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                      strokeWidth: 2.0,
                    ),
                  )
                  : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: isPlaying ? 32 : 36,
                    color: Colors.white,
                  ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(PlaybackState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
            onPressed: () => ref.read(playbackProvider.notifier).clearError(),
          ),
        ],
      ),
    );
  }

  /// 🎵 快捷操作按钮（播放模式切换 + 定时关机 + 加入收藏）
  /// 🎨 从封面图提取主色调 (已废弃,改用 _extractDominantColorFromProvider)
  Future<void> _extractDominantColor(String imageUrl) async {
    try {
      debugPrint('🎨 [ControlPanel] 开始提取封面主色调: $imageUrl');
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 [ControlPanel] 提取到的颜色: $extractedColor');

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 [ControlPanel] 颜色已应用到 UI');
      }
    } catch (e) {
      debugPrint('❌ [ControlPanel] 提取封面主色调失败: $e');
    }
  }

  /// 🎨 从已加载的 ImageProvider 提取主色调 (避免重复加载图片)
  Future<void> _extractDominantColorFromProvider(
    ImageProvider imageProvider,
  ) async {
    try {
      debugPrint('🎨 [ControlPanel] 从已加载的图片提取主色调');
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 [ControlPanel] 提取到的颜色: $extractedColor');

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 [ControlPanel] 颜色已应用到 UI');
      }
    } catch (e) {
      debugPrint('❌ [ControlPanel] 提取封面主色调失败: $e');
    }
  }

  void _showVolumeBottomSheet(BuildContext context, PlaybackState state) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '音量调节',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Consumer(
                builder: (context, ref, _) {
                  final playbackState = ref.watch(playbackProvider);
                  return Row(
                    children: [
                      Icon(
                        Icons.volume_mute_rounded,
                        color: onSurface.withValues(alpha: 0.5),
                        size: 24,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4.0,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8.0,
                            ),
                            activeTrackColor: onSurface.withValues(alpha: 0.8),
                            inactiveTrackColor: onSurface.withValues(
                              alpha: 0.1,
                            ),
                            thumbColor: onSurface,
                            overlayColor: Colors.transparent,
                          ),
                          child: Slider(
                            value: playbackState.volume.toDouble(),
                            min: 0,
                            max: 100,
                            onChanged: (value) {
                              ref
                                  .read(playbackProvider.notifier)
                                  .setVolumeLocal(value.round());
                            },
                            onChangeEnd: (value) {
                              ref
                                  .read(playbackProvider.notifier)
                                  .setVolume(value.round());
                            },
                          ),
                        ),
                      ),
                      Icon(
                        Icons.volume_up_rounded,
                        color: onSurface.withValues(alpha: 0.5),
                        size: 24,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// ⏰ 显示定时器底部弹窗选择器
  void _showTimerBottomSheet(BuildContext context, PlaybackState state) {
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final primaryColor = Theme.of(context).colorScheme.primary;

    showAppBottomSheet(
      context: context,
      isScrollControlled: true, // 允许自定义高度
      builder:
          (context) => AppBottomSheet(
            title: '定时关机',
            trailing:
                state.timerMinutes > 0
                    ? TextButton.icon(
                      onPressed: () {
                        ref.read(playbackProvider.notifier).cancelTimer();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('取消定时'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                      ),
                    )
                    : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 当前定时状态提示
                if (state.timerMinutes > 0)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orangeAccent.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: Colors.orangeAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '已设置 ${state.timerMinutes} 分钟后关机',
                            style: TextStyle(
                              color: onSurfaceColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 快捷时间选项（横向滚动）
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildTimerOption(context, state, 15, '15分钟'),
                        _buildTimerOption(context, state, 30, '30分钟'),
                        _buildTimerOption(context, state, 45, '45分钟'),
                        _buildTimerOption(context, state, 60, '1小时'),
                        _buildTimerOption(context, state, 90, '1.5小时'),
                        _buildTimerOption(context, state, 120, '2小时'),
                      ],
                    ),
                  ),
                ),

                // 自定义输入
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: '自定义时间（分钟）',
                      labelStyle: TextStyle(
                        color: onSurfaceColor.withOpacity(0.7),
                      ),
                      hintText: '输入1-999分钟',
                      hintStyle: TextStyle(
                        color: onSurfaceColor.withOpacity(0.4),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      prefixIcon: Icon(Icons.edit_rounded, color: primaryColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.check_circle_rounded,
                          color: primaryColor,
                        ),
                        onPressed: () {
                          // 这个按钮只是装饰，实际提交由 onSubmitted 处理
                        },
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: onSurfaceColor, fontSize: 16),
                    onSubmitted: (value) {
                      final minutes = int.tryParse(value);
                      if (minutes != null && minutes > 0 && minutes <= 999) {
                        ref
                            .read(playbackProvider.notifier)
                            .setTimerMinutes(minutes);
                        Navigator.pop(context);
                      } else {
                        // 显示错误提示
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('请输入有效的分钟数（1-999）'),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),

                SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  /// ⏰ 构建单个定时器选项卡片
  Widget _buildTimerOption(
    BuildContext context,
    PlaybackState state,
    int minutes,
    String label,
  ) {
    final isSelected = state.timerMinutes == minutes;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        ref.read(playbackProvider.notifier).setTimerMinutes(minutes);
        Navigator.pop(context);
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? primaryColor.withOpacity(0.15)
                  : onSurfaceColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryColor : onSurfaceColor.withOpacity(0.2),
            width: 2,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 36,
              color:
                  isSelected ? primaryColor : onSurfaceColor.withOpacity(0.6),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color:
                    isSelected ? primaryColor : onSurfaceColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放模式小角标 — 独立 ConsumerWidget 隔离 playbackModeProvider 的 watch 范围
class _PlaybackModeBadge extends ConsumerWidget {
  const _PlaybackModeBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playbackModeProvider);
    final isXiaomusic = mode == PlaybackMode.xiaomusic;

    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (isXiaomusic) {
      bgColor = Colors.blue.withValues(alpha: 0.08);
      fgColor = Colors.blue;
      icon = Icons.dns_rounded;
      label = 'xiaomusic';
    } else {
      bgColor = Colors.orange.withValues(alpha: 0.08);
      fgColor = Colors.orange;
      icon = Icons.wifi_tethering_rounded;
      label = '直连';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: fgColor.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fgColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fgColor,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomTrackShape extends RoundedRectSliderTrackShape {
  const _CustomTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 2.0;
    // Removed default horizontal padding (offset.dx)
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(0.0, trackTop, parentBox.size.width, trackHeight);
  }
}
