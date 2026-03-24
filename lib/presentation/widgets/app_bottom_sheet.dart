import 'dart:ui';
import 'package:flutter/material.dart';

/// 使用统一参数显示模态底部弹窗。
///
/// 所有基础参数（useSafeArea 等）由全局主题和此方法统一管理，
/// 确保应用内所有底部弹窗行为一致。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => AppBottomSheetContainer(
      child: builder(context),
    ),
  );
}

/// 底部弹窗的玻璃蒙层容器
class AppBottomSheetContainer extends StatelessWidget {
  final Widget child;

  const AppBottomSheetContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: isDark 
                ? const Color(0xFF1A1B22).withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.4),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 统一的底部弹窗容器，提供可选的标题行和一致的视觉样式。
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    this.title,
    this.centerTitle = false,
    this.trailing,
    required this.child,
  });

  /// 顶部标题文字。传 null 则不显示标题行（如简单操作菜单）。
  final String? title;

  /// 是否居中显示标题。默认左对齐。
  final bool centerTitle;

  /// 标题行尾部控件（如刷新按钮、取消按钮等）。
  final Widget? trailing;

  /// 标题下方的主内容区域。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // 自定义拖拽指示条
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                trailing != null ? 12 : 24,
                16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: -0.5,
                          ),
                      textAlign:
                          centerTitle ? TextAlign.center : TextAlign.start,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

