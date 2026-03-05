import 'package:flutter_js/flutter_js.dart';

// 🔧 需要显式导入 fetch 扩展（flutter_js.dart 未导出此扩展）
// ignore: implementation_imports
import 'package:flutter_js/extensions/fetch.dart';

/// 创建统一的 JS 运行时
///
/// iOS/Android 统一使用 QuickJsRuntime2，
/// 避免 iOS 上 JavaScriptCore 对 LX Music 脚本的兼容性问题。
JavascriptRuntime createUnifiedJsRuntime() {
  Object? quickJsError;

  // 优先使用 QuickJsRuntime2（与现有脚本兼容性更好）。
  try {
    final runtime = QuickJsRuntime2();
    runtime.enableFetch();
    runtime.enableHandlePromises();
    return runtime;
  } catch (e) {
    quickJsError = e;
    final msg = e.toString();
    final isMissingQuickJsSymbol =
        msg.contains('jsNewRuntime') ||
        msg.contains('symbol not found') ||
        msg.contains('Failed to lookup symbol');
    if (isMissingQuickJsSymbol) {
      print('[JSRuntime] ⚠️ QuickJsRuntime2 符号缺失，回退到默认运行时: $e');
    } else {
      print('[JSRuntime] ⚠️ QuickJsRuntime2 初始化失败，回退到默认运行时: $e');
    }
  }

  // 兜底：在部分 iOS 环境中，QuickJS 符号可能缺失，回退默认运行时保证可用性。
  try {
    final runtime = getJavascriptRuntime();
    try {
      runtime.enableFetch();
    } catch (_) {}
    try {
      runtime.enableHandlePromises();
    } catch (_) {}
    print('[JSRuntime] ✅ 已回退到默认运行时');
    return runtime;
  } catch (fallbackError) {
    throw Exception(
      'JS运行时初始化失败: QuickJsRuntime2=$quickJsError; fallback=$fallbackError',
    );
  }
}
