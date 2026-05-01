import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import '../../widgets/app_snackbar.dart';

class SponsorPage extends StatelessWidget {
  const SponsorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('赞赏支持'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 感谢卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),

              child: Column(
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    size: 48,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '感谢您的支持！',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'HMusic 是一个免费的音乐控制应用\n如果这个应用对您有帮助，欢迎赞赏支持开发者',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 赞赏码卡片
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '微信赞赏码',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 赞赏码图片
                  GestureDetector(
                    onLongPress: () => _saveQRCode(context),
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildQRCodeImage(colorScheme),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    '扫描上方二维码赞赏或长按保存到相册',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 其他支持方式
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.handshake_rounded,
                    color: colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '其他支持方式',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSupportItem(
                    context,
                    Icons.share_rounded,
                    '分享推荐',
                    '推荐给朋友使用',
                    () => _showShareDialog(context),
                  ),
                  const SizedBox(height: 8),
                  _buildSupportItem(
                    context,
                    Icons.feedback_rounded,
                    '反馈建议',
                    '帮助改进应用',
                    () => _showFeedbackDialog(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 温馨提示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '赞赏纯属自愿，应用永远免费使用！\n您的每一份支持都是对开发者最大的鼓励 ❤️',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurface.withOpacity(0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('分享应用'),
            content: const Text(
              '感谢您愿意推荐 HMusic！\n\n您可以将应用分享给朋友，或在社交媒体上推荐。每一次分享都是对开发者的支持！',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Clipboard.setData(
                    const ClipboardData(
                      text: '推荐一个好用的音乐控制应用：HMusic！功能强大，完全免费 🎵',
                    ),
                  );
                  AppSnackBar.showSuccess(context, '分享文案已复制到剪贴板');
                },
                child: const Text('复制分享文案'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('好的'),
              ),
            ],
          ),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('反馈建议'),
            content: const Text(
              '您的意见和建议对我们非常重要！\n\n如果您在使用过程中遇到问题或有改进建议，欢迎通过以下方式联系：\n\n• 邮件反馈\n• GitHub Issues\n• QQ群交流',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('好的'),
              ),
            ],
          ),
    );
  }

  Widget _buildQRCodeImage(ColorScheme colorScheme) {
    // 尝试加载赞赏码图片
    return Container(
      width: 200,
      height: 200,
      child: Image.asset(
        'assets/images/sponsor_qr_code.png',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // 图片加载失败时显示占位符
          return Container(
            width: 200,
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    size: 50,
                    color: colorScheme.primary.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '微信赞赏码',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '请添加图片到\nassets/images/',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveQRCode(BuildContext context) async {
    try {
      // 显示加载提示
      AppSnackBar.showInfo(context, '正在保存图片...');

      // 检查权限并请求
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final requestGranted = await Gal.requestAccess();
        if (!requestGranted) {
          AppSnackBar.showError(context, '需要相册访问权限才能保存图片');
          return;
        }
      }

      // 从assets加载图片
      final byteData = await rootBundle.load(
        'assets/images/sponsor_qr_code.png',
      );
      final bytes = byteData.buffer.asUint8List();

      // 保存到相册
      await Gal.putImageBytes(
        bytes,
        name:
            'xiaoai_music_sponsor_qr_${DateTime.now().millisecondsSinceEpoch}',
      );

      AppSnackBar.showSuccess(context, '赞赏码已保存到相册 📱');
    } catch (e) {
      print('保存赞赏码失败: $e');
      if (e.toString().contains('Unable to load asset')) {
        AppSnackBar.showError(context, '请先添加赞赏码图片');
      } else if (e.toString().contains('GalException')) {
        AppSnackBar.showError(context, '保存失败，请检查相册权限');
      } else {
        AppSnackBar.showError(context, '保存失败: ${e.toString()}');
      }
    }
  }
}
