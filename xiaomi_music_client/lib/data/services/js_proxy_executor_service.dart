import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';

/// JS脚本代理执行器服务
/// 让JS脚本自己处理所有请求，我们只负责接收结果
class JSProxyExecutorService {
  final Dio _dio = Dio();
  JavascriptRuntime? _runtime;
  String? _currentScript;
  bool _isInitialized = false;

  /// 初始化JS执行环境
  Future<void> initialize() async {
    if (_isInitialized) return;

    _runtime = getJavascriptRuntime();
    await _setupLXMusicEnvironment();
    _isInitialized = true;

    print('[JSProxy] ✅ JS执行环境初始化完成');
  }

  /// 设置LX Music运行环境
  Future<void> _setupLXMusicEnvironment() async {
    if (_runtime == null) return;

    // 注入LX Music环境模拟
    final lxEnvironment = '''
      // 模拟globalThis.lx环境
      globalThis.lx = {
        EVENT_NAMES: {
          request: 'request',
          inited: 'inited',
          updateAlert: 'updateAlert'
        },
        
        // 网络请求函数 - 通过Flutter代理
        request: function(url, options, callback) {
          console.log('[LXEnv] 发起网络请求:', url);
          
          // 调用Flutter的网络请求代理
          const requestId = 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
          globalThis._pendingRequests = globalThis._pendingRequests || {};
          globalThis._pendingRequests[requestId] = callback;
          
          // 发送请求给Flutter
          globalThis._flutterRequestProxy(JSON.stringify({
            id: requestId,
            url: url,
            options: options || {}
          }));
        },
        
        // 事件监听
        on: function(eventName, handler) {
          console.log('[LXEnv] 注册事件监听:', eventName);
          globalThis._lxHandlers = globalThis._lxHandlers || {};
          globalThis._lxHandlers[eventName] = handler;
        },
        
        // 发送事件
        send: function(eventName, data) {
          console.log('[LXEnv] 发送事件:', eventName, data);
          globalThis._flutterEventSender(JSON.stringify({
            event: eventName,
            data: data
          }));
        },
        
        // 工具函数
        utils: {
          buffer: {
            from: function(data, encoding) {
              return { data: data, encoding: encoding || 'utf-8' };
            },
            bufToString: function(buf, encoding) {
              if (encoding === 'base64') {
                return btoa(unescape(encodeURIComponent(buf.data)));
              } else if (encoding === 'hex') {
                return buf.data.split('').map(c => 
                  c.charCodeAt(0).toString(16).padStart(2, '0')
                ).join('');
              }
              return buf.data;
            }
          }
        },
        
        // 环境信息
        env: 'desktop',
        version: '1.0.0',
        currentScriptInfo: {
          version: '1.0.0'
        }
      };
      
      // 初始化全局变量
      globalThis._lxHandlers = {};
      globalThis._pendingRequests = {};
      globalThis._musicSources = {};
      
      console.log('[LXEnv] ✅ LX Music环境初始化完成');
    ''';

    _runtime!.evaluate(lxEnvironment);

    // 注册Flutter网络请求代理
    _runtime!.onMessage('_flutterRequestProxy', (args) async {
      await _handleNetworkRequest(args);
    });

    // 注册Flutter事件发送器
    _runtime!.onMessage('_flutterEventSender', (args) {
      _handleEventSend(args);
    });
  }

  /// 处理JS发起的网络请求
  Future<void> _handleNetworkRequest(dynamic args) async {
    Map<String, dynamic>? requestData;
    try {
      requestData = jsonDecode(args);
      final requestId = requestData?['id'];
      final url = requestData?['url'];
      final options = requestData?['options'] ?? {};

      print('[JSProxy] 🌐 处理网络请求: $url');

      // 发起实际的网络请求
      final response = await _dio.request(
        url,
        options: Options(
          method: options['method'] ?? 'GET',
          headers: Map<String, String>.from(options['headers'] ?? {}),
          followRedirects: options['follow_max'] != null,
          maxRedirects: options['follow_max'] ?? 5,
        ),
        data: options['data'],
      );

      // 构造响应数据
      final responseData = {
        'statusCode': response.statusCode,
        'body': response.data,
        'headers': response.headers.map,
      };

      // 调用JS回调
      final callbackScript = '''
        if (globalThis._pendingRequests['$requestId']) {
          const callback = globalThis._pendingRequests['$requestId'];
          delete globalThis._pendingRequests['$requestId'];
          
          const response = ${jsonEncode(responseData)};
          callback(null, response);
        }
      ''';

      _runtime!.evaluate(callbackScript);
      print('[JSProxy] ✅ 网络请求完成: ${response.statusCode}');
    } catch (e) {
      print('[JSProxy] ❌ 网络请求失败: $e');

      // 通知JS请求失败
      final requestId = requestData?['id'] ?? 'unknown';
      final errorScript = '''
        if (globalThis._pendingRequests['$requestId']) {
          const callback = globalThis._pendingRequests['$requestId'];
          delete globalThis._pendingRequests['$requestId'];
          callback(new Error('${e.toString().replaceAll("'", "\\'")}'), null);
        }
      ''';

      _runtime!.evaluate(errorScript);
    }
  }

