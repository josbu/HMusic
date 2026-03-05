import 'package:flutter/material.dart';

/// Shared layout utilities related to the floating bottom navigation overlay.
class AppLayout {
  const AppLayout._();

  static const double navHeight = 68.0; // matches _buildModernBottomNav
  static const double navTopMargin = 10.0;
  static const double navBottomMarginNoGesture = 16.0;

  /// Bottom margin of the floating nav bar.
  /// iPhone 等手势导航设备会保留少量安全间距，但避免离底部过高。
  static double bottomOverlayBottomMargin(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewPadding.bottom;
    final gestureInset = mediaQuery.systemGestureInsets.bottom;
    final effectiveInset =
        bottomInset > gestureInset ? bottomInset : gestureInset;
    if (effectiveInset <= 0) {
      return navBottomMarginNoGesture;
    }
    return (effectiveInset - 14.0).clamp(8.0, 18.0);
  }

  /// Total vertical space occupied by the floating bottom navigation overlay,
  /// including its top margin and bottom safe-area margin.
  static double bottomOverlayHeight(BuildContext context) {
    return navHeight + navTopMargin + bottomOverlayBottomMargin(context);
  }

  /// Suggested content bottom padding so the last item scrolls above the nav.
  static double contentBottomPadding(
    BuildContext context, {
    double extra = 12,
  }) {
    return bottomOverlayHeight(context) + extra;
  }
}
