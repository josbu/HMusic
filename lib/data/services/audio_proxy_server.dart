import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// 音频代理服务器
/// 用于代理音乐CDN的音频流，解决小爱音箱无法直接访问某些CDN的问题
class AudioProxyServer {
  HttpServer? _server;
  final Dio _dio = Dio();
  int _port = 8090;
  String? _localIp;

  // 🎯 健康检查定时器
  Timer? _healthCheckTimer;

  // 🎯 请求统计
  int _totalRequests = 0;
  int _successRequests = 0;
  int _failedRequests = 0;

  // 服务器是否正在运行
  bool get isRunning => _server != null;

  // 获取代理服务器地址
  String get serverUrl => 'http://$_localIp:$_port';

  // 获取本地IP地址
  String? get localIp => _localIp;

  // 获取统计信息
  Map<String, int> get stats => {
    'total': _totalRequests,
    'success': _successRequests,
    'failed': _failedRequests,
  };

  /// 启动代理服务器
  Future<bool> start({int port = 8090}) async {
    if (_server != null) {
      debugPrint('⚠️ [ProxyServer] 服务器已在运行');
      return true;
    }

    try {
      _port = port;

      // 🔍 获取本地IP地址
      _localIp = await _getLocalIp();
      if (_localIp == null) {
        debugPrint('❌ [ProxyServer] 无法获取本地IP地址');
        return false;
      }

      debugPrint('🌐 [ProxyServer] 本地IP: $_localIp');

      // 🚀 启动HTTP服务器
      final handler = const shelf.Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(shelf.logRequests())
          .addHandler(_router);

      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);

      debugPrint('✅ [ProxyServer] 代理服务器已启动: $serverUrl');

      // 🎯 启动健康检查
      _startHealthCheck();

      return true;
    } catch (e) {
      debugPrint('❌ [ProxyServer] 启动失败: $e');
      _server = null;
      return false;
    }
  }

  /// 🎯 启动健康检查（每30秒检查一次）
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _performHealthCheck();
    });
    debugPrint('⏰ [ProxyServer] 健康检查已启动');
  }

  /// 🎯 执行健康检查
  void _performHealthCheck() {
    if (_server == null) {
      debugPrint('⚠️ [ProxyServer] 健康检查失败：服务器未运行');
      _healthCheckTimer?.cancel();
      return;
    }

    debugPrint(
      '💚 [ProxyServer] 健康检查通过 - 统计: ${_totalRequests}次请求, ${_successRequests}次成功, ${_failedRequests}次失败',
    );
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server != null) {
      // 🎯 停止健康检查
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;

      await _server!.close();
      _server = null;

      debugPrint('👋 [ProxyServer] 代理服务器已停止');
      debugPrint(
        '📊 [ProxyServer] 最终统计: ${_totalRequests}次请求, ${_successRequests}次成功, ${_failedRequests}次失败',
      );
    }
  }

  /// 路由处理
  Future<shelf.Response> _router(shelf.Request request) async {
    final path = request.url.path;

    if (path == 'proxy') {
      return await _handleProxy(request);
    } else if (path == 'health') {
      return shelf.Response.ok('OK');
    }

    return shelf.Response.notFound('Not Found');
  }

  /// 处理代理请求
  Future<shelf.Response> _handleProxy(shelf.Request request) async {
    _totalRequests++; // 🎯 统计总请求数

    try {
      // 获取 base64 编码的 URL
      final urlB64 = request.url.queryParameters['urlb64'];
      if (urlB64 == null || urlB64.isEmpty) {
        _failedRequests++; // 🎯 统计失败请求
        return shelf.Response.badRequest(body: 'Missing urlb64 parameter');
      }

      // 解码 URL
      final urlBytes = base64.decode(urlB64);
      final originalUrl = utf8.decode(urlBytes);
      debugPrint('🔗 [ProxyServer] 代理请求 #$_totalRequests: $originalUrl');

      // 🔒 HTTP → HTTPS 升级（防止音乐 CDN 因 HTTP 协议返回 403）
      // 网易云、QQ 等主流音乐 CDN 仅支持 HTTPS，但 JS 解析器返回的 URL 可能是 http://
      // 浏览器会自动用 HSTS 升级，代理服务器需要手动升级
      final targetUrl = _upgradeToHttps(originalUrl);
      if (targetUrl != originalUrl) {
        debugPrint('🔒 [ProxyServer] HTTP → HTTPS 升级: $targetUrl');
      }

      // 🎯 根据上游 URL 域名动态构建请求头（防盗链需要正确的 UA 和 Referer）
      final upstreamHeaders = _getUpstreamHeaders(targetUrl);


      // 🎯 透传客户端的 Range 请求头（音箱通常会发 Range: bytes=0- 进行分段请求）
      final rangeHeader = request.headers['range'] ?? request.headers['Range'];
      if (rangeHeader != null) {
        upstreamHeaders['Range'] = rangeHeader;
        debugPrint('📦 [ProxyServer] 透传 Range 头: $rangeHeader');
      }

      // 🎯 发起HTTP请求获取音频流
      final response = await _dio.get(
        targetUrl,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          headers: upstreamHeaders,
          validateStatus: (status) => status! < 500,
        ),
      );

      // 接受 200 (完整响应) 和 206 (分段响应，Range 请求的正常返回)
      final statusCode = response.statusCode ?? 500;
      if (statusCode != 200 && statusCode != 206) {
        _failedRequests++; // 🎯 统计失败请求
        // 🔍 对 403 输出更详细的诊断信息，方便判断是 URL 过期还是 Referer 不对
        if (statusCode == 403) {
          final lowerUrl = targetUrl.toLowerCase();
          final hasUA = upstreamHeaders.containsKey('User-Agent');
          debugPrint(
            '❌ [ProxyServer] 上游 403 Forbidden'
            ' | URL: ${targetUrl.substring(0, targetUrl.length.clamp(0, 80))}...'
            ' | 已发送 Referer: ${upstreamHeaders['Referer'] ?? '无'}'
            ' | UA: ${hasUA ? '已设置' : '未设置'}'
            ' | 可能原因: (1) CDN URL 已过期 (2) 需要额外 Cookie',
          );
          // 检测网易云 URL 是否含有过期时间戳
          if (lowerUrl.contains('music.126.net') || lowerUrl.contains('ntes.com')) {
            final match = RegExp(r'/(\d{14})/').firstMatch(targetUrl);
            if (match != null) {
              try {
                final ts = match.group(1)!;
                final genTime = DateTime(
                  int.parse(ts.substring(0, 4)),
                  int.parse(ts.substring(4, 6)),
                  int.parse(ts.substring(6, 8)),
                  int.parse(ts.substring(8, 10)),
                  int.parse(ts.substring(10, 12)),
                  int.parse(ts.substring(12, 14)),
                );
                final ageMin = DateTime.now().difference(genTime).inMinutes;
                debugPrint(
                  '⏰ [ProxyServer] 网易云 URL 生成于 $ageMin 分钟前'
                  '${ageMin >= 20 ? ' ← 【已超 20 分钟，URL 可能已过期！】' : ' (仍在有效期内)'}',
                );
              } catch (_) {}
            }
          }
        } else {
          debugPrint('❌ [ProxyServer] 上游响应错误: $statusCode');
        }
        return shelf.Response(statusCode);
      }

      // 🎵 获取响应头（包含 206 相关的 Content-Range）
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        // 转发必要的响应头
        final lower = name.toLowerCase();
        if (lower == 'content-type' ||
            lower == 'content-length' ||
            lower == 'accept-ranges' ||
            lower == 'content-range') {
          headers[name] = values.join(', ');
        }
      });

      // 📡 流式转发音频数据
      final stream = response.data.stream;
      _successRequests++; // 🎯 统计成功请求
      debugPrint(
        '✅ [ProxyServer] 开始流式转发音频数据 [HTTP $statusCode] (成功率: ${(_successRequests / _totalRequests * 100).toStringAsFixed(1)}%)',
      );

      // 206 Partial Content 需要原样返回给客户端（小爱音箱），否则音箱会认为请求失败
      return shelf.Response(statusCode, body: stream, headers: headers);
    } catch (e) {
      _failedRequests++; // 🎯 统计失败请求
      debugPrint('❌ [ProxyServer] 代理请求失败: $e');
      return shelf.Response.internalServerError(body: 'Proxy error: $e');
    }
  }

  /// CORS 中间件
  shelf.Middleware _corsMiddleware() {
    return (innerHandler) {
      return (request) async {
        final response = await innerHandler(request);
        return response.change(
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': '*',
          },
        );
      };
    };
  }

  /// 获取本地IP地址
  Future<String?> _getLocalIp() async {
    try {
      // 🔍 获取所有网络接口
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final sortedInterfaces =
          interfaces.toList()..sort(
            (a, b) => _interfacePriority(
              a.name,
            ).compareTo(_interfacePriority(b.name)),
          );

      // 优先选择 WiFi/以太网接口
      for (var interface in sortedInterfaces) {
        // 跳过虚拟网络接口
        if (interface.name.contains('docker') ||
            interface.name.contains('veth') ||
            interface.name.contains('br-')) {
          continue;
        }

        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            // 优先选择局域网IP
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.')) {
              debugPrint('📱 [ProxyServer] 选择网络接口: ${interface.name} ($ip)');
              return ip;
            }
          }
        }
      }

      // 如果没有找到局域网IP，返回第一个可用的
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }

      return null;
    } catch (e) {
      debugPrint('❌ [ProxyServer] 获取IP地址失败: $e');
      return null;
    }
  }

  int _interfacePriority(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('wlan') || lower.contains('wifi') || lower == 'en0') {
      return 0;
    }
    if (lower.contains('eth') || lower.startsWith('en')) {
      return 1;
    }
    if (lower.contains('pdp') ||
        lower.contains('rmnet') ||
        lower.contains('wwan')) {
      return 3;
    }
    return 2;
  }

  Future<void> refreshLocalIp() async {
    final newIp = await _getLocalIp();
    if (newIp == null) {
      debugPrint('⚠️ [ProxyServer] 刷新本地IP失败');
      return;
    }
    if (_localIp != newIp) {
      debugPrint('🔄 [ProxyServer] 本地IP已更新: $_localIp -> $newIp');
      _localIp = newIp;
    }
  }

  /// 生成代理URL
  String getProxyUrl(String originalUrl) {
    final urlB64 = base64.encode(utf8.encode(originalUrl));
    return '$serverUrl/proxy?urlb64=$urlB64';
  }

  /// 🔒 将音乐 CDN 的 HTTP URL 升级为 HTTPS
  /// 网易云、QQ 音乐等 CDN 实际只接受 HTTPS，但 JS 解析器返回的 URL 有时是 http://
  /// 浏览器用 HSTS 自动升级，代理服务器需要手动处理
  static String _upgradeToHttps(String url) {
    if (!url.startsWith('http://')) return url;

    final lowerUrl = url.toLowerCase();
    // 已知仅支持 HTTPS 的音乐 CDN 域名
    const httpsOnlyDomains = [
      'music.126.net',   // 网易云音乐
      'ntes.com',        // 网易
      'qq.com',          // QQ 音乐
      'qqmusic.',        // QQ 音乐
      'kugou.com',       // 酷狗
      'kgmusic.',        // 酷狗
      'kuwo.cn',         // 酷我
      'kuwo.com',        // 酷我
      'migu.cn',         // 咪咕
      'miguvideo.',      // 咪咕
    ];

    if (httpsOnlyDomains.any((d) => lowerUrl.contains(d))) {
      return 'https://' + url.substring('http://'.length);
    }

    return url;
  }

  /// 🎯 根据上游 URL 域名构建合适的请求头
  /// 音乐 CDN 通常有防盗链检测，需要正确的 User-Agent 和 Referer
  static const String _browserUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Map<String, String> _getUpstreamHeaders(String url) {
    final headers = <String, String>{
      'User-Agent': _browserUA,
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Connection': 'Keep-Alive',
    };

    // 根据 CDN 域名匹配平台，添加对应 Referer
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('music.126.net') ||
        lowerUrl.contains('163.com') ||
        lowerUrl.contains('ntes.com')) {
      // 网易云音乐
      headers['Referer'] = 'https://music.163.com/';
    } else if (lowerUrl.contains('qq.com') || lowerUrl.contains('qqmusic.')) {
      // QQ 音乐
      headers['Referer'] = 'https://y.qq.com/';
    } else if (lowerUrl.contains('kugou.com') ||
        lowerUrl.contains('kgmusic.')) {
      // 酷狗音乐
      headers['Referer'] = 'https://www.kugou.com/';
    } else if (lowerUrl.contains('kuwo.cn') || lowerUrl.contains('kuwo.com')) {
      // 酷我音乐
      headers['Referer'] = 'https://www.kuwo.cn/';
    } else if (lowerUrl.contains('migu.cn') ||
        lowerUrl.contains('miguvideo.')) {
      // 咪咕音乐
      headers['Referer'] = 'https://www.migu.cn/';
    }

    return headers;
  }
}
