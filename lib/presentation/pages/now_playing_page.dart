import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/playback_provider.dart';
import '../providers/device_provider.dart';
import '../providers/direct_mode_provider.dart'; // 🎯 直连模式Provider
import '../providers/lyric_provider.dart';
import '../widgets/app_snackbar.dart';
import 'lyrics_page.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  AnimationController? _albumAnimationController;
  Color? _dominantColor;
  String? _lastCoverUrl;
  String? _colorExtractedUrl; // 🔧 已提取颜色的封面 URL（防止重复提取）

  @override
  void initState() {
    super.initState();
    _albumAnimationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    // 🎨 颜色提取现在由 CachedNetworkImage.imageBuilder 自动处理，不需要在这里手动触发
  }

  @override
  void dispose() {
    _albumAnimationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final current = playback.currentMusic;
    final coverUrl = playback.albumCoverUrl;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isPlaying = current?.isPlaying ?? false;

    debugPrint('🎨 build: coverUrl=$coverUrl, _lastCoverUrl=$_lastCoverUrl');

    // 🎨 当封面 URL 变化时，清除旧颜色 (颜色提取由 CachedNetworkImage.imageBuilder 处理)
    if (coverUrl != _lastCoverUrl) {
      debugPrint('🎨 检测到封面 URL 变化: $_lastCoverUrl -> $coverUrl');
      _lastCoverUrl = coverUrl;
      _dominantColor = null; // 立即清除旧颜色,等待新图片加载后提取
      _colorExtractedUrl = null; // 🔧 重置提取标记，允许新封面提取颜色
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _albumAnimationController == null) {
        return;
      }

      if (isPlaying) {
        if (!_albumAnimationController!.isAnimating) {
          _albumAnimationController!.repeat();
        }
      } else {
        if (_albumAnimationController!.isAnimating) {
          _albumAnimationController!.stop();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('正在播放'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              _buildAlbumCover(coverUrl, onSurface, isPlaying),
              const SizedBox(height: 20),
              Text(
                current?.curMusic ?? '暂无播放',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                current != null && current.curPlaylist.isNotEmpty
                    ? current.curPlaylist
                    : '未知歌单', // ✅ 提供默认文本
                style: TextStyle(
                  color: onSurface.withValues(
                    alpha:
                        current != null && current.curPlaylist.isNotEmpty
                            ? 0.7
                            : 0.4, // ✅ 未知歌单显示更淡
                  ),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              if (current != null)
                _ProgressBar(
                  currentTime: current.offset,
                  totalTime: current.duration,
                  // 🔧 只有当歌曲名为空时或设备不支持 seek 时才禁用进度条
                  disabled: current.curMusic.isEmpty || !playback.seekEnabled,
                  isLocalMode: playback.isLocalMode, // 🎵 传递播放模式信息
                )
              else
                const _ProgressBar(
                  currentTime: 0,
                  totalTime: 0,
                  disabled: true,
                  isLocalMode: false, // 🎵 默认远程模式
                ),
              const SizedBox(height: 16),
              _Controls(),
              const SizedBox(height: 16),
              _Volume(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumCover(String? coverUrl, Color onSurface, bool isPlaying) {
    final glowColor = _dominantColor ?? Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.of(context).size.width;
    final containerSize = (screenWidth - 32).clamp(220.0, 360.0).toDouble();
    final artworkSize = containerSize * 0.60;
    final frameInset = containerSize * 0.05;
    final coverTop = (containerSize - artworkSize) / 2;
    final recordLeft = frameInset + artworkSize * 0.5;
    debugPrint('🎨 当前光圈颜色: $glowColor (提取的颜色: $_dominantColor)');

    return GestureDetector(
      onTap: () {
        debugPrint('🎤 [点击封面] 触发点击事件');
        _openLyricsPage();
      },
      behavior: HitTestBehavior.opaque, // 🔧 确保整个区域都可点击
      child: SizedBox(
        width: containerSize,
        height: containerSize,
        child: Stack(
          children: [
            Positioned(
              left: recordLeft,
              top: coverTop,
              child: RotationTransition(
                turns: _albumAnimationController ?? kAlwaysCompleteAnimation,
                child: Container(
                  width: artworkSize,
                  height: artworkSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF111111),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final factor in [0.88, 0.74, 0.60])
                        Container(
                          width: artworkSize * factor,
                          height: artworkSize * factor,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 0.8,
                            ),
                          ),
                        ),
                      Container(
                        width: artworkSize * 0.34,
                        height: artworkSize * 0.34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: onSurface.withValues(alpha: 0.08),
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
                                            _buildDefaultArtwork(onSurface),
                                  )
                                  : _buildDefaultArtwork(onSurface),
                        ),
                      ),
                      Container(
                        width: artworkSize * 0.06,
                        height: artworkSize * 0.06,
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
              left: frameInset,
              top: coverTop,
              child: Container(
                width: artworkSize,
                height: artworkSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: onSurface.withValues(alpha: 0.08),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.32),
                      blurRadius: 20,
                      offset: const Offset(12, 8),
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
                            imageBuilder: (context, imageProvider) {
                              if (_colorExtractedUrl != coverUrl) {
                                _colorExtractedUrl = coverUrl;
                                Future.delayed(
                                  const Duration(milliseconds: 300),
                                  () {
                                    if (mounted &&
                                        coverUrl ==
                                            ref
                                                .read(playbackProvider)
                                                .albumCoverUrl) {
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
                                (context, url) =>
                                    _buildDefaultArtwork(onSurface),
                            errorWidget:
                                (context, url, error) =>
                                    _buildDefaultArtwork(onSurface),
                          )
                          : _buildDefaultArtwork(onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultArtwork(Color onSurface) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            onSurface.withValues(alpha: 0.02),
            onSurface.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 72,
          color: onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  /// 打开歌词页面
  void _openLyricsPage() {
    final current = ref.read(playbackProvider).currentMusic;

    debugPrint('🎤 [打开歌词] 开始执行');
    debugPrint('🎤 [打开歌词] 当前播放状态: ${current != null}');
    debugPrint('🎤 [打开歌词] 歌曲名: ${current?.curMusic}');

    if (current == null || current.curMusic.isEmpty) {
      debugPrint('⚠️ [打开歌词] 当前没有播放歌曲,不打开歌词页面');
      // 显示提示
      AppSnackBar.showWarning(context, '当前没有播放歌曲');
      return;
    }

    debugPrint('🎤 [打开歌词] 准备打开歌词页面: ${current.curMusic}');

    // 加载歌词
    ref.read(lyricProvider.notifier).loadLyrics(current.curMusic);

    // 导航到歌词页面
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const LyricsPage()));

    debugPrint('✅ [打开歌词] 页面跳转完成');
  }

  /// 🎨 从已加载的 ImageProvider 提取主色调 (避免重复加载图片)
  Future<void> _extractDominantColorFromProvider(
    ImageProvider imageProvider,
  ) async {
    try {
      debugPrint('🎨 [NowPlaying] 从已加载的图片提取主色调');
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 10,
      );

      final extractedColor =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color;

      debugPrint('🎨 [NowPlaying] 提取到的颜色: $extractedColor');
      debugPrint(
        '🎨 [NowPlaying] 主色调: ${paletteGenerator.dominantColor?.color}',
      );
      debugPrint(
        '🎨 [NowPlaying] 鲜艳色: ${paletteGenerator.vibrantColor?.color}',
      );

      if (mounted) {
        setState(() {
          _dominantColor = extractedColor;
        });
        debugPrint('🎨 [NowPlaying] 颜色已应用到 UI');
      }
    } catch (e) {
      // 提取颜色失败，使用默认颜色
      debugPrint('❌ [NowPlaying] 提取封面主色调失败: $e');
    }
  }
}

class _ProgressBar extends ConsumerStatefulWidget {
  final int currentTime;
  final int totalTime;
  final bool disabled;
  final bool isLocalMode; // 🎵 是否为本地播放模式

  const _ProgressBar({
    required this.currentTime,
    required this.totalTime,
    this.disabled = false,
    this.isLocalMode = false, // 🎵 默认为远程模式（不可拖动）
  });

  @override
  ConsumerState<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends ConsumerState<_ProgressBar> {
  double? _draggingValue; // 🔧 拖动时的临时进度值

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // 🔧 使用拖动值或实际进度值
    final displayTime =
        _draggingValue != null
            ? (_draggingValue! * widget.totalTime).round()
            : widget.currentTime;

    final progress =
        widget.totalTime > 0
            ? (displayTime / widget.totalTime).clamp(0.0, 1.0)
            : 0.0;

    debugPrint(
      '🎯 [ProgressBar] disabled=${widget.disabled}, isLocalMode=${widget.isLocalMode}, progress=$progress, currentTime=${widget.currentTime}, totalTime=${widget.totalTime}',
    );

    // 🎵 本地播放模式和直连模式都允许拖动进度条
    // 直连模式通过 player_set_positon ubus API 实现 seek
    final bool canSeek = !widget.disabled;

    return Column(
      children: [
        Slider(
          value: progress,
          onChanged:
              canSeek
                  ? (v) {
                    // 🔧 拖动时更新临时值,实时显示进度
                    debugPrint('🎯 [ProgressBar] onChanged: $v');
                    setState(() {
                      _draggingValue = v;
                    });
                  }
                  : null, // 🎵 远程播放模式禁用拖动
          onChangeEnd:
              canSeek
                  ? (v) {
                    // 🔧 拖动结束,清除临时值并执行 seek
                    final seekSeconds = (v * widget.totalTime).round();
                    debugPrint(
                      '🎯 [ProgressBar] onChangeEnd: $v, seekTo: $seekSeconds seconds',
                    );
                    setState(() {
                      _draggingValue = null;
                    });
                    ref.read(playbackProvider.notifier).seekTo(seekSeconds);
                  }
                  : null, // 🎵 远程播放模式禁用拖动
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(displayTime),
              style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
            ),
            Text(
              _fmt(widget.totalTime),
              style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(int seconds) {
    if (seconds <= 0) return '0:00';
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Controls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
    final playbackMode = ref.watch(playbackModeProvider);

    // 🎯 根据播放模式检查设备是否可用
    bool hasDevice = false;
    if (playbackMode == PlaybackMode.miIoTDirect) {
      // 直连模式：检查是否已登录且选择了播放设备
      final directState = ref.watch(directModeProvider);
      hasDevice =
          directState is DirectModeAuthenticated &&
          directState
              .playbackDeviceType
              .isNotEmpty; // 🔧 修复：检查 playbackDeviceType
    } else {
      // xiaomusic 模式：检查是否选择了设备
      hasDevice = ref.read(deviceProvider).selectedDeviceId != null;
    }

    final enabled = hasDevice && !state.isLoading;
    final isPlaying = state.currentMusic?.isPlaying ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        IconButton(
          onPressed:
              enabled
                  ? () => ref.read(playbackProvider.notifier).previous()
                  : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 36,
        ),
        ElevatedButton(
          onPressed:
              enabled
                  ? () {
                    if (isPlaying) {
                      ref.read(playbackProvider.notifier).pauseMusic();
                    } else {
                      ref.read(playbackProvider.notifier).resumeMusic();
                    }
                  }
                  : null,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(18),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 36,
          ),
        ),
        IconButton(
          onPressed:
              enabled ? () => ref.read(playbackProvider.notifier).next() : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 36,
        ),
      ],
    );
  }
}

class _Volume extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(
          Icons.volume_mute_rounded,
          color: onSurface.withValues(alpha: 0.6),
          size: 16,
        ),
        Expanded(
          child: Slider(
            value: state.volume.toDouble(),
            min: 0,
            max: 100,
            onChanged:
                (v) => ref
                    .read(playbackProvider.notifier)
                    .setVolumeLocal(v.round()),
            onChangeEnd:
                (v) => ref.read(playbackProvider.notifier).setVolume(v.round()),
          ),
        ),
        Icon(
          Icons.volume_up_rounded,
          color: onSurface.withValues(alpha: 0.6),
          size: 16,
        ),
      ],
    );
  }
}
