import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 赞赏提示对话框
class SponsorPromptDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showNeverAskAgain;

  const SponsorPromptDialog({
    super.key,
    required this.title,
    required this.message,
    this.showNeverAskAgain = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1F26) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4D8D).withOpacity(isDark ? 0.15 : 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 30,
                color: Color(0xFFFF4D8D),
              ),
            ),

            const SizedBox(height: 16),

            // 标题
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            // 消息
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.6),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // 按钮
            Row(
              children: [
                // 稍后按钮
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colorScheme.onSurface.withOpacity(0.1),
                          ),
                        ),
                      ),
                      child: Text(
                        '稍后',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // 赞赏按钮
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(true);
                        context.push('/settings/sponsor');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4D8D),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.favorite_rounded, size: 16),
                      label: const Text('赞赏支持', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),

            // "不再提醒"选项
            if (showNeverAskAgain) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).pop('never'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '不再提醒',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.35),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 显示播放里程碑提示
  static Future<dynamic> showPlaysMilestone(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '恭喜解锁成就',
        message: '您已经用 HMusic 播放了 50 首歌曲\n如果这个应用对您有帮助\n欢迎赞赏支持开发者继续改进',
        showNeverAskAgain: false,
      ),
    );
  }

  /// 显示歌词里程碑提示
  static Future<dynamic> showLyricsMilestone(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '歌词大师',
        message: '已为您自动获取了 20 条歌词\n喜欢这个功能吗\n您的支持是开发者最大的动力',
        showNeverAskAgain: false,
      ),
    );
  }

  /// 显示使用天数里程碑提示
  static Future<dynamic> showDaysMilestone(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '感谢陪伴',
        message: '您已经使用 HMusic 一周啦\n感谢您的信任和支持\n如果觉得应用不错，欢迎赞赏',
        showNeverAskAgain: false,
      ),
    );
  }

  /// 显示30天间隔提示
  static Future<dynamic> showIntervalPrompt(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const SponsorPromptDialog(
        title: '继续支持开发',
        message: 'HMusic 一直在为您提供更好的体验\n如果您觉得应用有帮助\n欢迎赞赏支持开发者',
        showNeverAskAgain: true,
      ),
    );
  }
}
