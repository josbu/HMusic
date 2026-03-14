import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/direct_mode_provider.dart';

/// 播放模式选择页面
/// 首次启动或切换模式时展示，让用户选择使用场景
class PlaybackModeSelectionPage extends ConsumerStatefulWidget {
  const PlaybackModeSelectionPage({super.key});

  @override
  ConsumerState<PlaybackModeSelectionPage> createState() => _PlaybackModeSelectionPageState();
}

class _PlaybackModeSelectionPageState extends ConsumerState<PlaybackModeSelectionPage> with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B0B14) : Colors.white,
          ),
          child: Stack(
            children: [
              // 🎨 背景装饰光晕 (带动画)
              if (isDark) ...[
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Positioned(
                      top: -150 + (30 * _controller.value),
                      right: -150 + (20 * (1 - _controller.value)),
                      child: child!,
                    );
                  },
                  child: Container(
                    width: 450,
                    height: 450,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2196F3).withValues(alpha: 0.08),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Positioned(
                      bottom: -150 + (25 * (1 - _controller.value)),
                      left: -150 + (40 * _controller.value),
                      child: child!,
                    );
                  },
                  child: Container(
                    width: 450,
                    height: 450,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF4081).withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🏠 App Bar / Logo 区域
                      Container(
                        height: 120,
                        alignment: Alignment.centerLeft,
                        child: SvgPicture.asset(
                          'assets/hmusic-logo.svg',
                          width: 140,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF21B0A5), // 强制使用品牌 Teal 颜色
                            BlendMode.srcIn,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 🏷️ 标题区域
                      Text(
                        '选择连接方式',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF1A1B22),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '选择最适合你的方式来控制小米音箱',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.black54,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // 🗂️ 选项列表
                      _ModeCard(
                        icon: Icons.cloud_queue_rounded,
                        title: 'xiaomusic 登录',
                        subtitle: '通过 xiaomusic 服务端远程控制',
                        iconColor: const Color(0xFFFF4081),
                        isSelected: false,
                        onTap: () {
                          ref
                              .read(playbackModeProvider.notifier)
                              .setMode(PlaybackMode.xiaomusic);
                        },
                      ),

                      const SizedBox(height: 16),

                      _ModeCard(
                        icon: Icons.bolt_rounded,
                        title: '直连模式',
                        subtitle: '局域网直接控制 (无须服务器)',
                        iconColor: const Color(0xFF2196F3),
                        isSelected: true,
                        onTap: () {
                          ref
                              .read(playbackModeProvider.notifier)
                              .setMode(PlaybackMode.miIoTDirect);
                        },
                      ),

                      const Spacer(),

                      // 💡 底部提示
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.black45,
                              ),
                              children: [
                                const TextSpan(text: '第一次使用 HMusic? '),
                                TextSpan(
                                  text: '查看设置指南',
                                  style: const TextStyle(
                                    color: Color(0xFFFF4081),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon; // 改为 IconData
  final String title;
  final String subtitle;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1E2C).withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // 🧊 图标容器
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 20),
              // 📝 文字内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1A1B22),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              // ➡️ 箭头
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