  /// 处理JS发送的事件
  void _handleEventSend(dynamic args) {
    try {
      final eventData = jsonDecode(args);
      final eventName = eventData['event'];
      final data = eventData['data'];

      print('[JSProxy] 📡 收到JS事件: $eventName');

      // 处理特定事件
      switch (eventName) {
        case 'inited':
          print('[JSProxy] 🎵 JS脚本初始化完成');
          break;
        case 'updateAlert':
          print('[JSProxy] 🔄 脚本更新提醒: ${data?['log']}');
          break;
        default:
          print('[JSProxy] 📨 未处理的事件: $eventName');
      }
    } catch (e) {
      print('[JSProxy] ❌ 事件处理失败: $e');
    }
  }

  /// 加载JS脚本
  Future<bool> loadScript(String scriptContent) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('[JSProxy] 📜 开始加载JS脚本...');

      // 执行JS脚本
      _runtime!.evaluate(scriptContent);
      _currentScript = scriptContent;

      // 等待脚本初始化
      await Future.delayed(const Duration(milliseconds: 500));

      // 检查脚本是否正确加载
      final checkResult = _runtime!.evaluate('''
        (function() {
          try {
            return {
              hasHandlers: Object.keys(globalThis._lxHandlers || {}).length > 0,
              hasMusicSources: Object.keys(globalThis._musicSources || {}).length > 0,
              handlers: Object.keys(globalThis._lxHandlers || {})
            };
          } catch (e) {
            return { error: e.toString() };
          }
        })()
      ''');

      print('[JSProxy] 🔍 脚本加载检查结果: ${checkResult.stringResult}');

      if (checkResult.stringResult.contains('error')) {
        print('[JSProxy] ❌ 脚本加载失败');
        return false;
      }

      print('[JSProxy] ✅ JS脚本加载成功');
      return true;
    } catch (e) {
      print('[JSProxy] ❌ JS脚本加载异常: $e');
      return false;
    }
  }

  /// 获取音乐播放链接
  Future<String?> getMusicUrl({
    required String source, // tx, wy, kg等
    required String songId, // 歌曲ID
    required String quality, // 320k, flac等
    Map<String, dynamic>? musicInfo, // 额外音乐信息
  }) async {
    if (!_isInitialized || _currentScript == null) {
      print('[JSProxy] ❌ JS环境未初始化或脚本未加载');
      return null;
    }

    try {
      print('[JSProxy] 🎵 开始获取音乐链接: $source/$songId/$quality');

      // 构造请求参数
      final requestParams = {
        'action': 'musicUrl',
        'source': source,
        'info': {
          'musicInfo': {'songmid': songId, 'hash': songId, ...?musicInfo},
          'type': quality,
        },
      };

      // 调用JS处理函数
      final executeScript = '''
        (async function() {
          try {
            const params = ${jsonEncode(requestParams)};
            console.log('[JSProxy] 调用JS处理函数:', params);
            
            if (globalThis._lxHandlers && globalThis._lxHandlers.request) {
              const result = await globalThis._lxHandlers.request(params);
              console.log('[JSProxy] JS返回结果:', result);
              return { success: true, result: result };
            } else {
              return { success: false, error: '未找到请求处理函数' };
            }
          } catch (e) {
            console.error('[JSProxy] JS执行错误:', e);
            return { success: false, error: e.toString() };
          }
        })()
      ''';

      final result = _runtime!.evaluate(executeScript);
      print('[JSProxy] 🔍 JS执行结果: ${result.stringResult}');

      // 解析结果
      final resultData = jsonDecode(result.stringResult);

      if (resultData['success'] == true) {
        final musicUrl = resultData['result'];
        print('[JSProxy] ✅ 成功获取音乐链接: $musicUrl');
        return musicUrl;
      } else {
        print('[JSProxy] ❌ 获取音乐链接失败: ${resultData['error']}');
        return null;
      }
    } catch (e) {
      print('[JSProxy] ❌ 获取音乐链接异常: $e');
      return null;
    }
  }

  /// 获取支持的音源列表
  Map<String, dynamic> getSupportedSources() {
    if (!_isInitialized || _currentScript == null) {
      return {};
    }

    try {
      final result = _runtime!.evaluate('''
        (function() {
          try {
            return globalThis._musicSources || {};
          } catch (e) {
            return {};
          }
        })()
      ''');

      return Map<String, dynamic>.from(jsonDecode(result.stringResult));
    } catch (e) {
      print('[JSProxy] ❌ 获取音源列表失败: $e');
      return {};
    }
  }

  /// 释放资源
  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    _currentScript = null;
    _isInitialized = false;
    print('[JSProxy] 🧹 资源已释放');
  }
}
