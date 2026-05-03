import 'package:flutter/material.dart';

/// Centralized helper to show SnackBars above the bottom navigation bar
/// so they do not overlap it.
class AppSnackBar {
  const AppSnackBar._();

  /// Computes a bottom margin that safely clears the custom bottom navigation.
  /// Matches measurements defined in `MainPage._buildModernBottomNav`.
  static double _computeBottomMargin(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom; // iOS home indicator etc.
    final hasBottomInset = bottomInset > 0;

    const double navHeight = 68.0; // height of the navbar container
    const double navTopMargin = 10.0; // top margin above navbar
    final double navBottomMargin = hasBottomInset ? (bottomInset + 8.0) : 20.0;

    // Leave an extra gap above the navbar for visual separation.
    const double extraGap = 12.0;

    return navHeight + navTopMargin + navBottomMargin + extraGap;
  }

  /// Show a SnackBar ensuring it appears above the bottom navigation.
  static void show(BuildContext context, SnackBar base, {IconData? icon}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final margin = EdgeInsets.fromLTRB(
      24,
      0,
      24,
      _computeBottomMargin(context),
    );

    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = base.backgroundColor ?? colorScheme.surface;
    final onBackgroundColor = backgroundColor.computeLuminance() > 0.5 
        ? Colors.black87 
        : Colors.white;

    // Rebuild a SnackBar with modern styling
    final snackBar = SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: onBackgroundColor, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: DefaultTextStyle(
              style: TextStyle(
                color: onBackgroundColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              child: base.content,
            ),
          ),
        ],
      ),
      action: base.action,
      backgroundColor: backgroundColor,
      duration: base.duration,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: onBackgroundColor.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }

  /// Convenience for simple text messages.
  static void showText(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
    IconData? icon,
  }) {
    show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
      icon: icon,
    );
  }

  /// 🎯 显示成功提示（绿色）
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4CAF50),
        duration: duration,
        action: action,
      ),
      icon: Icons.check_circle_rounded,
    );
  }

  /// 🎯 显示错误提示（红色）
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE53935),
        duration: duration,
        action: action,
      ),
      icon: Icons.error_rounded,
    );
  }

  /// 🎯 显示警告提示（橙色）
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFFA000),
        duration: duration,
        action: action,
      ),
      icon: Icons.warning_rounded,
    );
  }

  /// 🎯 显示信息提示（蓝色）
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2196F3),
        duration: duration,
        action: action,
      ),
      icon: Icons.info_rounded,
    );
  }
}
