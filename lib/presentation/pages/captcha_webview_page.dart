import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// WebView 验证码页面
/// 在 WebView 中显示小米验证码页面，用户完成验证后自动关闭
class CaptchaWebViewPage extends StatefulWidget {
  final String captchaUrl;
  final void Function(Map<String, String>? cookies) onVerificationComplete;

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
  bool _verificationHandled = false; // 防止重复处理
  String? _pendingStsUrl; // 等待处理的 STS 回调 URL
  Map<String, String>? _preStsCookies;
  final Dio _dio = Dio();
  static const MethodChannel _cookieChannel = MethodChannel('hmusic/cookies');

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
      )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('🌐 [WebView] 页面开始加载: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          // 🎯 关键修复：在导航请求阶段拦截 STS 回调
          // 不要等页面加载完成，因为 STS 页面可能返回 HTTP 错误
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🔗 [WebView] 导航请求: ${request.url}');

            // 防止重复处理
            if (_verificationHandled) {
              return NavigationDecision.prevent;
            }

            // 🎯 检测 STS 回调 URL
            if (request.url.contains('api2.mina.mi.com/sts')) {
              debugPrint('✅ [WebView] 检测到 STS 回调，验证已完成！');
              // 尝试在跳转前从当前页面（account.xiaomi.com）读取 Cookie
              _captureCookiesBeforeSts().then((gotToken) {
                if (gotToken) {
                  // 已拿到 token，阻止跳转到 STS 错误页
                  return;
                }
                _pendingStsUrl = request.url;
                _fetchStsFromUrl(request.url, preCookies: _preStsCookies);
              });

              // 允许导航，避免打断正常流程；若已拿到 token，会在回调中自动关闭
              return NavigationDecision.navigate;
            }

            // 🎯 处理登录完成回调（可能会重定向到 STS）
            if (request.url.contains('account.xiaomi.com/pass/serviceLoginAuth2/end')) {
              _captureCookiesBeforeSts().then((gotToken) {
                if (gotToken) {
                  return;
                }
                _fetchAuthEndFromUrl(request.url, preCookies: _preStsCookies);
              });
              return NavigationDecision.navigate;
            }

            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) async {
            debugPrint('🌐 [WebView] 页面加载完成: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }

            // 防止重复处理（备用检测，如果 onNavigationRequest 没有拦截到）
            if (_verificationHandled) {
              return;
            }

            // 🎯 备用检测：如果页面 URL 包含 STS，说明验证成功
            if (url.contains('api2.mina.mi.com/sts') || _pendingStsUrl != null) {
              debugPrint('✅ [WebView] 检测到验证完成 (STS 回调 - 备用检测)');
              _pendingStsUrl = null;

              // 🎯 直接读取页面内容，这是一个 JSON 响应，包含 serviceToken
              final success = await _extractServiceTokenFromPage();
              if (success) {
                _verificationHandled = true;
              } else {
                debugPrint('⚠️ [WebView] STS 页面未返回 token，等待用户继续验证');
              }
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ [WebView] 加载错误: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }

            if (!_verificationHandled && _pendingStsUrl != null) {
              _pendingStsUrl = null;
              debugPrint('⚠️ [WebView] STS 页面加载失败，尝试从 Cookie 获取认证信息');
              _extractCookies().then((cookies) {
                if (cookies == null) return;
                if (cookies.containsKey('serviceToken') ||
                    (cookies.containsKey('passToken') && cookies.containsKey('userId'))) {
                  _verificationHandled = true;
                  widget.onVerificationComplete(cookies);
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                }
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.captchaUrl));

    // 🎯 Android: 允许第三方 Cookie（部分小米登录流程需要）
    final platformController = _webViewController.platform;
    if (platformController is AndroidWebViewController) {
      final cookieManager = WebViewCookieManager();
      final androidCookieManager = cookieManager.platform;
      if (androidCookieManager is AndroidWebViewCookieManager) {
        androidCookieManager.setAcceptThirdPartyCookies(platformController, true);
      }
    }
  }

  /// 🎯 处理验证完成（在 onNavigationRequest 中调用）
  /// 当检测到导航到 STS URL 时，立即标记验证完成
  void _handleVerificationComplete() {
    debugPrint('🎯 [WebView] 处理验证完成...');

    // 标记验证完成
    final cookies = <String, String>{
      '_stsVerified': 'true',
    };

    debugPrint('🍪 [WebView] 验证完成，返回标记: _stsVerified=true');

    // 延迟一下确保状态更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        widget.onVerificationComplete(cookies);
        Navigator.of(context).pop();
      }
    });
  }

  /// 🎯 从 STS 页面提取 serviceToken
  /// STS 页面返回的是 JSON 格式，包含 serviceToken 等认证信息
  Future<bool> _extractServiceTokenFromPage() async {
    try {
      // 读取页面内容（JSON 格式）
      final pageContent = await _webViewController.runJavaScriptReturningResult(
        'document.body.innerText'
      );

      debugPrint('📄 [WebView] STS 页面内容: $pageContent');

      // 解析 JSON
      String jsonStr = pageContent.toString();
      if (!jsonStr.trim().startsWith('{') && !jsonStr.trim().startsWith('"')) {
        debugPrint('⚠️ [WebView] STS 页面不是 JSON，可能仍需要验证');
        return false;
      }
      // 移除引号包裹
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      }
      // 处理转义字符
      jsonStr = jsonStr.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');

      debugPrint('📄 [WebView] 清理后的 JSON: $jsonStr');

      final Map<String, dynamic> stsResponse = json.decode(jsonStr);

      debugPrint('📄 [WebView] STS 响应解析成功: ${stsResponse.keys}');

      // 🎯 提取关键认证信息
      final cookies = <String, String>{};

      // serviceToken 可能在不同字段中
      if (stsResponse.containsKey('serviceToken')) {
        cookies['serviceToken'] = stsResponse['serviceToken'].toString();
        debugPrint('✅ [WebView] 提取到 serviceToken');
      }

      if (stsResponse.containsKey('userId')) {
        cookies['userId'] = stsResponse['userId'].toString();
        debugPrint('✅ [WebView] 提取到 userId: ${cookies['userId']}');
      }

      if (stsResponse.containsKey('ssecurity')) {
        cookies['ssecurity'] = stsResponse['ssecurity'].toString();
        debugPrint('✅ [WebView] 提取到 ssecurity');
      }

      if (stsResponse.containsKey('passToken')) {
        cookies['passToken'] = stsResponse['passToken'].toString();
        debugPrint('✅ [WebView] 提取到 passToken');
      }

      if (stsResponse.containsKey('nonce')) {
        cookies['nonce'] = stsResponse['nonce'].toString();
        debugPrint('✅ [WebView] 提取到 nonce');
      }

      // 标记验证完成
      cookies['_stsVerified'] = 'true';

      debugPrint('🍪 [WebView] 最终提取的认证信息: ${cookies.keys}');

      if (cookies.isEmpty ||
          (!cookies.containsKey('serviceToken') &&
              !(cookies.containsKey('passToken') && cookies.containsKey('userId')))) {
        debugPrint('⚠️ [WebView] STS JSON 未包含 token 字段，继续等待验证');
        return false;
      }

      // 延迟一下确保用户能看到成功状态
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        widget.onVerificationComplete(cookies);
        Navigator.of(context).pop();
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ [WebView] 解析 STS 响应失败: $e');
      debugPrint('⚠️ [WebView] 尝试从 Cookie 中获取认证信息...');

      // 回退方案：从 Cookie 中获取
      var cookies = await _extractCookies();

      if (cookies == null || cookies.isEmpty) {
        return false;
      }

      if (cookies.containsKey('serviceToken') ||
          (cookies.containsKey('passToken') && cookies.containsKey('userId'))) {
        cookies['_stsVerified'] = 'true';
        if (mounted) {
          widget.onVerificationComplete(cookies);
          Navigator.of(context).pop();
        }
        return true;
      }

      return false;
    }
  }

  /// 🎯 直接请求 STS URL 获取 JSON（绕过 WebView 错误页）
  Future<void> _fetchStsFromUrl(String url, {Map<String, String>? preCookies}) async {
    if (_verificationHandled) return;
    try {
      final cookieHeader = _buildCookieHeader(preCookies);
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => true,
          followRedirects: true,
          headers: {
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
            'User-Agent': 'Mozilla/5.0 (Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
          },
        ),
      );

      debugPrint('🧪 [WebView] STS 请求状态: ${response.statusCode}, realUri: ${response.realUri}');
      final raw = response.data?.toString() ?? '';
      if (raw.isEmpty) return;

      final jsonStr = _extractJsonString(raw);
      if (jsonStr == null) return;

      final Map<String, dynamic> stsResponse = json.decode(jsonStr);
      final resultCookies = <String, String>{};

      if (stsResponse.containsKey('serviceToken')) {
        resultCookies['serviceToken'] = stsResponse['serviceToken'].toString();
      }
      if (stsResponse.containsKey('userId')) {
        resultCookies['userId'] = stsResponse['userId'].toString();
      }
      if (stsResponse.containsKey('ssecurity')) {
        resultCookies['ssecurity'] = stsResponse['ssecurity'].toString();
      }
      if (stsResponse.containsKey('passToken')) {
        resultCookies['passToken'] = stsResponse['passToken'].toString();
      }
      if (stsResponse.containsKey('nonce')) {
        resultCookies['nonce'] = stsResponse['nonce'].toString();
      }

      if (resultCookies.containsKey('serviceToken') ||
          (resultCookies.containsKey('passToken') &&
              resultCookies.containsKey('userId'))) {
        resultCookies['_stsVerified'] = 'true';
        _verificationHandled = true;
        if (mounted) {
          widget.onVerificationComplete(resultCookies);
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('⚠️ [WebView] STS 请求失败: $e');
    }
  }

  /// 🎯 直接请求 Auth2 end URL，获取可能的重定向到 STS
  Future<void> _fetchAuthEndFromUrl(String url, {Map<String, String>? preCookies}) async {
    if (_verificationHandled) return;
    try {
      final cookieHeader = _buildCookieHeader(preCookies);
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => true,
          followRedirects: false,
          headers: {
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
            'User-Agent': 'Mozilla/5.0 (Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
          },
        ),
      );

      final location = response.headers.value('location');
      debugPrint('🧪 [WebView] Auth2 end 状态: ${response.statusCode}, location: $location');

      if (location != null && location.contains('api2.mina.mi.com/sts')) {
        _fetchStsFromUrl(location, preCookies: preCookies);
      }
    } catch (e) {
      debugPrint('⚠️ [WebView] Auth2 end 请求失败: $e');
    }
  }

  Future<bool> _captureCookiesBeforeSts() async {
    try {
      final cookies = await _extractCookies();
      if (cookies == null || cookies.isEmpty) return false;
      _preStsCookies = cookies;

      // 若已包含必要 token，直接完成
      if (cookies.containsKey('serviceToken') ||
          (cookies.containsKey('passToken') && cookies.containsKey('userId'))) {
        cookies['_stsVerified'] = 'true';
        _verificationHandled = true;
        if (mounted) {
          widget.onVerificationComplete(cookies);
          Navigator.of(context).pop();
        }
        return true;
      }

      // 尝试通过原生 CookieManager 获取 HttpOnly Cookie
      final nativeCookies = await _getNativeCookies('https://account.xiaomi.com');
      if (nativeCookies.isNotEmpty) {
        _preStsCookies = nativeCookies;
        if (nativeCookies.containsKey('serviceToken') ||
            (nativeCookies.containsKey('passToken') && nativeCookies.containsKey('userId'))) {
          nativeCookies['_stsVerified'] = 'true';
          _verificationHandled = true;
          if (mounted) {
            widget.onVerificationComplete(nativeCookies);
            Navigator.of(context).pop();
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  String _buildCookieHeader(Map<String, String>? cookies) {
    if (cookies == null || cookies.isEmpty) return '';
    final pairs = <String>[];
    cookies.forEach((k, v) {
      pairs.add('$k=$v');
    });
    return pairs.join('; ');
  }

  Future<Map<String, String>> _getNativeCookies(String url) async {
    if (!Platform.isAndroid) return {};
    try {
      final raw = await _cookieChannel.invokeMethod<String>('getCookies', {'url': url});
      if (raw == null || raw.isEmpty) return {};
      debugPrint('🍪 [WebView] Native Cookie 原始字符串长度: ${raw.length}');
      return _parseCookieString(raw);
    } catch (_) {
      return {};
    }
  }

  Map<String, String> _parseCookieString(String cookieString) {
    final cookies = <String, String>{};
    final parts = cookieString.split(';');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx);
      final value = trimmed.substring(idx + 1);
      cookies[key] = value;
    }
    if (cookies.isNotEmpty) {
      debugPrint('🍪 [WebView] Native Cookie 字段: ${cookies.keys}');
    }
    return cookies;
  }

  String? _extractJsonString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      return trimmed;
    }
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return raw.substring(start, end + 1);
    }
    return null;
  }

  /// 🎯 从 WebView 中提取 Cookie（备用方案）
  Future<Map<String, String>?> _extractCookies() async {
    try {
      // 使用 JavaScript 获取 Cookie（必须在同域页面上）
      final cookieString = await _webViewController.runJavaScriptReturningResult(
        'document.cookie'
      );

      debugPrint('🍪 [WebView] 原始 Cookie 字符串: $cookieString');

      // 解析 Cookie 字符串
      final cookies = <String, String>{};
      final cleanCookieString = cookieString.toString().replaceAll('"', '');

      if (cleanCookieString.isNotEmpty && cleanCookieString != 'null') {
        final pairs = cleanCookieString.split('; ');
        for (final pair in pairs) {
          final index = pair.indexOf('=');
          if (index > 0) {
            final key = pair.substring(0, index);
            final value = pair.substring(index + 1);
            cookies[key] = value;
            final isSensitive = key == 'passToken' || key == 'serviceToken' || key == 'ssecurity';
            final displayValue = isSensitive
                ? '***'
                : (value.length > 20 ? "${value.substring(0, 20)}..." : value);
            debugPrint('🍪 [WebView] Cookie: $key=$displayValue');
          }
        }
      }

      return cookies.isNotEmpty ? cookies : null;
    } catch (e) {
      debugPrint('❌ [WebView] 提取 Cookie 失败: $e');
      return null;
    }
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
