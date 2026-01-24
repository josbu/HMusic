import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView 验证码页面
/// 在 WebView 中显示小米验证码页面，用户完成验证后自动关闭
class CaptchaWebViewPage extends StatefulWidget {
  final String captchaUrl;
  final VoidCallback onVerificationComplete;

  const CaptchaWebViewPage({
    super.key,
    required this.captchaUrl,
    required this.onVerificationComplete,
  });

  @override
  State<CaptchaWebViewPage> createState() => _CaptchaWebViewPageState();
}

class _CaptchaWebViewPageState extends State<CaptchaWebViewPage> {
  late WebViewController _webViewController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('🌐 [WebView] 页面开始加载: $url');
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            debugPrint('🌐 [WebView] 页面加载完成: $url');
            setState(() {
              _isLoading = false;
            });

            // 🎯 检测验证完成：如果导航到小米主页，说明验证成功
            if (url.contains('mi.com') && !url.contains('account.xiaomi.com')) {
              debugPrint('✅ [WebView] 检测到验证完成，用户已进入小米主页');
              // 延迟 1 秒后关闭，确保 Cookie 已保存
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  widget.onVerificationComplete();
                  Navigator.of(context).pop();
                }
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ [WebView] 加载错误: ${error.description}');
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.captchaUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小米账号验证'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
