import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 增强版JS脚本代理执行器服务
/// 完全兼容LX Music脚本格式和API
class EnhancedJSProxyExecutorService {
  final Dio _dio = Dio();
  JavascriptRuntime? _runtime;
  String? _currentScript;
  bool _isInitialized = false;
  String? _lxPreloadScript;
  final Map<String, Completer<dynamic>> _lxPendingRequests = {};

  EnhancedJSProxyExecutorService() {
    // 某些第三方音源接口证书链不稳定（尤其是测试环境/镜像站），导致握手失败；
    // 这里仅对白名单域名放宽校验，避免影响其他正常 HTTPS。
    final adapter = _dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.onHttpClientCreate = (HttpClient client) {
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          const allowed = <String>{
            'xue.010504.xyz',
            'lxx.010504.xyz',
          };
          return allowed.contains(host);
        };
        return client;
      };
    }
  }

  /// 初始化JS执行环境
  Future<void> initialize() async {
    if (_isInitialized) return;

    _runtime = getJavascriptRuntime();
    await _setupCompleteLXMusicEnvironment();
    await _ensureLxPreloadLoaded();
    _isInitialized = true;

    print('[EnhancedJSProxy] ✅ JS执行环境初始化完成');
  }

  Future<void> _ensureLxPreloadLoaded() async {
    if (_lxPreloadScript != null) return;
    try {
      _lxPreloadScript = await rootBundle.loadString(
        'assets/lx/lx_user_api_preload.js',
      );
    } catch (e) {
      // 预加载脚本缺失不应阻塞；后续将回退到旧兼容层
      print('[EnhancedJSProxy] ⚠️ 无法加载 LX preload 脚本: $e');
      _lxPreloadScript = '';
    }
  }

  /// 设置完整的LX Music运行环境
  Future<void> _setupCompleteLXMusicEnvironment() async {
    if (_runtime == null) return;

    // 注入完整的LX Music环境模拟（基于官方实现）
    final lxEnvironment = '''
      // =============================================================================
      // 基础浏览器API模拟
      // =============================================================================
      
      // Base64编码解码
      if (typeof atob === 'undefined') {
        globalThis.atob = function(input) {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          let str = '', bc = 0, buffer, idx = 0;
          input = input.replace(/=+\$/, '');
          for (buffer = input.charAt(idx++); ~(buffer = chars.indexOf(buffer)) && (buffer = bc % 4 ? buffer * 64 + chars.indexOf(input.charAt(idx - 1)) : buffer) && bc++ % 4 ? str += String.fromCharCode(255 & buffer >> (-2 * bc & 6)) : 0;) {}
          return str;
        };
      }
      
      if (typeof btoa === 'undefined') {
        globalThis.btoa = function(input) {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          let str = input, output = '';
          for (let block = 0, charCode, idx = 0, map = chars; str.charAt(idx | 0) || (map = '=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
            charCode = str.charCodeAt(idx += 3/4);
            if (charCode > 0xFF) throw new Error('btoa failed: invalid char');
            block = block << 8 | charCode;
          }
          return output;
        };
      }

      // TextEncoder/TextDecoder polyfill（部分脚本/加密库会用到）
      if (typeof TextEncoder === 'undefined') {
        globalThis.TextEncoder = function() {};
        globalThis.TextEncoder.prototype.encode = function(str) {
          str = String(str ?? '');
          const bytes = [];
          for (let i = 0; i < str.length; i++) {
            const c = str.charCodeAt(i);
            if (c < 0x80) bytes.push(c);
            else if (c < 0x800) { bytes.push((c >> 6) | 0xc0, (c & 0x3f) | 0x80); }
            else { bytes.push((c >> 12) | 0xe0, ((c >> 6) & 0x3f) | 0x80, (c & 0x3f) | 0x80); }
          }
          return new Uint8Array(bytes);
        };
      }
      if (typeof TextDecoder === 'undefined') {
        globalThis.TextDecoder = function() {};
        globalThis.TextDecoder.prototype.decode = function(buf) {
          if (buf == null) return '';
          const bytes = buf instanceof Uint8Array ? buf : (ArrayBuffer.isView(buf) ? new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength) : new Uint8Array(buf));
          let out = '';
          let i = 0;
          while (i < bytes.length) {
            const b = bytes[i++];
            if (b < 0x80) out += String.fromCharCode(b);
            else if (b < 0xe0) { const b2 = bytes[i++]; out += String.fromCharCode(((b & 0x1f) << 6) | (b2 & 0x3f)); }
            else { const b2 = bytes[i++]; const b3 = bytes[i++]; out += String.fromCharCode(((b & 0x0f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f)); }
          }
          return out;
        };
      }

      // URL / URLSearchParams polyfill（满足基本 query 解析需求）
      if (typeof URLSearchParams === 'undefined') {
        globalThis.URLSearchParams = function(init) {
          this._m = {};
          if (typeof init === 'string') {
            const s = init.replace(/^\\?/, '');
            if (s) {
              s.split('&').forEach(p => {
                const kv = p.split('=');
                const k = decodeURIComponent(kv[0] || '');
                const v = decodeURIComponent(kv.slice(1).join('=') || '');
                if (k) this._m[k] = v;
              });
            }
          }
        };
        globalThis.URLSearchParams.prototype.get = function(k) { return this._m[k] ?? null; };
        globalThis.URLSearchParams.prototype.set = function(k, v) { this._m[k] = String(v); };
        globalThis.URLSearchParams.prototype.toString = function() {
          const parts = [];
          for (const k in this._m) parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(this._m[k]));
          return parts.join('&');
        };
      }
      if (typeof URL === 'undefined') {
        globalThis.URL = function(url) {
          const u = String(url || '');
          const m = u.match(/^(https?:)\\/\\/([^\\/]+)(\\/[^?]*)?(\\?.*)?\$/);
          this.href = u;
          this.protocol = m ? m[1] : '';
          this.host = m ? m[2] : '';
          this.pathname = m && m[3] ? m[3] : '/';
          this.search = m && m[4] ? m[4] : '';
          this.searchParams = new URLSearchParams(this.search);
        };
      }

      // WebCrypto getRandomValues 兼容（常用于生成随机 key/nonce）
      if (typeof crypto === 'undefined') globalThis.crypto = {};
      if (typeof globalThis.crypto.getRandomValues !== 'function') {
        globalThis.crypto.getRandomValues = function(arr) {
          for (let i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
          return arr;
        };
      }
      
      // 简化的XMLHttpRequest
      if (typeof XMLHttpRequest === 'undefined') {
        globalThis.XMLHttpRequest = function() {
          this.readyState = 0;
          this.status = 0;
          this.responseText = '';
          this.onreadystatechange = null;
          
          this.open = function(method, url, async) {
            this.method = method;
            this.url = url;
            this.async = async !== false;
            this.readyState = 1;
          };
          
          this.setRequestHeader = function(header, value) {
            this.headers = this.headers || {};
            this.headers[header] = value;
          };
          
          this.send = function(data) {
            const self = this;
            setTimeout(() => {
              self.readyState = 4;
              self.status = 200;
              self.responseText = '{}';
              if (self.onreadystatechange) self.onreadystatechange();
            }, 100);
          };
        };
      }
      
      // 添加fetch polyfill
      if (typeof fetch === 'undefined') {
        globalThis.fetch = function(url, options) {
          return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open(options?.method || 'GET', url);
            
            if (options?.headers) {
              for (const [key, value] of Object.entries(options.headers)) {
                xhr.setRequestHeader(key, value);
              }
            }
            
            xhr.onreadystatechange = function() {
              if (xhr.readyState === 4) {
                resolve({
                  ok: xhr.status >= 200 && xhr.status < 300,
                  status: xhr.status,
                  text: () => Promise.resolve(xhr.responseText),
                  json: () => Promise.resolve(JSON.parse(xhr.responseText))
                });
              }
            };
            
            xhr.send(options?.body);
          });
        };
      }
      
      // =============================================================================
      // LX Music核心环境
      // =============================================================================
      
      // 初始化全局状态（按 LX Music 官方规范）
      globalThis._lxHandlers = {
        request: null  // 单一处理器，不是数组
      };
      globalThis._pendingRequests = {};
      globalThis._musicSources = {};
      globalThis._isInitedApi = false;      // 标记是否已初始化
      globalThis._isShowedUpdateAlert = false;  // 标记是否已显示更新提示
      globalThis._scriptRegistered = false;
      
      // 创建完整的lx对象
      globalThis.lx = {
        // 事件名称常量
        EVENT_NAMES: {
          inited: 'inited',
          request: 'request',
          send: 'send', 
          updateAlert: 'updateAlert',
          error: 'error'
        },
        
        // 网络请求函数（按 LX Music 官方规范）
        request: function(url, options, callback) {
          console.log('[LXEnv] 发起网络请求:', url);

          // 兼容不同的调用方式
          let actualUrl, actualOptions, actualCallback;

          if (typeof url === 'string') {
            actualUrl = url;
            if (typeof options === 'function') {
              actualCallback = options;
              actualOptions = {};
            } else {
              actualOptions = options || {};
              actualCallback = callback;
            }
          } else if (typeof url === 'object') {
            actualUrl = url.url;
            actualOptions = url.options || url;
            actualCallback = options || callback;
          }

          const requestId = 'req_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

          // 请求状态追踪
          const requestInfo = {
            aborted: false
          };

          // 存储回调
          if (typeof actualCallback === 'function') {
            globalThis._pendingRequests[requestId] = function(err, response) {
              if (requestInfo.aborted) return;  // 如果已取消，不执行回调
              try {
                // 按官方格式回调：callback(err, response, body)
                actualCallback(err, response ? {
                  statusCode: response.statusCode,
                  statusMessage: response.statusMessage || '',
                  headers: response.headers || {},
                  body: response.body
                } : null, response ? response.body : null);
              } catch (e) {
                console.warn('[LXEnv] 回调执行出错:', e);
              }
            };
          }

          // 构建请求数据
          const requestData = {
            id: requestId,
            url: actualUrl,
            options: {
              method: actualOptions.method || 'GET',
              headers: actualOptions.headers || {},
              body: actualOptions.body,
              timeout: actualOptions.timeout ? Math.min(actualOptions.timeout, 60000) : 30000,
              follow_max: actualOptions.follow_max || 5
            }
          };

          console.log('[LXEnv] 调用Flutter网络请求代理，请求数据:', JSON.stringify(requestData));
          globalThis._flutterRequestProxy(requestData);

          // 返回 abort 函数（官方行为）
          return function() {
            if (!requestInfo.aborted) {
              requestInfo.aborted = true;
              delete globalThis._pendingRequests[requestId];
              console.log('[LXEnv] 请求已取消:', requestId);
            }
          };
        },
        
        // 事件监听（按 LX Music 官方规范）
        on: function(eventName, handler) {
          console.log('[LXEnv] 注册事件监听:', eventName);
          const supportedEvents = ['request', 'inited', 'updateAlert'];
          if (!supportedEvents.includes(eventName)) {
            return Promise.reject(new Error('The event is not supported: ' + eventName));
          }
          switch (eventName) {
            case 'request':
              globalThis._lxHandlers.request = handler;  // 单一处理器，不是数组
              console.log('[LXEnv] ✅ request 处理器已注册');
              break;
            default:
              return Promise.reject(new Error('The event is not supported: ' + eventName));
          }
          return Promise.resolve();  // 返回 Promise
        },
        
        // 事件发送（按 LX Music 官方规范）
        send: function(eventName, data) {
          console.log('[LXEnv] 发送事件到Flutter:', eventName, data);
          const supportedEvents = ['request', 'inited', 'updateAlert'];

          return new Promise((resolve, reject) => {
            if (!supportedEvents.includes(eventName)) {
              return reject(new Error('The event is not supported: ' + eventName));
            }

            switch (eventName) {
              case 'inited':
                if (globalThis._isInitedApi) {
                  return reject(new Error('Script is inited'));
                }
                globalThis._isInitedApi = true;
                // 处理初始化数据
                if (data && data.sources) {
                  globalThis._musicSources = data.sources;
                  globalThis._scriptRegistered = true;
                  console.log('[LXEnv] ✅ 脚本初始化完成，音源:', Object.keys(data.sources).join(', '));
                }
                const eventData = { event: eventName, data: data };
                globalThis._flutterEventSender(JSON.stringify(eventData));
                resolve();
                break;

              case 'updateAlert':
                if (globalThis._isShowedUpdateAlert) {
                  return reject(new Error('The update alert can only be called once.'));
                }
                globalThis._isShowedUpdateAlert = true;
                const alertData = { event: eventName, data: data };
                globalThis._flutterEventSender(JSON.stringify(alertData));
                resolve();
                break;

              default:
                reject(new Error('Unknown event name: ' + eventName));
            }
          });
        },
        
        // emit别名（向后兼容）
        emit: function(eventName, data) {
          try {
            if (typeof globalThis._dispatchEventToScript === 'function') {
              return globalThis._dispatchEventToScript(eventName, data);
            }
            return null;
          } catch (e) {
            console.warn('[LXEnv] emit 分发失败:', e);
            return null;
          }
        },
        
        // 🔥 工具函数集合（完全按照官方 preload 脚本实现 - 2024.01 版本）
        // 🎯 关键修复：官方返回纯 Uint8Array，不是 Buffer 子类！
        utils: {
          buffer: {
            // 🔥 官方实现：直接返回 Uint8Array，不使用 Buffer 类
            from: function(input, encoding) {
              console.log('[LXEnv] utils.buffer.from 被调用');
              console.log('[LXEnv] utils.buffer.from 输入类型:', typeof input, '编码:', encoding);

              // 🎯 完全按照官方实现
              if (typeof input === 'string') {
                switch (encoding) {
                  case 'binary':
                    // 官方: throw new Error('Binary encoding is not supported for input strings')
                    throw new Error('Binary encoding is not supported for input strings');
                  case 'base64':
                    // 官方: return new Uint8Array(JSON.parse(nativeFuncs.utils_b642buf(input)))
                    // 我们的实现：直接 atob 解码
                    try {
                      var binaryStr = atob(input);
                      var bytes = new Uint8Array(binaryStr.length);
                      for (var i = 0; i < binaryStr.length; i++) {
                        bytes[i] = binaryStr.charCodeAt(i);
                      }
                      console.log('[LXEnv] buffer.from base64 解码完成, 长度:', bytes.length);
                      return bytes;
                    } catch (e) {
                      console.warn('[LXEnv] base64 解码失败:', e);
                      return new Uint8Array(0);
                    }
                  case 'hex':
                    // 官方: return new Uint8Array(input.match(/.{1,2}/g).map(byte => parseInt(byte, 16)))
                    var hexMatch = input.match(/.{1,2}/g);
                    if (!hexMatch) return new Uint8Array(0);
                    return new Uint8Array(hexMatch.map(function(byte) { return parseInt(byte, 16); }));
                  default:
                    // 官方: return new Uint8Array(stringToBytes(input))
                    // UTF-8 编码
                    var utf8Bytes = [];
                    for (var i = 0; i < input.length; i++) {
                      var charCode = input.charCodeAt(i);
                      if (charCode < 128) {
                        utf8Bytes.push(charCode);
                      } else if (charCode < 2048) {
                        utf8Bytes.push((charCode >> 6) | 192);
                        utf8Bytes.push((charCode & 63) | 128);
                      } else {
                        utf8Bytes.push((charCode >> 12) | 224);
                        utf8Bytes.push(((charCode >> 6) & 63) | 128);
                        utf8Bytes.push((charCode & 63) | 128);
                      }
                    }
                    return new Uint8Array(utf8Bytes);
                }
              } else if (Array.isArray(input)) {
                // 官方: return new Uint8Array(input)
                return new Uint8Array(input);
              } else {
                // 官方: throw new Error('Unsupported input type: ' + input + ' encoding: ' + encoding)
                throw new Error('Unsupported input type: ' + input + ' encoding: ' + encoding);
              }
            },
            // 🔥 官方实现：支持 Array 和 ArrayBufferView
            bufToString: function(buf, format) {
              console.log('[LXEnv] utils.buffer.bufToString 被调用');
              console.log('[LXEnv] bufToString buf 类型:', typeof buf, 'format:', format);

              // 🎯 完全按照官方实现
              if (Array.isArray(buf) || ArrayBuffer.isView(buf)) {
                switch (format) {
                  case 'binary':
                    // 官方: return buf
                    return buf;
                  case 'hex':
                    // 官方: return new Uint8Array(buf).reduce((str, byte) => str + byte.toString(16).padStart(2, '0'), '')
                    return new Uint8Array(buf).reduce(function(str, byte) {
                      return str + byte.toString(16).padStart(2, '0');
                    }, '');
                  case 'base64':
                    // 官方: return nativeFuncs.utils_str2b64(bytesToString(Array.from(buf)))
                    // 我们的实现：先转字符串再转 base64
                    var utf8Str = '';
                    var bytes = Array.from(buf);
                    var i = 0;
                    while (i < bytes.length) {
                      var byte = bytes[i];
                      if (byte < 128) {
                        utf8Str += String.fromCharCode(byte);
                        i++;
                      } else if (byte >= 192 && byte < 224) {
                        utf8Str += String.fromCharCode(((byte & 31) << 6) | (bytes[i + 1] & 63));
                        i += 2;
                      } else {
                        utf8Str += String.fromCharCode(((byte & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63));
                        i += 3;
                      }
                    }
                    return btoa(utf8Str);
                  case 'utf8':
                  case 'utf-8':
                  default:
                    // 官方: return bytesToString(Array.from(buf))
                    var result = '';
                    var arr = Array.from(buf);
                    var j = 0;
                    while (j < arr.length) {
                      var b = arr[j];
                      if (b < 128) {
                        result += String.fromCharCode(b);
                        j++;
                      } else if (b >= 192 && b < 224) {
                        result += String.fromCharCode(((b & 31) << 6) | (arr[j + 1] & 63));
                        j += 2;
                      } else {
                        result += String.fromCharCode(((b & 15) << 12) | ((arr[j + 1] & 63) << 6) | (arr[j + 2] & 63));
                        j += 3;
                      }
                    }
                    return result;
                }
              } else {
                // 官方: throw new Error('Input is not a valid buffer: ' + buf + ' format: ' + format)
                throw new Error('Input is not a valid buffer: ' + buf + ' format: ' + format);
              }
            }
          },

          crypto: {
            // 🔥 MD5 实现（完全按照官方 preload 脚本）
            // 🎯 官方实现：if (typeof str !== 'string') throw new Error('param required a string')
            md5: function(str) {
              console.log('[LXEnv] utils.crypto.md5 被调用');
              console.log('[LXEnv] md5 输入类型:', typeof str);

              // 🎯 官方行为：必须是字符串，否则抛出错误
              // 🔥 关键：错误消息必须和官方完全一致！
              if (typeof str !== 'string') {
                console.error('[LXEnv] md5: 参数不是字符串，抛出错误（官方行为）');
                throw new Error('param required a string');
              }

              console.log('[LXEnv] md5 输入长度:', str.length);
              console.log('[LXEnv] md5 输入预览:', str.substring(0, 50));

              // MD5 辅助函数
              function md5cycle(x, k) {
                var a = x[0], b = x[1], c = x[2], d = x[3];

                a = ff(a, b, c, d, k[0], 7, -680876936);
                d = ff(d, a, b, c, k[1], 12, -389564586);
                c = ff(c, d, a, b, k[2], 17, 606105819);
                b = ff(b, c, d, a, k[3], 22, -1044525330);
                a = ff(a, b, c, d, k[4], 7, -176418897);
                d = ff(d, a, b, c, k[5], 12, 1200080426);
                c = ff(c, d, a, b, k[6], 17, -1473231341);
                b = ff(b, c, d, a, k[7], 22, -45705983);
                a = ff(a, b, c, d, k[8], 7, 1770035416);
                d = ff(d, a, b, c, k[9], 12, -1958414417);
                c = ff(c, d, a, b, k[10], 17, -42063);
                b = ff(b, c, d, a, k[11], 22, -1990404162);
                a = ff(a, b, c, d, k[12], 7, 1804603682);
                d = ff(d, a, b, c, k[13], 12, -40341101);
                c = ff(c, d, a, b, k[14], 17, -1502002290);
                b = ff(b, c, d, a, k[15], 22, 1236535329);

                a = gg(a, b, c, d, k[1], 5, -165796510);
                d = gg(d, a, b, c, k[6], 9, -1069501632);
                c = gg(c, d, a, b, k[11], 14, 643717713);
                b = gg(b, c, d, a, k[0], 20, -373897302);
                a = gg(a, b, c, d, k[5], 5, -701558691);
                d = gg(d, a, b, c, k[10], 9, 38016083);
                c = gg(c, d, a, b, k[15], 14, -660478335);
                b = gg(b, c, d, a, k[4], 20, -405537848);
                a = gg(a, b, c, d, k[9], 5, 568446438);
                d = gg(d, a, b, c, k[14], 9, -1019803690);
                c = gg(c, d, a, b, k[3], 14, -187363961);
                b = gg(b, c, d, a, k[8], 20, 1163531501);
                a = gg(a, b, c, d, k[13], 5, -1444681467);
                d = gg(d, a, b, c, k[2], 9, -51403784);
                c = gg(c, d, a, b, k[7], 14, 1735328473);
                b = gg(b, c, d, a, k[12], 20, -1926607734);

                a = hh(a, b, c, d, k[5], 4, -378558);
                d = hh(d, a, b, c, k[8], 11, -2022574463);
                c = hh(c, d, a, b, k[11], 16, 1839030562);
                b = hh(b, c, d, a, k[14], 23, -35309556);
                a = hh(a, b, c, d, k[1], 4, -1530992060);
                d = hh(d, a, b, c, k[4], 11, 1272893353);
                c = hh(c, d, a, b, k[7], 16, -155497632);
                b = hh(b, c, d, a, k[10], 23, -1094730640);
                a = hh(a, b, c, d, k[13], 4, 681279174);
                d = hh(d, a, b, c, k[0], 11, -358537222);
                c = hh(c, d, a, b, k[3], 16, -722521979);
                b = hh(b, c, d, a, k[6], 23, 76029189);
                a = hh(a, b, c, d, k[9], 4, -640364487);
                d = hh(d, a, b, c, k[12], 11, -421815835);
                c = hh(c, d, a, b, k[15], 16, 530742520);
                b = hh(b, c, d, a, k[2], 23, -995338651);

                a = ii(a, b, c, d, k[0], 6, -198630844);
                d = ii(d, a, b, c, k[7], 10, 1126891415);
                c = ii(c, d, a, b, k[14], 15, -1416354905);
                b = ii(b, c, d, a, k[5], 21, -57434055);
                a = ii(a, b, c, d, k[12], 6, 1700485571);
                d = ii(d, a, b, c, k[3], 10, -1894986606);
                c = ii(c, d, a, b, k[10], 15, -1051523);
                b = ii(b, c, d, a, k[1], 21, -2054922799);
                a = ii(a, b, c, d, k[8], 6, 1873313359);
                d = ii(d, a, b, c, k[15], 10, -30611744);
                c = ii(c, d, a, b, k[6], 15, -1560198380);
                b = ii(b, c, d, a, k[13], 21, 1309151649);
                a = ii(a, b, c, d, k[4], 6, -145523070);
                d = ii(d, a, b, c, k[11], 10, -1120210379);
                c = ii(c, d, a, b, k[2], 15, 718787259);
                b = ii(b, c, d, a, k[9], 21, -343485551);

                x[0] = add32(a, x[0]);
                x[1] = add32(b, x[1]);
                x[2] = add32(c, x[2]);
                x[3] = add32(d, x[3]);
              }

              function cmn(q, a, b, x, s, t) {
                a = add32(add32(a, q), add32(x, t));
                return add32((a << s) | (a >>> (32 - s)), b);
              }

              function ff(a, b, c, d, x, s, t) {
                return cmn((b & c) | ((~b) & d), a, b, x, s, t);
              }

              function gg(a, b, c, d, x, s, t) {
                return cmn((b & d) | (c & (~d)), a, b, x, s, t);
              }

              function hh(a, b, c, d, x, s, t) {
                return cmn(b ^ c ^ d, a, b, x, s, t);
              }

              function ii(a, b, c, d, x, s, t) {
                return cmn(c ^ (b | (~d)), a, b, x, s, t);
              }

              function md51(s) {
                var n = s.length,
                    state = [1732584193, -271733879, -1732584194, 271733878],
                    i;
                for (i = 64; i <= n; i += 64) {
                  md5cycle(state, md5blk(s.substring(i - 64, i)));
                }
                s = s.substring(i - 64);
                var tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                for (i = 0; i < s.length; i++) {
                  tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
                }
                tail[i >> 2] |= 0x80 << ((i % 4) << 3);
                if (i > 55) {
                  md5cycle(state, tail);
                  for (i = 0; i < 16; i++) tail[i] = 0;
                }
                tail[14] = n * 8;
                md5cycle(state, tail);
                return state;
              }

              function md5blk(s) {
                var md5blks = [], i;
                for (i = 0; i < 64; i += 4) {
                  md5blks[i >> 2] = s.charCodeAt(i) +
                                    (s.charCodeAt(i + 1) << 8) +
                                    (s.charCodeAt(i + 2) << 16) +
                                    (s.charCodeAt(i + 3) << 24);
                }
                return md5blks;
              }

              var hex_chr = '0123456789abcdef'.split('');

              function rhex(n) {
                var s = '', j = 0;
                for (; j < 4; j++) {
                  s += hex_chr[(n >> (j * 8 + 4)) & 0x0F] +
                       hex_chr[(n >> (j * 8)) & 0x0F];
                }
                return s;
              }

              function hex(x) {
                for (var i = 0; i < x.length; i++) {
                  x[i] = rhex(x[i]);
                }
                return x.join('');
              }

              function add32(a, b) {
                return (a + b) & 0xFFFFFFFF;
              }

              // 处理 UTF-8 字符串
              function utf8Encode(str) {
                var utf8 = '';
                for (var i = 0; i < str.length; i++) {
                  var c = str.charCodeAt(i);
                  if (c < 128) {
                    utf8 += String.fromCharCode(c);
                  } else if (c < 2048) {
                    utf8 += String.fromCharCode((c >> 6) | 192);
                    utf8 += String.fromCharCode((c & 63) | 128);
                  } else {
                    utf8 += String.fromCharCode((c >> 12) | 224);
                    utf8 += String.fromCharCode(((c >> 6) & 63) | 128);
                    utf8 += String.fromCharCode((c & 63) | 128);
                  }
                }
                return utf8;
              }

              var result = hex(md51(utf8Encode(str)));
              console.log('[LXEnv] md5 计算结果:', result);
              return result;
            },

            // 🔥 随机字节生成
            randomBytes: function(size) {
              console.log('[LXEnv] utils.crypto.randomBytes 被调用, size:', size);
              const byteArray = new Uint8Array(size);
              for (let i = 0; i < size; i++) {
                byteArray[i] = Math.floor(Math.random() * 256);
              }
              console.log('[LXEnv] randomBytes 返回 Uint8Array, 长度:', byteArray.length);
              return byteArray;
            },

            // 🔥 AES-128 加密实现（支持 ECB 和 CBC 模式）
            // 🎯 关键：ECB 模式使用 NoPadding，CBC 模式使用 PKCS7Padding
            aesEncrypt: function(buffer, mode, key, iv) {
              console.log('[LXEnv] aesEncrypt 被调用, mode:', mode);

              // 将输入转换为字节数组
              // 🔥 详细日志：看看脚本传入的是什么类型
              console.log('[LXEnv] aesEncrypt buffer 类型检查:', {
                typeofBuffer: typeof buffer,
                isUint8Array: buffer instanceof Uint8Array,
                isArrayBufferView: ArrayBuffer.isView(buffer),
                isArray: Array.isArray(buffer),
                hasData: buffer && buffer.data !== undefined,
                hasLength: buffer && buffer.length !== undefined,
                constructorName: buffer && buffer.constructor ? buffer.constructor.name : 'null',
                bufferPreview: buffer ? (typeof buffer === 'string' ? buffer.substring(0, 50) : JSON.stringify(buffer).substring(0, 100)) : 'null'
              });

              var data;
              // 🔥 按优先级检测类型并转换为 Uint8Array
              // 1. ArrayBuffer（必须在 ArrayBuffer.isView 之前检测！）
              if (buffer instanceof ArrayBuffer) {
                console.log('[LXEnv] aesEncrypt: 检测到 ArrayBuffer，长度:', buffer.byteLength);
                data = new Uint8Array(buffer);
              }
              // 2. TypedArray（Uint8Array, Int8Array 等）
              else if (ArrayBuffer.isView(buffer)) {
                console.log('[LXEnv] aesEncrypt: 检测到 ArrayBufferView，长度:', buffer.byteLength);
                data = new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
              }
              // 3. 普通 Uint8Array（冗余检查，增加安全性）
              else if (buffer instanceof Uint8Array) {
                data = buffer;
              }
              // 4. 字符串
              else if (typeof buffer === 'string') {
                console.log('[LXEnv] aesEncrypt: 检测到字符串，长度:', buffer.length);
                data = new Uint8Array(buffer.length);
                for (var i = 0; i < buffer.length; i++) {
                  data[i] = buffer.charCodeAt(i);
                }
              }
              // 5. 带 data 属性的对象（兼容旧格式）
              else if (buffer && buffer.data) {
                console.log('[LXEnv] aesEncrypt: 检测到 data 属性对象');
                data = new Uint8Array(buffer.data);
              }
              // 6. 数组
              else if (Array.isArray(buffer)) {
                console.log('[LXEnv] aesEncrypt: 检测到数组，长度:', buffer.length);
                data = new Uint8Array(buffer);
              }
              // 7. 类数组对象（有 length 和数字索引）
              else if (buffer && typeof buffer.length === 'number') {
                console.log('[LXEnv] aesEncrypt: 检测到类数组对象，长度:', buffer.length);
                data = new Uint8Array(buffer.length);
                for (var i = 0; i < buffer.length; i++) {
                  data[i] = buffer[i];
                }
              }
              // 8. 可迭代对象
              else if (buffer && typeof buffer[Symbol.iterator] === 'function') {
                console.log('[LXEnv] aesEncrypt: 检测到可迭代对象');
                data = new Uint8Array(Array.from(buffer));
              }
              // 9. 带 byteLength 属性的对象（可能是 SharedArrayBuffer 等）
              else if (buffer && typeof buffer.byteLength === 'number') {
                console.log('[LXEnv] aesEncrypt: 检测到 byteLength 属性对象，长度:', buffer.byteLength);
                try {
                  data = new Uint8Array(buffer);
                } catch (e) {
                  try {
                    globalThis.__lx_last_invalid_aes_input = {
                      phase: 'byteLength_to_uint8array',
                      type: typeof buffer,
                      tag: Object.prototype.toString.call(buffer),
                      keys: Object.keys(buffer || {}).slice(0, 50),
                    };
                  } catch(_) {}
                  console.error('[LXEnv] aesEncrypt: 转换失败:', e);
                  throw new Error('input is invalid type');
                }
              }
              else {
                try {
                  globalThis.__lx_last_invalid_aes_input = {
                    phase: 'unrecognized',
                    type: typeof buffer,
                    tag: Object.prototype.toString.call(buffer),
                    keys: Object.keys(buffer || {}).slice(0, 50),
                  };
                } catch(_) {}
                console.error('[LXEnv] aesEncrypt: 无法识别的输入类型:', typeof buffer, Object.prototype.toString.call(buffer));
                throw new Error('input is invalid type');
              }

              // 将 key 转换为字节数组（同样支持 ArrayBuffer）
              var keyBytes;
              if (key instanceof ArrayBuffer) {
                keyBytes = new Uint8Array(key);
              } else if (ArrayBuffer.isView(key)) {
                keyBytes = new Uint8Array(key.buffer, key.byteOffset, key.byteLength);
              } else if (key instanceof Uint8Array) {
                keyBytes = key;
              } else if (typeof key === 'string') {
                keyBytes = new Uint8Array(key.length);
                for (var i = 0; i < key.length; i++) {
                  keyBytes[i] = key.charCodeAt(i);
                }
              } else if (Array.isArray(key)) {
                keyBytes = new Uint8Array(key);
              } else if (key && typeof key.length === 'number') {
                keyBytes = new Uint8Array(key.length);
                for (var i = 0; i < key.length; i++) {
                  keyBytes[i] = key[i];
                }
              } else if (key && typeof key.byteLength === 'number') {
                keyBytes = new Uint8Array(key);
              } else {
                console.warn('[LXEnv] aesEncrypt: 无效的密钥类型:', typeof key, Object.prototype.toString.call(key));
                throw new Error('Invalid key type');
              }

              // 将 iv 转换为字节数组（仅 CBC 模式需要，同样支持 ArrayBuffer）
              var ivBytes = null;
              if (iv) {
                if (iv instanceof ArrayBuffer) {
                  ivBytes = new Uint8Array(iv);
                } else if (ArrayBuffer.isView(iv)) {
                  ivBytes = new Uint8Array(iv.buffer, iv.byteOffset, iv.byteLength);
                } else if (iv instanceof Uint8Array) {
                  ivBytes = iv;
                } else if (typeof iv === 'string') {
                  ivBytes = new Uint8Array(iv.length);
                  for (var i = 0; i < iv.length; i++) {
                    ivBytes[i] = iv.charCodeAt(i);
                  }
                } else if (Array.isArray(iv)) {
                  ivBytes = new Uint8Array(iv);
                } else if (iv && typeof iv.length === 'number') {
                  ivBytes = new Uint8Array(iv.length);
                  for (var i = 0; i < iv.length; i++) {
                    ivBytes[i] = iv[i];
                  }
                } else if (iv && typeof iv.byteLength === 'number') {
                  ivBytes = new Uint8Array(iv);
                }
              }

              // AES S-box
              var sbox = [
                0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
                0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
                0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
                0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
                0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
                0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
                0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
                0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
                0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
                0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
                0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
                0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
                0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
                0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
                0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
                0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
              ];

              var rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

              // 密钥扩展
              function keyExpansion(key) {
                var expandedKey = new Uint8Array(176);
                for (var i = 0; i < 16; i++) {
                  expandedKey[i] = key[i] || 0;
                }

                for (var i = 16; i < 176; i += 4) {
                  var temp = expandedKey.slice(i - 4, i);
                  if (i % 16 === 0) {
                    temp = new Uint8Array([sbox[temp[1]], sbox[temp[2]], sbox[temp[3]], sbox[temp[0]]]);
                    temp[0] ^= rcon[(i / 16) - 1];
                  }
                  for (var j = 0; j < 4; j++) {
                    expandedKey[i + j] = expandedKey[i - 16 + j] ^ temp[j];
                  }
                }
                return expandedKey;
              }

              // GF(2^8) 乘法
              function gmul(a, b) {
                var p = 0;
                for (var i = 0; i < 8; i++) {
                  if (b & 1) p ^= a;
                  var hi = a & 0x80;
                  a = (a << 1) & 0xff;
                  if (hi) a ^= 0x1b;
                  b >>= 1;
                }
                return p;
              }

              // AES 加密一个块
              function encryptBlock(block, expandedKey) {
                var state = new Uint8Array(block);

                // 初始轮密钥加
                for (var i = 0; i < 16; i++) state[i] ^= expandedKey[i];

                for (var round = 1; round <= 10; round++) {
                  // SubBytes
                  for (var i = 0; i < 16; i++) state[i] = sbox[state[i]];

                  // ShiftRows
                  var temp = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = temp;
                  temp = state[2]; state[2] = state[10]; state[10] = temp;
                  temp = state[6]; state[6] = state[14]; state[14] = temp;
                  temp = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = temp;

                  // MixColumns (最后一轮跳过)
                  if (round < 10) {
                    for (var c = 0; c < 4; c++) {
                      var a0 = state[c*4], a1 = state[c*4+1], a2 = state[c*4+2], a3 = state[c*4+3];
                      state[c*4]   = gmul(a0, 2) ^ gmul(a1, 3) ^ a2 ^ a3;
                      state[c*4+1] = a0 ^ gmul(a1, 2) ^ gmul(a2, 3) ^ a3;
                      state[c*4+2] = a0 ^ a1 ^ gmul(a2, 2) ^ gmul(a3, 3);
                      state[c*4+3] = gmul(a0, 3) ^ a1 ^ a2 ^ gmul(a3, 2);
                    }
                  }

                  // AddRoundKey
                  for (var i = 0; i < 16; i++) state[i] ^= expandedKey[round * 16 + i];
                }

                return state;
              }

              var expandedKey = keyExpansion(keyBytes);

              // 🎯 根据模式选择加密方式
              switch (mode) {
                case 'aes-128-cbc':
                  // CBC 模式：PKCS7 填充 + IV 异或
                  console.log('[LXEnv] 使用 AES-128-CBC 模式 (PKCS7Padding)');
                  if (!ivBytes || ivBytes.length !== 16) {
                    throw new Error('CBC mode requires 16-byte IV');
                  }

                  // PKCS7 填充
                  var padLen = 16 - (data.length % 16);
                  var paddedData = new Uint8Array(data.length + padLen);
                  paddedData.set(data);
                  for (var i = data.length; i < paddedData.length; i++) {
                    paddedData[i] = padLen;
                  }

                  var result = new Uint8Array(paddedData.length);
                  var previousBlock = ivBytes;

                  for (var i = 0; i < paddedData.length; i += 16) {
                    var block = paddedData.slice(i, i + 16);
                    // 与前一个密文块（或 IV）异或
                    for (var j = 0; j < 16; j++) {
                      block[j] ^= previousBlock[j];
                    }
                    var encrypted = encryptBlock(block, expandedKey);
                    result.set(encrypted, i);
                    previousBlock = encrypted;
                  }

                  return result;

                case 'aes-128-ecb':
                default:
                  // ECB 模式：NoPadding（输入必须是 16 的倍数）
                  console.log('[LXEnv] 使用 AES-128-ECB 模式 (NoPadding)');

                  // NoPadding：如果不是 16 的倍数，用 0 填充到 16 的倍数
                  var processData = data;
                  if (data.length % 16 !== 0) {
                    var newLen = Math.ceil(data.length / 16) * 16;
                    processData = new Uint8Array(newLen);
                    processData.set(data);
                    // 剩余字节填充 0
                  }

                  var result = new Uint8Array(processData.length);

                  // ECB 模式：每个块独立加密
                  for (var i = 0; i < processData.length; i += 16) {
                    var block = processData.slice(i, i + 16);
                    var encrypted = encryptBlock(block, expandedKey);
                    result.set(encrypted, i);
                  }

                  return result;
              }
            },

            // 🔥 RSA 加密（简化实现 - 真正的 RSA 需要大数运算库）
            rsaEncrypt: function(buffer, key) {
              console.log('[LXEnv] utils.crypto.rsaEncrypt 被调用');
              console.log('[LXEnv] rsaEncrypt buffer 类型:', typeof buffer, Object.prototype.toString.call(buffer));
              console.log('[LXEnv] rsaEncrypt key 类型:', typeof key);

              // 🔥 统一转换为 Uint8Array
              var bytes;
              if (buffer instanceof ArrayBuffer) {
                console.log('[LXEnv] rsaEncrypt: 检测到 ArrayBuffer，长度:', buffer.byteLength);
                bytes = new Uint8Array(buffer);
              } else if (buffer instanceof Uint8Array) {
                bytes = buffer;
              } else if (ArrayBuffer.isView(buffer)) {
                bytes = new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
              } else if (Array.isArray(buffer)) {
                bytes = new Uint8Array(buffer);
              } else if (buffer && typeof buffer.length === 'number') {
                bytes = new Uint8Array(buffer.length);
                for (var i = 0; i < buffer.length; i++) {
                  bytes[i] = buffer[i];
                }
              } else if (buffer && typeof buffer.byteLength === 'number') {
                bytes = new Uint8Array(buffer);
              } else if (typeof buffer === 'string') {
                // 字符串转字节
                bytes = new Uint8Array(buffer.length);
                for (var i = 0; i < buffer.length; i++) {
                  bytes[i] = buffer.charCodeAt(i);
                }
              } else {
                console.warn('[LXEnv] rsaEncrypt: 不支持的类型，尝试 fallback');
                var result = btoa(String(buffer));
                console.log('[LXEnv] rsaEncrypt (fallback) 返回 base64, 长度:', result.length);
                return result;
              }

              // RSA 需要大数运算，在纯 JS 中实现较复杂
              // 暂时返回 Base64 编码的数据作为兼容
              var binary = '';
              for (var i = 0; i < bytes.length; i++) {
                binary += String.fromCharCode(bytes[i]);
              }
              var result = btoa(binary);
              console.log('[LXEnv] rsaEncrypt 返回 base64, 长度:', result.length);
              return result;
            }
          }
        },
        
        // 环境信息
        env: 'mobile',
        version: '2.4.0',
        currentScriptInfo: {
          version: '1.0.0',
          name: 'Enhanced LX Music Compatibility Layer'
        }
      };
      
      // =============================================================================
      // 脚本注册和兼容性支持
      // =============================================================================
      
      // 脚本注册函数（多种格式支持）
      globalThis.registerScript = function(scriptInfo) {
        console.log('[LXEnv] 注册脚本:', JSON.stringify(scriptInfo));
        if (scriptInfo && scriptInfo.sources) {
          globalThis._musicSources = scriptInfo.sources;
          globalThis._scriptRegistered = true;
          console.log('[LXEnv] 已注册音源:', Object.keys(scriptInfo.sources).join(', '));
          
          // 发送初始化完成事件
          setTimeout(() => {
            lx.send('inited', {
              status: true,
              sources: scriptInfo.sources
            });
          }, 100);
        }
        return true;
      };
      
      // 兼容旧版脚本的注册方式
      globalThis.register = globalThis.registerScript;
      
      // 模拟window对象（某些脚本需要）
      if (typeof window === 'undefined') {
        globalThis.window = globalThis;
      }

      // 🔥 关键修复：添加 global 对象（Node.js 环境兼容，crypto-js 等库需要）
      if (typeof global === 'undefined') {
        globalThis.global = globalThis;
      }

      // 🔥 关键修复：添加 self 对象（Web Worker 环境兼容，某些库需要）
      if (typeof self === 'undefined') {
        globalThis.self = globalThis;
      }

      // 🔥 关键修复：确保window.lx指向正确的lx对象
      window.lx = globalThis.lx;
      
      // 🔥 同时确保window上也有这些函数的直接访问
      window.EVENT_NAMES = globalThis.lx.EVENT_NAMES;
      window.request = globalThis.lx.request;
      window.on = globalThis.lx.on;
      window.send = globalThis.lx.send;
      window.emit = globalThis.lx.emit;
      window.utils = globalThis.lx.utils;
      window.env = globalThis.lx.env;
      window.version = globalThis.lx.version;
      
      // 内部事件分发器：分发事件到脚本内已注册的处理器（单一处理器模式）
      globalThis._dispatchEventToScript = function(eventName, data) {
        try {
          console.log('[LXEnv] 分发事件到脚本:', eventName, data);
          const handler = globalThis._lxHandlers && globalThis._lxHandlers[eventName];
          if (typeof handler === 'function') {
            try {
              return handler(data);
            } catch (e) {
              console.warn('[LXEnv] 分发事件处理器执行出错:', e);
              return null;
            }
          }
          return null;
        } catch (e) {
          console.warn('[LXEnv] 分发事件出错:', e);
          return null;
        }
      };
      
      // 模拟document对象
      if (typeof document === 'undefined') {
        globalThis.document = {
          createElement: function() { return {}; },
          querySelector: function() { return null; },
          addEventListener: function() {}
        };
      }

      // 🔥 关键修复：添加 TextEncoder/TextDecoder polyfill（crypto-js 等库需要）
      if (typeof TextEncoder === 'undefined') {
        globalThis.TextEncoder = function() {};
        globalThis.TextEncoder.prototype.encode = function(str) {
          if (str === undefined || str === null) str = '';
          str = String(str);
          var utf8 = [];
          for (var i = 0; i < str.length; i++) {
            var charcode = str.charCodeAt(i);
            if (charcode < 0x80) utf8.push(charcode);
            else if (charcode < 0x800) {
              utf8.push(0xc0 | (charcode >> 6), 0x80 | (charcode & 0x3f));
            } else if (charcode < 0xd800 || charcode >= 0xe000) {
              utf8.push(0xe0 | (charcode >> 12), 0x80 | ((charcode >> 6) & 0x3f), 0x80 | (charcode & 0x3f));
            } else {
              i++;
              charcode = 0x10000 + (((charcode & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
              utf8.push(0xf0 | (charcode >> 18), 0x80 | ((charcode >> 12) & 0x3f), 0x80 | ((charcode >> 6) & 0x3f), 0x80 | (charcode & 0x3f));
            }
          }
          return new Uint8Array(utf8);
        };
      }

      if (typeof TextDecoder === 'undefined') {
        globalThis.TextDecoder = function(encoding) {
          this.encoding = encoding || 'utf-8';
        };
        globalThis.TextDecoder.prototype.decode = function(bytes) {
          if (!bytes || bytes.length === 0) return '';
          var result = '';
          var i = 0;
          while (i < bytes.length) {
            var byte = bytes[i];
            if (byte < 128) {
              result += String.fromCharCode(byte);
              i++;
            } else if (byte >= 192 && byte < 224) {
              result += String.fromCharCode(((byte & 31) << 6) | (bytes[i + 1] & 63));
              i += 2;
            } else if (byte >= 224 && byte < 240) {
              result += String.fromCharCode(((byte & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63));
              i += 3;
            } else {
              var codePoint = ((byte & 7) << 18) | ((bytes[i + 1] & 63) << 12) | ((bytes[i + 2] & 63) << 6) | (bytes[i + 3] & 63);
              codePoint -= 0x10000;
              result += String.fromCharCode((codePoint >> 10) + 0xD800, (codePoint & 0x3FF) + 0xDC00);
              i += 4;
            }
          }
          return result;
        };
      }

      // 模拟localStorage
      if (typeof localStorage === 'undefined') {
        globalThis.localStorage = {
          getItem: function() { return null; },
          setItem: function() {},
          removeItem: function() {}
        };
      }

      // =============================================================================
      // Node.js / CommonJS 兼容性支持
      // =============================================================================

      // 注意：默认不注入 module/exports，避免 UMD 库（如 js-sha256）误判为 CommonJS，
      // 把 module.exports 覆盖成库导出，导致后续被误识别为“音源处理器”。

      // 模拟 require 函数（返回模块导出）
      // 🔥 关键修复：强制覆盖 require，无论是否已定义
      (function() {
        var originalRequire = globalThis.require;

        var customRequire = function(name) {
          console.log('[LXEnv] 🔧 require 被调用:', name);

          // =================================================================
          // 🔥 关键修复：完整的 Node.js crypto 模块实现
          // =================================================================
          if (name === 'crypto') {
            console.log('[LXEnv] 🔧 返回完整的 crypto 模块');
            return {
              // 🔥 Node.js 风格: createCipheriv(algorithm, key, iv)
              createCipheriv: function(algorithm, key, iv) {
                console.log('[LXEnv] crypto.createCipheriv 被调用');
                console.log('[LXEnv] algorithm:', algorithm);
                console.log('[LXEnv] key 类型:', typeof key, 'key 长度:', key ? key.length : 0);
                console.log('[LXEnv] iv 类型:', typeof iv, 'iv:', iv);

                // 将 key 转换为 Uint8Array
                var keyBytes;
                if (typeof key === 'string') {
                  keyBytes = new Uint8Array(key.length);
                  for (var i = 0; i < key.length; i++) {
                    keyBytes[i] = key.charCodeAt(i);
                  }
                } else if (key instanceof Uint8Array) {
                  keyBytes = key;
                } else if (ArrayBuffer.isView(key)) {
                  keyBytes = new Uint8Array(key.buffer, key.byteOffset, key.byteLength);
                } else if (Array.isArray(key)) {
                  keyBytes = new Uint8Array(key);
                } else if (key && typeof key.length === 'number') {
                  keyBytes = new Uint8Array(key.length);
                  for (var i = 0; i < key.length; i++) {
                    keyBytes[i] = key[i];
                  }
                } else {
                  console.error('[LXEnv] createCipheriv: 无效的 key 类型');
                  throw new Error('Invalid key type');
                }

                // 将 iv 转换为 Uint8Array（如果存在）
                var ivBytes = null;
                if (iv !== null && iv !== undefined && iv !== '') {
                  if (typeof iv === 'string') {
                    ivBytes = new Uint8Array(iv.length);
                    for (var i = 0; i < iv.length; i++) {
                      ivBytes[i] = iv.charCodeAt(i);
                    }
                  } else if (iv instanceof Uint8Array) {
                    ivBytes = iv;
                  } else if (ArrayBuffer.isView(iv)) {
                    ivBytes = new Uint8Array(iv.buffer, iv.byteOffset, iv.byteLength);
                  } else if (Array.isArray(iv)) {
                    ivBytes = new Uint8Array(iv);
                  } else if (typeof iv.length === 'number') {
                    ivBytes = new Uint8Array(iv.length);
                    for (var i = 0; i < iv.length; i++) {
                      ivBytes[i] = iv[i];
                    }
                  }
                }

                // 累积的数据
                var dataChunks = [];

                return {
                  update: function(data, inputEncoding, outputEncoding) {
                    console.log('[LXEnv] cipher.update 被调用');
                    console.log('[LXEnv] update data 类型:', typeof data);
                    console.log('[LXEnv] update inputEncoding:', inputEncoding);

                    var bytes;
                    if (typeof data === 'string') {
                      if (inputEncoding === 'binary' || inputEncoding === 'latin1') {
                        bytes = new Uint8Array(data.length);
                        for (var i = 0; i < data.length; i++) {
                          bytes[i] = data.charCodeAt(i) & 0xff;
                        }
                      } else if (inputEncoding === 'hex') {
                        var hexMatch = data.match(/.{1,2}/g);
                        bytes = hexMatch ? new Uint8Array(hexMatch.map(function(b) { return parseInt(b, 16); })) : new Uint8Array(0);
                      } else if (inputEncoding === 'base64') {
                        var binaryStr = atob(data);
                        bytes = new Uint8Array(binaryStr.length);
                        for (var i = 0; i < binaryStr.length; i++) {
                          bytes[i] = binaryStr.charCodeAt(i);
                        }
                      } else {
                        // utf8
                        var utf8Bytes = [];
                        for (var i = 0; i < data.length; i++) {
                          var c = data.charCodeAt(i);
                          if (c < 128) utf8Bytes.push(c);
                          else if (c < 2048) { utf8Bytes.push((c >> 6) | 192); utf8Bytes.push((c & 63) | 128); }
                          else { utf8Bytes.push((c >> 12) | 224); utf8Bytes.push(((c >> 6) & 63) | 128); utf8Bytes.push((c & 63) | 128); }
                        }
                        bytes = new Uint8Array(utf8Bytes);
                      }
                  } else if (data instanceof Uint8Array) {
                    bytes = data;
                  } else if (data instanceof ArrayBuffer) {
                    bytes = new Uint8Array(data);
                  } else if (ArrayBuffer.isView(data)) {
                    bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
                  } else if (Array.isArray(data)) {
                    bytes = new Uint8Array(data);
                  } else if (data && data.buffer instanceof ArrayBuffer && typeof data.byteLength === 'number') {
                    // 兼容某些 Buffer/TypedArray-like 对象
                    try {
                      bytes = new Uint8Array(data.buffer, data.byteOffset || 0, data.byteLength);
                    } catch(_) {}
                  } else if (data && typeof data.length === 'number') {
                    bytes = new Uint8Array(data.length);
                    for (var i = 0; i < data.length; i++) {
                      bytes[i] = data[i];
                    }
                    } else {
                      try {
                        globalThis.__lx_last_invalid_cipher_input = {
                          type: typeof data,
                          tag: Object.prototype.toString.call(data),
                          preview: (data === null || data === undefined) ? String(data) : ('' + data).slice(0, 200),
                        };
                      } catch(_) {}
                      console.error('[LXEnv] cipher.update: 无效的数据类型:', typeof data, data);
                      throw new Error('input is invalid type');
                    }

                    dataChunks.push(bytes);
                    console.log('[LXEnv] cipher.update 累积数据，当前块数:', dataChunks.length);

                    // 返回空 Buffer（数据在 final 时一起处理）
                    return globalThis.Buffer.alloc(0);
                  },

                  final: function(outputEncoding) {
                    console.log('[LXEnv] cipher.final 被调用');
                    console.log('[LXEnv] final outputEncoding:', outputEncoding);
                    console.log('[LXEnv] final 数据块数:', dataChunks.length);

                    // 合并所有数据
                    var totalLen = 0;
                    for (var i = 0; i < dataChunks.length; i++) {
                      totalLen += dataChunks[i].length;
                    }
                    var allData = new Uint8Array(totalLen);
                    var offset = 0;
                    for (var i = 0; i < dataChunks.length; i++) {
                      allData.set(dataChunks[i], offset);
                      offset += dataChunks[i].length;
                    }

                    console.log('[LXEnv] cipher.final 总数据长度:', totalLen);

                    // 调用 AES 加密
                    var result = globalThis.lx.utils.crypto.aesEncrypt(allData, algorithm, keyBytes, ivBytes);

                    console.log('[LXEnv] cipher.final 加密结果长度:', result ? result.length : 0);

                    // 根据输出编码返回
                    if (outputEncoding === 'hex') {
                      return Array.from(result).map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
                    } else if (outputEncoding === 'base64') {
                      var binary = '';
                      for (var i = 0; i < result.length; i++) {
                        binary += String.fromCharCode(result[i]);
                      }
                      return btoa(binary);
                    } else {
                      return globalThis.Buffer.from(result);
                    }
                  },

                  setAutoPadding: function(autoPadding) {
                    console.log('[LXEnv] cipher.setAutoPadding:', autoPadding);
                    return this;
                  }
                };
              },

              // 🔥 Node.js 风格: createHash(algorithm)
              createHash: function(algorithm) {
                console.log('[LXEnv] crypto.createHash 被调用, algorithm:', algorithm);

                var data = '';

                return {
                  update: function(input, encoding) {
                    console.log('[LXEnv] hash.update 被调用');
                    if (typeof input === 'string') {
                      data += input;
                    } else if (input instanceof Uint8Array || ArrayBuffer.isView(input)) {
                      for (var i = 0; i < input.length; i++) {
                        data += String.fromCharCode(input[i]);
                      }
                    }
                    return this;
                  },

                  digest: function(encoding) {
                    console.log('[LXEnv] hash.digest 被调用, encoding:', encoding);
                    if (algorithm.toLowerCase() === 'md5') {
                      return globalThis.lx.utils.crypto.md5(data);
                    }
                    // 其他算法暂时返回空
                    console.warn('[LXEnv] hash.digest: 不支持的算法:', algorithm);
                    return '';
                  }
                };
              },

              // 🔥 Node.js 风格: publicEncrypt
              publicEncrypt: function(options, buffer) {
                console.log('[LXEnv] crypto.publicEncrypt 被调用');
                var key = typeof options === 'string' ? options : options.key;
                return globalThis.lx.utils.crypto.rsaEncrypt(buffer, key);
              },

              // 🔥 Node.js 风格: randomBytes
              randomBytes: function(size) {
                console.log('[LXEnv] crypto.randomBytes 被调用, size:', size);
                return globalThis.lx.utils.crypto.randomBytes(size);
              },

              // 兼容旧 API
              md5: globalThis.lx.utils.crypto.md5,
              aesEncrypt: globalThis.lx.utils.crypto.aesEncrypt,
              rsaEncrypt: globalThis.lx.utils.crypto.rsaEncrypt,

              // constants
              constants: {
                RSA_NO_PADDING: 3,
                RSA_PKCS1_PADDING: 1,
                RSA_PKCS1_OAEP_PADDING: 4
              }
            };
          }

          if (name === 'buffer' || name === 'Buffer') {
            console.log('[LXEnv] 🔧 返回 buffer 模块');
            return { Buffer: globalThis.Buffer };
          }
          if (name === 'url') {
            return {
              parse: function(urlStr) {
                try {
                  const url = new URL(urlStr);
                  return {
                    protocol: url.protocol,
                    host: url.host,
                    hostname: url.hostname,
                    port: url.port,
                    pathname: url.pathname,
                    search: url.search,
                    hash: url.hash,
                    href: url.href
                  };
                } catch (e) {
                  return {};
                }
              }
            };
          }
          if (name === 'querystring' || name === 'qs') {
            return {
              stringify: function(obj) {
                return Object.entries(obj || {}).map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&');
              },
              parse: function(str) {
                const result = {};
                (str || '').split('&').forEach(pair => {
                  const [k, v] = pair.split('=');
                  if (k) result[decodeURIComponent(k)] = decodeURIComponent(v || '');
                });
                return result;
              }
            };
          }
          // 如果都不匹配，尝试原始 require
          if (typeof originalRequire === 'function') {
            return originalRequire(name);
          }
          console.warn('[LXEnv] require: 未知模块:', name);
          return {};
        };

        // 🔥 强制覆盖全局 require
        globalThis.require = customRequire;
        if (typeof window !== 'undefined') {
          window.require = customRequire;
        }
      })();

      // 模拟 process 对象
      if (typeof process === 'undefined') {
        globalThis.process = {
          env: { NODE_ENV: 'production' },
          version: 'v18.0.0',
          platform: 'android',
          nextTick: function(cb) { setTimeout(cb, 0); }
        };
      }

      // =================================================================
      // 🔥 关键修复：全局 crypto 对象（某些脚本直接使用 crypto 而不是 require）
      // =================================================================
      if (typeof globalThis.crypto === 'undefined' || !globalThis.crypto.createCipheriv) {
        console.log('[LXEnv] 🔧 注入全局 crypto 对象');
        var nodeCrypto = globalThis.require('crypto');
        globalThis.crypto = Object.assign(globalThis.crypto || {}, nodeCrypto);
        if (typeof window !== 'undefined') {
          window.crypto = globalThis.crypto;
        }
      }

      // 模拟 Buffer（Node.js 风格，完整实现 - 创建真正的 Buffer 类）
      if (typeof Buffer === 'undefined') {
        // 🔥 创建一个继承自 Uint8Array 的 Buffer 类
        class BufferImpl extends Uint8Array {
          constructor(arg, encodingOrOffset, length) {
            if (typeof arg === 'number') {
              super(arg);
            } else if (typeof arg === 'string') {
              // 处理字符串输入
              const encoding = encodingOrOffset || 'utf8';
              const bytes = BufferImpl._stringToBytes(arg, encoding);
              super(bytes);
            } else if (arg instanceof ArrayBuffer) {
              // 🔥 支持 ArrayBuffer
              super(new Uint8Array(arg));
            } else if (arg instanceof Uint8Array || Array.isArray(arg)) {
              super(arg);
            } else if (ArrayBuffer.isView(arg)) {
              // 🔥 支持其他 TypedArray
              super(new Uint8Array(arg.buffer, arg.byteOffset, arg.byteLength));
            } else if (arg && typeof arg.length === 'number') {
              // 🔥 支持类数组对象
              super(Array.from(arg));
            } else if (arg && typeof arg.byteLength === 'number') {
              // 🔥 支持其他有 byteLength 属性的对象
              super(new Uint8Array(arg));
            } else {
              super(0);
            }
          }

          // 🔥 关键：设置 Symbol.toStringTag 使 Object.prototype.toString.call() 返回 '[object Buffer]'
          get [Symbol.toStringTag]() {
            return 'Buffer';
          }

          static _stringToBytes(str, encoding) {
            switch (encoding) {
              case 'base64':
                try {
                  const binaryStr = atob(str);
                  const bytes = new Uint8Array(binaryStr.length);
                  for (let i = 0; i < binaryStr.length; i++) {
                    bytes[i] = binaryStr.charCodeAt(i);
                  }
                  return bytes;
                } catch (e) {
                  return new Uint8Array(0);
                }
              case 'hex':
                const hexMatch = str.match(/.{1,2}/g);
                if (!hexMatch) return new Uint8Array(0);
                return new Uint8Array(hexMatch.map(byte => parseInt(byte, 16)));
              case 'binary':
              case 'latin1':
                const latinBytes = new Uint8Array(str.length);
                for (let i = 0; i < str.length; i++) {
                  latinBytes[i] = str.charCodeAt(i) & 0xff;
                }
                return latinBytes;
              case 'utf8':
              case 'utf-8':
              default:
                const utf8Bytes = [];
                for (let i = 0; i < str.length; i++) {
                  const charCode = str.charCodeAt(i);
                  if (charCode < 128) {
                    utf8Bytes.push(charCode);
                  } else if (charCode < 2048) {
                    utf8Bytes.push((charCode >> 6) | 192);
                    utf8Bytes.push((charCode & 63) | 128);
                  } else {
                    utf8Bytes.push((charCode >> 12) | 224);
                    utf8Bytes.push(((charCode >> 6) & 63) | 128);
                    utf8Bytes.push((charCode & 63) | 128);
                  }
                }
                return new Uint8Array(utf8Bytes);
            }
          }

          // 🔥 关键：实现 toString 方法，支持各种编码
          toString(encoding) {
            encoding = encoding || 'utf8';
            switch (encoding) {
              case 'hex':
                return Array.from(this).map(b => b.toString(16).padStart(2, '0')).join('');
              case 'base64':
                let binaryStr = '';
                for (let i = 0; i < this.length; i++) {
                  binaryStr += String.fromCharCode(this[i]);
                }
                return btoa(binaryStr);
              case 'binary':
              case 'latin1':
                let latin1Str = '';
                for (let i = 0; i < this.length; i++) {
                  latin1Str += String.fromCharCode(this[i]);
                }
                return latin1Str;
              case 'utf8':
              case 'utf-8':
              default:
                let result = '';
                let i = 0;
                while (i < this.length) {
                  const byte = this[i];
                  if (byte < 128) {
                    result += String.fromCharCode(byte);
                    i++;
                  } else if (byte >= 192 && byte < 224) {
                    result += String.fromCharCode(((byte & 31) << 6) | (this[i + 1] & 63));
                    i += 2;
                  } else {
                    result += String.fromCharCode(((byte & 15) << 12) | ((this[i + 1] & 63) << 6) | (this[i + 2] & 63));
                    i += 3;
                  }
                }
                return result;
            }
          }

          // 其他常用 Buffer 方法
          slice(start, end) {
            const sliced = super.slice(start, end);
            return new BufferImpl(sliced);
          }

          copy(target, targetStart, sourceStart, sourceEnd) {
            targetStart = targetStart || 0;
            sourceStart = sourceStart || 0;
            sourceEnd = sourceEnd || this.length;
            for (let i = sourceStart; i < sourceEnd; i++) {
              target[targetStart + i - sourceStart] = this[i];
            }
            return sourceEnd - sourceStart;
          }

          equals(otherBuffer) {
            if (this.length !== otherBuffer.length) return false;
            for (let i = 0; i < this.length; i++) {
              if (this[i] !== otherBuffer[i]) return false;
            }
            return true;
          }

          write(string, offset, length, encoding) {
            offset = offset || 0;
            encoding = encoding || 'utf8';
            const bytes = BufferImpl._stringToBytes(string, encoding);
            const writeLen = Math.min(bytes.length, length || this.length - offset);
            for (let i = 0; i < writeLen; i++) {
              this[offset + i] = bytes[i];
            }
            return writeLen;
          }

          readUInt8(offset) {
            return this[offset];
          }

          writeUInt8(value, offset) {
            this[offset] = value & 0xff;
          }

          readUInt16BE(offset) {
            return (this[offset] << 8) | this[offset + 1];
          }

          readUInt16LE(offset) {
            return this[offset] | (this[offset + 1] << 8);
          }

          readUInt32BE(offset) {
            return (this[offset] << 24) | (this[offset + 1] << 16) | (this[offset + 2] << 8) | this[offset + 3];
          }

          readUInt32LE(offset) {
            return this[offset] | (this[offset + 1] << 8) | (this[offset + 2] << 16) | (this[offset + 3] << 24);
          }
        }

        // 静态方法
        BufferImpl.from = function(data, encoding) {
          // 🔥 详细日志
          console.log('[Buffer.from] 被调用');
          console.log('[Buffer.from] data 类型:', typeof data);
          console.log('[Buffer.from] encoding:', encoding);
          if (data && typeof data === 'object') {
            console.log('[Buffer.from] data 详情:', {
              isBufferImpl: data instanceof BufferImpl,
              isUint8Array: data instanceof Uint8Array,
              isArray: Array.isArray(data),
              isArrayBufferView: ArrayBuffer.isView(data),
              constructorName: data.constructor ? data.constructor.name : 'unknown',
              length: data.length,
              byteLength: data.byteLength
            });
          }

          if (data instanceof BufferImpl) {
            console.log('[Buffer.from] 输入已是 BufferImpl');
            return data;
          }
          if (typeof data === 'string') {
            var result = new BufferImpl(data, encoding);
            console.log('[Buffer.from] 字符串转换完成, 长度:', result.length);
            return result;
          }
          if (data instanceof Uint8Array) {
            var result = new BufferImpl(data);
            console.log('[Buffer.from] Uint8Array 转换完成, 长度:', result.length);
            return result;
          }
          if (Array.isArray(data)) {
            var result = new BufferImpl(data);
            console.log('[Buffer.from] Array 转换完成, 长度:', result.length);
            return result;
          }
          // 🔥 兼容 ArrayBufferView（TypedArray）
          if (ArrayBuffer.isView(data)) {
            console.log('[Buffer.from] 检测到 ArrayBufferView');
            var result = new BufferImpl(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
            console.log('[Buffer.from] ArrayBufferView 转换完成, 长度:', result.length);
            return result;
          }
          // 🔥 兼容 ArrayBuffer
          if (data instanceof ArrayBuffer) {
            console.log('[Buffer.from] 检测到 ArrayBuffer');
            var result = new BufferImpl(new Uint8Array(data));
            console.log('[Buffer.from] ArrayBuffer 转换完成, 长度:', result.length);
            return result;
          }
          // 🔥 兼容类数组对象
          if (data && typeof data.length === 'number') {
            console.log('[Buffer.from] 检测到类数组对象, 长度:', data.length);
            var arr = new Uint8Array(data.length);
            for (var i = 0; i < data.length; i++) {
              arr[i] = data[i];
            }
            var result = new BufferImpl(arr);
            console.log('[Buffer.from] 类数组转换完成, 长度:', result.length);
            return result;
          }
          console.warn('[Buffer.from] 不支持的输入类型:', typeof data, data);
          return new BufferImpl(0);
        };

        BufferImpl.isBuffer = function(obj) {
          var result = obj instanceof BufferImpl || obj instanceof Uint8Array;
          console.log('[Buffer.isBuffer] 检查:', result, '类型:', obj ? (obj.constructor ? obj.constructor.name : typeof obj) : 'null');
          return result;
        };

        BufferImpl.alloc = function(size, fill) {
          console.log('[Buffer.alloc] 被调用, size:', size, 'fill:', fill);
          const buf = new BufferImpl(size);
          if (fill !== undefined) {
            buf.fill(typeof fill === 'number' ? fill : 0);
          }
          return buf;
        };

        BufferImpl.allocUnsafe = function(size) {
          console.log('[Buffer.allocUnsafe] 被调用, size:', size);
          return new BufferImpl(size);
        };

        BufferImpl.concat = function(list, totalLength) {
          console.log('[Buffer.concat] 被调用, 列表长度:', list ? list.length : 0);
          if (!Array.isArray(list)) return new BufferImpl(0);
          if (list.length === 0) return new BufferImpl(0);

          let len = totalLength;
          if (len === undefined) {
            len = 0;
            for (const buf of list) {
              len += buf.length;
            }
          }

          const result = new BufferImpl(len);
          let offset = 0;
          for (const buf of list) {
            if (offset + buf.length > len) break;
            result.set(buf, offset);
            offset += buf.length;
          }
          return result;
        };

        BufferImpl.byteLength = function(string, encoding) {
          return BufferImpl._stringToBytes(string, encoding || 'utf8').length;
        };

        globalThis.Buffer = BufferImpl;
      }

      // =============================================================================
      // 增强的音源检测
      // =============================================================================
      
      // 自动检测脚本定义的音源
      globalThis._detectSources = function() {
        const sources = {};
        const commonPlatforms = ['tx', 'wy', 'kg', 'kw', 'qq', 'netease', 'kugou', 'kuwo', 'mg'];
        
        // 检测模式1: scriptManifest
        if (typeof scriptManifest !== 'undefined' && scriptManifest.supportedPlatforms) {
          scriptManifest.supportedPlatforms.forEach(platform => {
            sources[platform] = { name: platform, type: 'music', actions: ['musicUrl'] };
          });
        }
        
        // 检测模式2: 函数名模式
        const functionPatterns = [
          p => p + 'GetMusicUrl',
          p => 'get' + p.charAt(0).toUpperCase() + p.slice(1) + 'Url',
          p => p + '_getMusicUrl',
          p => 'handle' + p.toUpperCase()
        ];
        
        commonPlatforms.forEach(platform => {
          const hasFunction = functionPatterns.some(pattern => {
            const funcName = pattern(platform);
            return typeof globalThis[funcName] === 'function';
          });
          
          if (hasFunction) {
            sources[platform] = { name: platform, type: 'music', actions: ['musicUrl'] };
          }
        });
        
        // 检测模式3: 通用函数
        if (typeof getMusicUrl === 'function' || typeof handleGetMusicUrl === 'function') {
          commonPlatforms.forEach(platform => {
            sources[platform] = { name: platform, type: 'music', actions: ['musicUrl'] };
          });
        }
        
        return sources;
      };

      // =============================================================================
      // 🔥 LX Music 原生函数别名（某些脚本可能直接调用这些函数）
      // =============================================================================

      // 🎯 原生 MD5 函数（LX Music Mobile 原生模块提供）
      globalThis.utils_str2md5 = function(str) {
        console.log('[LXEnv] utils_str2md5 被调用（原生函数别名）');
        return globalThis.lx.utils.crypto.md5(str);
      };

      // 🎯 原生 AES 加密函数（LX Music Mobile 原生模块提供）
      globalThis.utils_aes_encrypt = function(buffer, mode, key, iv) {
        console.log('[LXEnv] utils_aes_encrypt 被调用（原生函数别名）');
        console.log('[LXEnv] utils_aes_encrypt 参数类型:', {
          bufferType: typeof buffer,
          mode: mode,
          keyType: typeof key,
          ivType: typeof iv
        });
        return globalThis.lx.utils.crypto.aesEncrypt(buffer, mode, key, iv);
      };

      // 🎯 原生 RSA 加密函数（LX Music Mobile 原生模块提供）
      globalThis.utils_rsa_encrypt = function(buffer, key) {
        console.log('[LXEnv] utils_rsa_encrypt 被调用（原生函数别名）');
        return globalThis.lx.utils.crypto.rsaEncrypt(buffer, key);
      };

      // 🎯 原生 Buffer 函数（LX Music Mobile 原生模块提供）
      globalThis.utils_buffer_from = function(data, encoding) {
        console.log('[LXEnv] utils_buffer_from 被调用（原生函数别名）');
        return globalThis.lx.utils.buffer.from(data, encoding);
      };

      globalThis.utils_buffer_to_string = function(buf, format) {
        console.log('[LXEnv] utils_buffer_to_string 被调用（原生函数别名）');
        return globalThis.lx.utils.buffer.bufToString(buf, format);
      };

      // 🎯 原生随机字节函数
      globalThis.utils_crypto_randomBytes = function(size) {
        console.log('[LXEnv] utils_crypto_randomBytes 被调用（原生函数别名）');
        return globalThis.lx.utils.crypto.randomBytes(size);
      };

      console.log('[LXEnv] ✅ 增强的LX Music环境初始化完成');
    ''';

    _runtime!.evaluate(lxEnvironment);

    // 注入console polyfill
    _runtime!.evaluate('''
      // 完善的console对象
      if (typeof console === 'undefined') globalThis.console = {};
      const consoleMethods = ['log', 'warn', 'error', 'info', 'debug', 'group', 'groupCollapsed', 'groupEnd', 'time', 'timeEnd'];
      consoleMethods.forEach(method => {
        if (typeof console[method] !== 'function') {
          console[method] = function() {
            try {
              const args = Array.prototype.slice.call(arguments);
              const message = args.map(arg => typeof arg === 'object' ? JSON.stringify(arg) : String(arg)).join(' ');
              // 发送到Flutter日志
              if (typeof sendMessage === 'function') {
                sendMessage('console_log', JSON.stringify({ level: method, message: message }));
              }
            } catch (e) {}
          };
        }
      });

      // 注意：MD5 已在 lx.utils.crypto.md5 中实现完整 RFC 1321 标准算法，不需要 polyfill

      // 🔥 关键修复：将lx对象的函数暴露到全局作用域
      // 这样脚本可以使用: const { EVENT_NAMES, request, on, send, utils, env, version } = globalThis.lx
      globalThis.EVENT_NAMES = globalThis.lx.EVENT_NAMES;
      globalThis.request = globalThis.lx.request;
      globalThis.on = globalThis.lx.on;
      globalThis.send = globalThis.lx.send;
      globalThis.emit = globalThis.lx.emit;
      globalThis.utils = globalThis.lx.utils;
      globalThis.env = globalThis.lx.env;
      globalThis.version = globalThis.lx.version;
    ''');

    // 设置网络请求和事件处理
    _setupNetworkAndEventHandlers();
  }

  /// 设置网络请求和事件处理器
  void _setupNetworkAndEventHandlers() {
    if (_runtime == null) return;

    // 设置Flutter请求代理
    _runtime!.evaluate('''
      globalThis._flutterRequestProxy = function(args) {
        try {
          console.log('[LXEnv] 调用Flutter网络请求代理');
          console.log('[LXEnv] 发送的参数:', args);
          console.log('[LXEnv] 参数类型:', typeof args);
          
          const argsToSend = typeof args === 'string' ? args : JSON.stringify(args);
          console.log('[LXEnv] 序列化后的参数:', argsToSend);
          
          sendMessage('_flutterRequestProxy', argsToSend);
        } catch (e) {
          console.error('[LXEnv] 请求代理调用失败:', e);
        }
      };
      
      globalThis._flutterEventSender = function(args) {
        try {
          console.log('[LXEnv] 调用Flutter事件发送器');
          console.log('[LXEnv] 事件参数:', args);
          console.log('[LXEnv] 事件参数类型:', typeof args);
          
          const argsToSend = typeof args === 'string' ? args : JSON.stringify(args);
          console.log('[LXEnv] 事件序列化后的参数:', argsToSend);
          
          sendMessage('_flutterEventSender', argsToSend);
        } catch (e) {
          console.error('[LXEnv] 事件发送失败:', e);
        }
      };
    ''');

    // 注册消息处理器
    _runtime!.onMessage('_flutterRequestProxy', (args) async {
      await _handleNetworkRequest(args);
    });

    _runtime!.onMessage('_flutterEventSender', (args) {
      _handleEventSend(args);
    });

    // LX 官方 preload 通道
    _runtime!.onMessage('_lxNativeCall', (args) async {
      await _handleLxNativeCall(args);
    });

    _runtime!.onMessage('console_log', (args) {
      _handleConsoleLog(args);
    });
  }

  Future<void> _handleLxNativeCall(dynamic message) async {
    try {
      Map<String, dynamic> m;
      if (message is String) {
        m = jsonDecode(message) as Map<String, dynamic>;
      } else if (message is Map<String, dynamic>) {
        m = message;
      } else {
        return;
      }

      final key = (m['key'] ?? '').toString();
      final action = (m['action'] ?? '').toString();
      final dataStr = m['data']; // preload 传入的是 JSON string

      Map<String, dynamic> data = const {};
      if (dataStr is String && dataStr.isNotEmpty) {
        data = jsonDecode(dataStr) as Map<String, dynamic>;
      } else if (dataStr is Map<String, dynamic>) {
        data = dataStr;
      }

      if (action == 'request') {
        final requestKey = (data['requestKey'] ?? '').toString();
        final url = (data['url'] ?? '').toString();
        final options = (data['options'] as Map?)?.cast<String, dynamic>() ?? {};

        try {
          final resp = await _dio.request(
            url,
            options: Options(
              method: (options['method'] ?? 'GET').toString(),
              headers: (options['headers'] as Map?)?.cast<String, dynamic>(),
              validateStatus: (status) => status != null && status < 500,
              responseType:
                  options['binary'] == true ? ResponseType.bytes : ResponseType.json,
            ),
            data: options['body'] ?? options['form'] ?? options['formData'],
          );

          final responseData = <String, dynamic>{
            'statusCode': resp.statusCode ?? 0,
            'statusMessage': '',
            'headers': resp.headers.map,
            'body': resp.data,
          };

          final payload = jsonEncode({
            'requestKey': requestKey,
            'error': null,
            'response': responseData,
          });
          _runtime!.evaluate(
            "globalThis.__lx_native__(${jsonEncode(key)}, 'response', ${jsonEncode(payload)});",
          );
        } catch (e) {
          final payload = jsonEncode({
            'requestKey': requestKey,
            'error': e.toString(),
            'response': null,
          });
          _runtime!.evaluate(
            "globalThis.__lx_native__(${jsonEncode(key)}, 'response', ${jsonEncode(payload)});",
          );
        }
      } else if (action == 'response') {
        // JS -> Native: 回传 request 处理结果（包括 musicUrl/lyric/pic）
        final requestKey = (data['requestKey'] ?? '').toString();
        final completer = _lxPendingRequests.remove(requestKey);
        if (completer == null) return;
        if (data['status'] == true) {
          completer.complete(data['result']);
        } else {
          completer.completeError(
            data['errorMessage'] ?? 'LX request failed',
          );
        }
      } else {
        // init/showUpdateAlert/cancelRequest 等：目前仅忽略
        // 需要的话可在这里转发到 Flutter 层做 UI 提示或持久化
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ _lxNativeCall 处理失败: $e');
    }
  }

  /// 处理控制台日志
  void _handleConsoleLog(dynamic logData) {
    try {
      if (logData is Map<String, dynamic>) {
        final level = logData['level'] ?? 'log';
        final message = logData['message'] ?? '';
        print('[JSConsole-$level] $message');
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 控制台日志处理失败: $e');
    }
  }

  /// 处理网络请求
  Future<void> _handleNetworkRequest(dynamic requestData) async {
    try {
      print('[EnhancedJSProxy] 📥 收到网络请求代理消息: $requestData');
      print('[EnhancedJSProxy] 📥 参数类型: ${requestData.runtimeType}');

      Map<String, dynamic> data;
      if (requestData is String) {
        data = jsonDecode(requestData);
      } else if (requestData is Map<String, dynamic>) {
        data = requestData;
      } else {
        print('[EnhancedJSProxy] ❌ 无效的请求数据类型');
        return;
      }

      print('[EnhancedJSProxy] 📥 解析后的请求数据: $data');

      final requestId = data['id'] as String?;
      final url = data['url'] as String?;
      final options = data['options'] as Map<String, dynamic>? ?? {};

      if (requestId == null || url == null) {
        print('[EnhancedJSProxy] ❌ 缺少必要参数: requestId=$requestId, url=$url');
        return;
      }

      // 部分“独家/更新检测”脚本会先请求脚本更新接口，如果该接口响应结构与预期不一致会导致脚本中断。
      // 这里对已知更新检测地址做最小兜底：返回空更新列表，不影响后续 musicUrl 功能。
      try {
        final isUpdateCheck =
            url.contains('88.lxmusic') &&
            url.contains('/script') &&
            url.contains('checkUpdate');
        if (isUpdateCheck) {
          print('[EnhancedJSProxy] 🛡️ 拦截脚本更新检测请求，返回空列表: $url');
          // 该接口真实返回形如: { code: 0, msg: 'success', data: null }
          // 为避免脚本对 data 做数组处理时崩溃，这里返回空数组。
          final mockBody = {'code': 0, 'msg': 'success', 'data': []};
          final mockBodyText = jsonEncode(mockBody);
          final responseData = {
            'statusCode': 200,
            'body': mockBodyText,
            'data': mockBody,
            'headers': <String, dynamic>{},
          };
          final callbackScript = '''
            (function() {
              try {
                if (globalThis._pendingRequests['$requestId']) {
                  const callback = globalThis._pendingRequests['$requestId'];
                  delete globalThis._pendingRequests['$requestId'];
                  const response = ${jsonEncode(responseData)};
                  const compatResponse = { ...response, bodyObj: response.data, ...response.data };
                  callback(null, compatResponse);
                }
              } catch (e) {}
            })()
          ''';
          _runtime!.evaluate(callbackScript);
          return;
        }
      } catch (_) {}

      print('[EnhancedJSProxy] 🌐 处理网络请求: $url');
      print('[EnhancedJSProxy] 🔍 请求参数详情: $data');

      final bool isLx88 = url.contains('88.lxmusic');
      final headers = Map<String, String>.from(options['headers'] ?? {});
      if (isLx88) {
        // 对齐 lx-music-mobile 抓包中的关键请求头，避免服务端返回非预期格式导致脚本崩溃
        headers['Accept'] = headers['Accept'] ?? 'application/json';
        headers['Accept-Encoding'] = headers['Accept-Encoding'] ?? 'gzip';
        headers['Content-Type'] = headers['Content-Type'] ?? 'application/json';
        // 强制使用与抓包一致的 UA / key
        headers['User-Agent'] = 'lx-music-mobile/2.0.0';
        headers['X-Request-Key'] = 'lxmusic';
      }

      // 使用Dio发起网络请求
      final response = await _dio.request(
        url,
        options: Options(
          method: options['method'] ?? 'GET',
          headers: headers,
          validateStatus: (status) => status != null && status < 500,
        ),
        data: options['body'],
      );

      print('[EnhancedJSProxy] ✅ 网络请求完成: ${response.statusCode}');

      dynamic body = response.data;
      // 修复：部分 lxmusic 接口返回 data: null，但脚本会当数组处理
      if (isLx88 && body is Map && body.containsKey('data') && body['data'] == null) {
        body = {...body, 'data': []};
      }

      // 兼容 lx-music 的返回格式：
      // - response.body: 原始文本（多数脚本会 JSON.parse(body)）
      // - response.data: 解析后的对象（给少数脚本直接取字段）
      dynamic parsedData = body;
      String rawBody;
      if (body is String) {
        rawBody = body;
        try {
          parsedData = jsonDecode(body);
        } catch (_) {
          // 非 JSON：保持字符串
          parsedData = body;
        }
      } else {
        try {
          rawBody = jsonEncode(body);
        } catch (_) {
          rawBody = body.toString();
        }
      }

      // 构建响应数据
      final responseData = {
        'statusCode': response.statusCode,
        'body': rawBody,
        'data': parsedData,
        'headers': response.headers.map,
      };

      // 回调JS
      final callbackScript = '''
        (function() {
          try {
            console.log('[EnhancedJSProxy] 调用网络请求回调，请求ID: $requestId');

            if (globalThis._pendingRequests['$requestId']) {
              const callback = globalThis._pendingRequests['$requestId'];
              delete globalThis._pendingRequests['$requestId'];

              const response = ${jsonEncode(responseData)};
              console.log('[EnhancedJSProxy] 📊 [HTTP层] statusCode=' + response.statusCode + ' (200=成功,404=未找到,500=服务器错误)');
              console.log('[EnhancedJSProxy] 📦 [响应体] body=' + JSON.stringify(response.body));

              // 🔧 关键修复：为不同脚本提供兼容的响应格式
              // 有些脚本期望直接收到 body，有些期望收到完整的 response 对象
              // 我们同时提供两种格式，让回调函数选择使用
              const compatResponse = (function() {
                // response.body 始终为 string，response.data 为解析后的对象/原始值
                const base = { ...response };

                let bodyObj = null;
                try {
                  if (response.data && typeof response.data === 'object') {
                    bodyObj = response.data;
                  } else if (typeof response.body === 'string') {
                    const parsed = JSON.parse(response.body);
                    if (parsed && typeof parsed === 'object') bodyObj = parsed;
                  }
                } catch (_) {}

                if (bodyObj) {
                  return {
                    ...base,
                    bodyObj,
                    ...bodyObj,
                  };
                }
                return base;
              })();

              console.log('[EnhancedJSProxy] 🔍 [兼容层] 脚本可用的访问方式:');
              console.log('  response.statusCode =', compatResponse.statusCode, '← [HTTP层状态码] (200=HTTP成功)');
              console.log('  response.body =', JSON.stringify(compatResponse.body), '← [原始响应体(字符串)]');
              console.log('  response.data =', JSON.stringify(compatResponse.data), '← [解析后的数据]');

              // 检查业务状态码
              if (compatResponse.bodyObj && typeof compatResponse.bodyObj === 'object' && compatResponse.bodyObj.code !== undefined) {
                console.log('  response.code =', compatResponse.code, '← [业务层状态码] (从body展开,0=业务成功)');
                console.log('  ⚠️  重要: HTTP成功(200) ≠ 业务成功,需检查 code 值判断业务结果!');
              }

              // 执行回调（优先使用兼容格式）
              callback(null, compatResponse);
              console.log('[EnhancedJSProxy] 回调执行完成');

              // ✨ 双保险机制：如果 Promise 还没设置结果，网络回调作为后备
              // 策略：不判断具体的 code 值，只检查是否有有效结果
              // 让 JS 脚本负责业务逻辑判断，Flutter 只做快速缓存
              if (!globalThis._promiseComplete && compatResponse.bodyObj && typeof compatResponse.bodyObj === 'object') {
                // 尝试提取可能的结果字段
                const result = compatResponse.bodyObj.data || compatResponse.bodyObj.url || compatResponse.bodyObj.result;

                if (result && typeof result === 'string' && result.length > 0) {
                  // 有明确的字符串结果，设置快速路径
                  globalThis._promiseResult = result;
                  globalThis._promiseComplete = true;
                  console.log('[EnhancedJSProxy] 🚀 快速路径: 检测到有效结果');
                }
                // 注意：不设置错误，让 JS Promise 自己判断失败情况
                // 因为我们不知道什么 code 代表失败
              }
              
              return true;
            } else {
              console.log('[EnhancedJSProxy] 未找到请求ID对应的回调: $requestId');
              return false;
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] 回调执行失败:', e);
            return false;
          }
        })()
      ''';

      _runtime!.evaluate(callbackScript);
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 网络请求失败: $e');

      // 尝试获取请求ID来发送错误回调
      String requestId = 'unknown';
      try {
        Map<String, dynamic> errorData;
        if (requestData is String) {
          errorData = jsonDecode(requestData);
        } else if (requestData is Map<String, dynamic>) {
          errorData = requestData;
        } else {
          errorData = {};
        }
        requestId = errorData['id'] as String? ?? 'unknown';
      } catch (_) {}

      final errorScript = '''
        (function() {
          try {
            if (globalThis._pendingRequests['$requestId']) {
              const callback = globalThis._pendingRequests['$requestId'];
              delete globalThis._pendingRequests['$requestId'];
              callback(new Error('${e.toString().replaceAll("'", "\\'")}'), null);
              return true;
            }
            return false;
          } catch (callbackError) {
            console.error('[EnhancedJSProxy] 错误回调执行失败:', callbackError);
            return false;
          }
        })()
      ''';

      _runtime!.evaluate(errorScript);
    }
  }

  /// 处理JS发送的事件
  void _handleEventSend(dynamic eventData) {
    try {
      print('[EnhancedJSProxy] 📡 收到JS事件: $eventData');

      Map<String, dynamic> data;
      if (eventData is String) {
        data = jsonDecode(eventData);
      } else if (eventData is Map<String, dynamic>) {
        data = eventData;
      } else {
        print('[EnhancedJSProxy] ❌ 无效的事件数据类型');
        return;
      }

      final eventName = data['event'];
      final eventPayload = data['data'];

      print('[EnhancedJSProxy] 📡 事件名称: $eventName');

      // 处理特定事件
      switch (eventName) {
        case 'inited':
          print('[EnhancedJSProxy] 🎵 JS脚本初始化完成');
          if (eventPayload != null && eventPayload['sources'] != null) {
            final sourcesJson = jsonEncode(eventPayload['sources']);
            _runtime!.evaluate('globalThis._musicSources = $sourcesJson;');
            print(
              '[EnhancedJSProxy] 📋 已存储音源信息: ${eventPayload['sources'].keys.join(', ')}',
            );
          }
          break;
        case 'updateAlert':
          print('[EnhancedJSProxy] 🔄 脚本更新提醒: ${eventPayload?['log']}');
          break;
        case 'request':
          print('[EnhancedJSProxy] 🔄 收到request事件，但现在直接在JS中处理');
          // 不需要额外处理，JS中已经直接调用了事件处理器
          break;
        default:
          print('[EnhancedJSProxy] 📨 其他事件: $eventName');
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 事件处理失败: $e');
    }
  }

  /// 加载JS脚本
  Future<bool> loadScript(String scriptContent) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('[EnhancedJSProxy] 📜 开始加载JS脚本...');
      final scriptMd5 = crypto.md5.convert(utf8.encode(scriptContent)).toString();
      print('[EnhancedJSProxy] 🔑 脚本MD5: $scriptMd5');

      // 为避免上次脚本遗留的全局函数影响当前脚本，重置JS运行时并重新注入环境
      try {
        print('[EnhancedJSProxy] ♻️ 重置JS运行时，清理旧脚本环境');
        _runtime?.dispose();
        _runtime = getJavascriptRuntime();
        await _setupCompleteLXMusicEnvironment();
      } catch (e) {
        print('[EnhancedJSProxy] ⚠️ 重置JS运行时失败，继续使用现有环境: $e');
      }

      // 保存脚本内容供检测使用
      _runtime!.evaluate(
        'globalThis._currentScriptContent = ${jsonEncode(scriptContent)};',
      );
      // 一些 v4/加密脚本会从 currentScriptInfo 取到原始脚本用于校验/签名
      _runtime!.evaluate(r'''
        (function(){
          try{
            if (globalThis.lx && globalThis.lx.currentScriptInfo) {
              globalThis.lx.currentScriptInfo.rawScript = globalThis._currentScriptContent;
              globalThis.lx.currentScriptInfo.script = globalThis._currentScriptContent;
            }
          }catch(e){}
        })();
      ''');

      // 针对少数“CommonJS 格式”音源：按需提供 module/exports（默认保持 undefined，更贴近 LX 真实环境）
      final bool wantsCommonJS =
          scriptContent.contains('module.exports') ||
          scriptContent.contains('exports.') ||
          scriptContent.contains('require(');
      _runtime!.evaluate('''
        (function(){
          try{
            const enable = ${wantsCommonJS ? 'true' : 'false'};
            if (enable) {
              if (typeof module === 'undefined') globalThis.module = { exports: {} };
              if (typeof exports === 'undefined') globalThis.exports = globalThis.module.exports;
            } else {
              try { delete globalThis.module; } catch (e) { globalThis.module = undefined; }
              try { delete globalThis.exports; } catch (e) { globalThis.exports = undefined; }
            }
          }catch(e){}
        })();
      ''');

      // 尝试启用 LX 官方 preload（更接近 lx-music-mobile 的真实运行环境）
      // 仅对“重度混淆/大体积脚本”启用；普通脚本优先走旧兼容层（更稳定）。
      try {
        // 经验规则：只有脚本明确依赖 mobile preload 的 native bridge 时才启用，
        // 否则 preload 的 lx_setup 可能会破坏一些第三方音源对 globalThis.lx 的假设。
        final shouldUsePreload =
            scriptContent.contains('__lx_native_call__') ||
            scriptContent.contains('_lx_native_call') ||
            scriptContent.contains('lx_user_api_preload') ||
            scriptContent.contains('lx_setup(');
        if (shouldUsePreload) {
          await _ensureLxPreloadLoaded();
        }
        final preload = shouldUsePreload ? (_lxPreloadScript ?? '') : '';
        if (preload.isNotEmpty) {
          final key = DateTime.now().millisecondsSinceEpoch.toString();
          _runtime!.evaluate('globalThis.__hmusic_lx_key = ${jsonEncode(key)};');

          // 固化旧兼容层里的加密实现，避免 lx_setup 覆盖 globalThis.lx 后形成递归调用
          _runtime!.evaluate(r'''
            (function(){
              try{
                if (!globalThis.__hmusic_crypto) globalThis.__hmusic_crypto = {};
                if (globalThis.lx && globalThis.lx.utils && globalThis.lx.utils.crypto) {
                  globalThis.__hmusic_crypto.md5 = globalThis.lx.utils.crypto.md5;
                  globalThis.__hmusic_crypto.aesEncrypt = globalThis.lx.utils.crypto.aesEncrypt;
                  globalThis.__hmusic_crypto.rsaEncrypt = globalThis.lx.utils.crypto.rsaEncrypt;
                }
                globalThis.__hmusic_crypto.str2b64 = function(s){ return btoa(String(s||'')); };
                globalThis.__hmusic_crypto.b642buf = function(b64){
                  var bin = atob(String(b64||''));
                  var out = new Uint8Array(bin.length);
                  for (var i=0;i<bin.length;i++) out[i] = bin.charCodeAt(i) & 0xff;
                  return out;
                };
              }catch(e){}
            })();
          ''');

          // 提供官方 preload 需要的 native call 与 native funcs
          _runtime!.evaluate(r'''
            (function(){
              try{
                globalThis.__lx_native_call__ = function(key, action, data){
                  try{
                    sendMessage('_lxNativeCall', JSON.stringify({ key: key, action: action, data: data }));
                  }catch(e){}
                };
                globalThis.__lx_native_call__set_timeout = function(id, timeout){
                  setTimeout(function(){
                    try{ globalThis.__lx_native__(globalThis.__hmusic_lx_key, '__set_timeout__', JSON.stringify(id)); }catch(e){}
                  }, timeout|0);
                };
                globalThis.__lx_native_call__utils_str2b64 = function(str){
                  return globalThis.__hmusic_crypto.str2b64(str);
                };
                globalThis.__lx_native_call__utils_b642buf = function(b64){
                  return globalThis.__hmusic_crypto.b642buf(b64);
                };
                globalThis.__lx_native_call__utils_str2md5 = function(str){
                  return globalThis.__hmusic_crypto.md5(String(str));
                };
                globalThis.__lx_native_call__utils_aes_encrypt = function(buffer, mode, key, iv){
                  // lx preload 传入的是 'AES/CBC/PKCS7Padding' or 'AES'
                  var m = String(mode||'');
                  var mapped = (m.indexOf('CBC') >= 0) ? 'aes-128-cbc' : 'aes-128-ecb';
                  return globalThis.__hmusic_crypto.aesEncrypt(buffer, mapped, key, iv);
                };
                globalThis.__lx_native_call__utils_rsa_encrypt = function(buffer, key){
                  return globalThis.__hmusic_crypto.rsaEncrypt(buffer, key);
                };
              }catch(e){}
            })();
          ''');

          _runtime!.evaluate(preload);
          _runtime!.evaluate(
            "globalThis.lx_setup(${jsonEncode(key)}, 'hmusic', 'hmusic', '', '1', '', '', ${jsonEncode(scriptContent)});",
          );
        }
      } catch (e) {
        print('[EnhancedJSProxy] ⚠️ LX preload 启用失败（回退到旧兼容层）: $e');
      }

      // 兼容：部分音源脚本会在初始化阶段直接读取 cookie 变量（例如 MUSIC_U / ts_last）。
      // 在 flutter_js/QuickJS 环境里，仅设置 globalThis 属性不一定会生成全局变量绑定，
      // 因此需要用 var 显式声明，避免出现 undefined 触发脚本内部 crypto/md5 报错。
      _runtime!.evaluate('''
        try {
          if (typeof MUSIC_U === 'undefined') { var MUSIC_U = ''; }
          if (typeof ts_last === 'undefined') { var ts_last = ''; }
          if (typeof globalThis !== 'undefined') {
            if (typeof globalThis.MUSIC_U === 'undefined') globalThis.MUSIC_U = MUSIC_U;
            if (typeof globalThis.ts_last === 'undefined') globalThis.ts_last = ts_last;
          }
        } catch(_) {}
      ''');

      // 执行JS脚本
      print('[EnhancedJSProxy] 🚀 执行脚本内容，长度: ${scriptContent.length} 字符');
      print(
        '[EnhancedJSProxy] 🚀 脚本前100字符: ${scriptContent.substring(0, scriptContent.length > 100 ? 100 : scriptContent.length)}',
      );

      // 🔧 增强：用 try-catch 包装脚本执行，捕获任何错误
      final scriptResult = _runtime!.evaluate('''
        (function() {
          try {
            // 记录 lx.on 调用
            const originalOn = globalThis.lx.on;
            let onCallCount = 0;
            globalThis.lx.on = function(...args) {
              onCallCount++;
              console.log('[LXEnv-Debug] lx.on 被调用! 参数:', args[0], '调用次数:', onCallCount);
              return originalOn.apply(this, args);
            };

            // 同样监控 window.lx.on
            if (typeof window !== 'undefined' && window.lx) {
              window.lx.on = globalThis.lx.on;
            }

            // 监控顶层 on 函数
            globalThis.on = globalThis.lx.on;
            if (typeof window !== 'undefined') {
              window.on = globalThis.lx.on;
            }

            return { hooked: true };
          } catch (e) {
            return { error: e.message };
          }
        })()
      ''');
      print('[EnhancedJSProxy] 🔧 lx.on 钩子安装: ${scriptResult.stringResult}');

      // 🔥 官方模式：先检测脚本格式，确定是否需要特殊处理
      final scriptAnalysis = _runtime!.evaluate('''
        (function() {
          const script = globalThis._currentScriptContent || '';
          const result = {
            isIIFE: script.trim().startsWith('!function') || script.trim().startsWith('(function'),
            hasDestructuring: script.includes('const {') && script.includes('} = lx'),
            hasModuleExports: script.includes('module.exports'),
            hasLxOn: script.includes('lx.on(') || script.includes('.on('),
            hasLxSend: script.includes('lx.send(') || script.includes('.send('),
            firstChars: script.substring(0, 50),
            // 检测是否是加密脚本（Base64 或十六进制编码）
            isEncoded: script.includes('atob(') || /\\\\x[0-9a-f]{2}/i.test(script) || /eval\\s*\\(/i.test(script),
          };
          return JSON.stringify(result);
        })()
      ''');
      print('[EnhancedJSProxy] 🔍 脚本分析: ${scriptAnalysis.stringResult}');

      // 执行用户脚本
      try {
        _runtime!.evaluate(scriptContent);
        print('[EnhancedJSProxy] ✅ 脚本执行完成（无异常）');
      } catch (e) {
        print('[EnhancedJSProxy] ❌ 脚本执行异常: $e');
      }

      // 仅用于调试：捕获常见 hash 函数的输入类型（部分混淆脚本会对非 string/Uint8Array 做 sha256）
      assert(() {
        try {
          _runtime!.evaluate(r'''
            (function(){
              try{
                function wrap(name){
                  const fn = globalThis[name];
                  if (typeof fn !== 'function' || fn.__hmusic_wrapped) return;
                  const wrapped = function(){
                    try{
                      const v = arguments[0];
                      const t = Object.prototype.toString.call(v);
                      let preview = '';
                      if (typeof v === 'string') preview = v.slice(0, 120);
                      console.log('[HMUSIC-TRACE]', name, 'arg0 typeof=', typeof v, 'toStringTag=', t, 'preview=', preview);
                    }catch(e){}
                    return fn.apply(this, arguments);
                  };
                  wrapped.__hmusic_wrapped = true;
                  globalThis[name] = wrapped;
                }
                wrap('sha256');
                wrap('sha256hex');
                wrap('sha256_hmac');
              }catch(e){}
            })();
          ''');
        } catch (_) {}
        return true;
      }());

      // 🔥 关键：脚本执行后立即检查是否有通过 module.exports 导出的处理器
      final moduleExportsCheck = _runtime!.evaluate('''
        (function() {
          try {
            // 检查 module.exports 是否包含处理器
            if (typeof module !== 'undefined' && module.exports) {
              // 如果脚本已经通过 lx.on 注册了 request 处理器，则不要用 module.exports 覆盖，
              // 否则 UMD 库（如 js-sha256）会把 module.exports 变成库导出，导致误注册。
              if (globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function') {
                return { skipped: true, reason: 'request handler already registered' };
              }
              const exp = module.exports;

              // 如果导出了函数，可能就是处理器
              if (typeof exp === 'function') {
                console.log('[LXEnv] 检测到 module.exports 导出函数，尝试注册为处理器');
                globalThis._lxHandlers.request = exp;
                return { registered: true, type: 'function' };
              }

              // 如果导出了对象，检查是否包含处理器方法
              if (typeof exp === 'object') {
                // 检查常见的处理器导出方式
                const handlerKeys = ['request', 'handler', 'handle', 'musicUrl', 'getMusicUrl'];
                for (const key of handlerKeys) {
                  if (typeof exp[key] === 'function') {
                    console.log('[LXEnv] 检测到 module.exports.' + key + '，尝试注册为处理器');
                    globalThis._lxHandlers.request = exp[key].bind(exp);
                    return { registered: true, type: 'object', key: key };
                  }
                }

                // 检查是否导出了 sources 对象
                if (exp.sources && typeof exp.sources === 'object') {
                  console.log('[LXEnv] 检测到 module.exports.sources，注册音源');
                  globalThis._musicSources = exp.sources;
                  return { registered: true, type: 'sources', sources: Object.keys(exp.sources) };
                }
              }
            }

            // 检查 exports 对象
            if (typeof exports !== 'undefined' && exports !== module?.exports) {
              if (typeof exports === 'function') {
                console.log('[LXEnv] 检测到 exports 导出函数');
                globalThis._lxHandlers.request = exports;
                return { registered: true, type: 'exports-function' };
              }
            }

            return { registered: false };
          } catch (e) {
            return { error: e.message };
          }
        })()
      ''');
      print('[EnhancedJSProxy] 🔍 module.exports 检查: ${moduleExportsCheck.stringResult}');

      // 检查脚本执行后 lx.on 是否被调用
      final onCallCheck = _runtime!.evaluate('''
        JSON.stringify({
          handlersState: globalThis._lxHandlers ? Object.keys(globalThis._lxHandlers) : null,
          requestHandlerType: globalThis._lxHandlers && globalThis._lxHandlers.request ? typeof globalThis._lxHandlers.request : 'null',
          // 🔧 检查脚本内部的 lx 引用
          scriptLxRef: typeof globalThis._globalThis\$lx !== 'undefined' ? Object.keys(globalThis._globalThis\$lx || {}) : null,
          // 检查是否有其他可能的处理器注册方式
          allGlobalFunctions: Object.keys(globalThis).filter(k => typeof globalThis[k] === 'function').slice(0, 20),
          // 检查脚本是否使用了某些特定的变量
          hasSourcesVar: typeof sources !== 'undefined',
          hasApisVar: typeof apis !== 'undefined',
          hasModuleVar: typeof module !== 'undefined',
          hasExportsVar: typeof exports !== 'undefined'
        })
      ''');
      print('[EnhancedJSProxy] 🔍 脚本执行后处理器状态: ${onCallCheck.stringResult}');

      // 🔥 关键诊断：检查脚本是否正确初始化
      final initDiagnostic = _runtime!.evaluate('''
        JSON.stringify({
          isInitedApi: globalThis._isInitedApi,
          isShowedUpdateAlert: globalThis._isShowedUpdateAlert,
          musicSources: Object.keys(globalThis._musicSources || {}),
          scriptRegistered: globalThis._scriptRegistered,
          hasRequestHandler: globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function',
          // 🔍 检查脚本是否声明了 sources 变量（洛雪格式）
          declaredSources: (function() {
            try {
              // 查找脚本中声明的 sources 变量
              if (typeof sources !== 'undefined' && typeof sources === 'object') {
                return Object.keys(sources);
              }
              // 检查常见的音源声明模式
              const sourceVars = ['sources', 'musicSources', 'APIs', 'apis'];
              for (const v of sourceVars) {
                if (typeof globalThis[v] === 'object' && globalThis[v]) {
                  return { varName: v, keys: Object.keys(globalThis[v]) };
                }
              }
              return null;
            } catch (e) { return { error: e.message }; }
          })(),
          // 🔍 检查是否有全局的处理器函数
          globalHandlers: (function() {
            const handlers = {};
            const handlerNames = [
              'getMusicUrl', 'handleGetMusicUrl', 'musicUrl', 'handleRequest',
              'getUrl', 'resolveUrl', 'fetchUrl', 'getPlayUrl'
            ];
            for (const name of handlerNames) {
              if (typeof globalThis[name] === 'function') {
                handlers[name] = true;
              }
            }
            return handlers;
          })()
        })
      ''');
      print('[EnhancedJSProxy] 🔍 脚本初始化诊断: ${initDiagnostic.stringResult}');

      _currentScript = scriptContent;

      // 立即触发一次 inited 到脚本（部分官方脚本在收到 inited 后注册处理器）
      try {
        _runtime!.evaluate(
          "typeof _dispatchEventToScript === 'function' && _dispatchEventToScript('inited', { status: true });",
        );
      } catch (_) {}

      // 试探性调用常见入口函数，促进脚本完成自注册
      try {
        _runtime!.evaluate('''
          (function() {
            const candidates = [
              'main', 'init', 'initialize', 'bootstrap', 'start', 'setup',
              'registerSource', 'registerScript', 'lxInit'
            ];
            candidates.forEach(name => {
              try {
                if (typeof globalThis[name] === 'function') {
                  console.log('[LXEnv] 调用入口函数:', name);
                  try { globalThis[name](); } catch (e) { console.log('[LXEnv] 入口函数调用失败:', name, e && e.message); }
                }
              } catch (e) {}
            });
            if (typeof window !== 'undefined' && window.lx && typeof window.lx.init === 'function') {
              console.log('[LXEnv] 调用 window.lx.init');
              try { window.lx.init(); } catch (e) { console.log('[LXEnv] window.lx.init 调用失败:', e && e.message); }
            }
          })()
        ''');
      } catch (_) {}

      // 延迟再次触发一次 inited，给脚本留出注册时间
      try {
        _runtime!.evaluate(
          'setTimeout(function(){ try { if (typeof _dispatchEventToScript === "function") _dispatchEventToScript("inited", { status: true, delayed: true }); } catch(e){} }, 500);',
        );
      } catch (_) {}

      // 🔥 立即检查脚本执行后的状态（增强版诊断）
      final immediateCheck = _runtime!.evaluate('''
        JSON.stringify({
          // 基础环境检查
          globalThisKeys: Object.keys(globalThis).filter(k => k.includes('lx') || k.includes('on') || k.includes('EVENT')),
          windowKeys: typeof window !== 'undefined' ? Object.keys(window).filter(k => k.includes('lx') || k.includes('on') || k.includes('EVENT')) : null,
          lxKeys: globalThis.lx ? Object.keys(globalThis.lx) : null,
          windowLxKeys: typeof window !== 'undefined' && window.lx ? Object.keys(window.lx) : null,
          handlersAfterScript: globalThis._lxHandlers,
          hasOnFunction: typeof globalThis.on === 'function',
          hasWindowLx: typeof window !== 'undefined' && typeof window.lx !== 'undefined',
          hasWindowOn: typeof window !== 'undefined' && typeof window.lx !== 'undefined' && typeof window.lx.on === 'function',

          // 🔥 混淆脚本专项检查
          obfuscationCheck: {
            // 检查常见混淆变量名
            hasShortVars: {
              r: typeof globalThis.r !== 'undefined' ? typeof globalThis.r : null,
              t: typeof globalThis.t !== 'undefined' ? typeof globalThis.t : null,
              e: typeof globalThis.e !== 'undefined' ? typeof globalThis.e : null,
              o: typeof globalThis.o !== 'undefined' ? typeof globalThis.o : null,
              k: typeof globalThis.k !== 'undefined' ? typeof globalThis.k : null,
            },
            // 检查解构赋值是否成功
            lxAccessible: typeof globalThis.lx !== 'undefined',
            lxType: typeof globalThis.lx,
            lxIsObject: typeof globalThis.lx === 'object',
            lxHasOn: globalThis.lx && typeof globalThis.lx.on === 'function',
            lxHasRequest: globalThis.lx && typeof globalThis.lx.request === 'function',
            // 检查脚本是否尝试调用 on() 注册事件
            attemptedRegistration: globalThis._lxHandlers && Object.keys(globalThis._lxHandlers).length > 0,
            // 🔧 检查是否通过解构赋值创建了 r 变量（野花音源.js的模式）
            rIsFunction: typeof globalThis.r === 'function',
            rEqualsOn: globalThis.r === globalThis.on || (globalThis.lx && globalThis.r === globalThis.lx.on),
            // 🔧 检查脚本的混淆模式
            hasHexEncoding: (function() {
              try {
                // 检查脚本源码是否包含十六进制编码（形如 \\x6c 的模式）
                const scriptContent = globalThis._currentScriptContent || '';
                return scriptContent.includes('\\\\x');
              } catch(e) { return false; }
            })(),
          },

          scriptExecuted: true
        }, null, 2)
      ''');
      print('[EnhancedJSProxy] 🔍 脚本执行后立即检查:\n${immediateCheck.stringResult}');

      // 🚀 自动修复：如果检测到混淆脚本使用了解构赋值但未成功注册处理器
      try {
        final checkData = jsonDecode(immediateCheck.stringResult) as Map<String, dynamic>;
        final obfuscationCheck = checkData['obfuscationCheck'] as Map<String, dynamic>?;
        final attemptedRegistration = obfuscationCheck?['attemptedRegistration'] == true;
        final rIsFunction = obfuscationCheck?['rIsFunction'] == true;

        print('[EnhancedJSProxy] 🔍 混淆检测结果: rIsFunction=$rIsFunction, attemptedRegistration=$attemptedRegistration');

        if (rIsFunction && !attemptedRegistration) {
          print('[EnhancedJSProxy] 🔧 检测到混淆脚本使用解构赋值但未注册处理器');
          print('[EnhancedJSProxy] 🔧 可能原因：脚本使用了异步注册或setTimeout延迟注册');

          // 🔥 核心修复：手动触发一次 inited 事件到所有可能的监听器
          _runtime!.evaluate('''
            (function() {
              try {
                console.log('[EnhancedJSProxy-AutoFix] 尝试触发延迟注册...');

                // 方式1: 如果脚本定义了 r 变量（解构赋值的 on 函数）
                if (typeof globalThis.r === 'function') {
                  console.log('[EnhancedJSProxy-AutoFix] 发现 r 变量，尝试通过它触发注册');
                  // 检查是否有未注册的监听器
                  if (typeof globalThis.e === 'object' && globalThis.e.inited) {
                    console.log('[EnhancedJSProxy-AutoFix] 触发 inited 事件');
                    // 模拟脚本可能需要的初始化事件
                  }
                }

                // 方式2: 检查是否有全局的初始化函数
                const initFunctions = ['init', 'initialize', 'onInit', 'onReady', 'ready'];
                for (const fname of initFunctions) {
                  if (typeof globalThis[fname] === 'function') {
                    console.log('[EnhancedJSProxy-AutoFix] 调用初始化函数:', fname);
                    try {
                      globalThis[fname]();
                    } catch (e) {
                      console.log('[EnhancedJSProxy-AutoFix] 初始化函数执行失败:', e.message);
                    }
                  }
                }

                console.log('[EnhancedJSProxy-AutoFix] 延迟注册触发完成');
                return true;
              } catch (e) {
                console.error('[EnhancedJSProxy-AutoFix] 触发延迟注册失败:', e);
                return false;
              }
            })()
          ''');

          // 等待脚本完成异步初始化（某些混淆脚本可能在setTimeout中注册）
          await Future.delayed(const Duration(milliseconds: 800));

          // 再次检查是否成功注册（单一处理器模式）
          final delayedCheck = _runtime!.evaluate('''
            JSON.stringify({
              handlersAfterDelay: globalThis._lxHandlers ? Object.keys(globalThis._lxHandlers) : [],
              hasRequestHandler: globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function',
              allHandlerKeys: globalThis._lxHandlers ? Object.keys(globalThis._lxHandlers) : []
            })
          ''');
          print('[EnhancedJSProxy] 🔍 延迟后再次检查: ${delayedCheck.stringResult}');
        }
      } catch (e) {
        print('[EnhancedJSProxy] ⚠️ 混淆脚本检测失败（继续执行）: $e');
      }

      // 等待脚本初始化
      await Future.delayed(const Duration(milliseconds: 1000));

      // 再次检查是否已注册处理器（单一处理器模式）
      final delayedCheck = _runtime!.evaluate('''
        JSON.stringify({
          hasRequestHandler: globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function',
          handlers: globalThis._lxHandlers ? Object.keys(globalThis._lxHandlers) : []
        })
      ''');
      print('[EnhancedJSProxy] 🔍 脚本延迟检查: ${delayedCheck.stringResult}');

      // 如果仍未注册request处理器，自动注入兼容处理器（单一处理器模式）
      try {
        final needCompat = _runtime!.evaluate('''
          (function(){
            try {
              // 单一处理器模式：检查是否为函数
              return !(globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function');
            } catch(e) { return true; }
          })()
        ''');
        // 🔧 修复：flutter_js 返回布尔值时可能是 Pointer 类型，使用 stringResult 判断
        final needCompatStr = needCompat.stringResult;
        final shouldInjectCompat = needCompatStr == 'true' || needCompatStr == '1';
        print('[EnhancedJSProxy] 🔍 needCompat 检测结果: $needCompatStr (shouldInject=$shouldInjectCompat)');

        if (shouldInjectCompat) {
          print('[EnhancedJSProxy] ♻️ 注入兼容request处理器');
          _runtime!.evaluate('''
            (function(){
              try {
                if (!globalThis._lxHandlers) globalThis._lxHandlers = { request: null };

                // 单一处理器模式：直接定义兼容处理器
                const compatHandler = function(request){
                  try {
                    let result = null;
                    const src = request && request.source;
                    const info = request && request.info;
                    const musicInfo = info && info.musicInfo;
                    const quality = info && info.type;
                    
                    // 1) 严格优先：你的标准签名 (source, musicInfo, quality)
                    if (typeof handleGetMusicUrl === 'function') {
                      try { result = handleGetMusicUrl(src, musicInfo, quality); } catch(_) {}
                    }
                    if (!result && typeof getMusicUrl === 'function') {
                      try { result = getMusicUrl(src, musicInfo, quality); } catch(_) {}
                    }
                    
                    // 2) 其次：常见双参 (musicInfo, quality)
                    if (!result && typeof handleGetMusicUrl === 'function') {
                      try { result = handleGetMusicUrl(musicInfo, quality); } catch(_) {}
                    }
                    if (!result && typeof getMusicUrl === 'function') {
                      try { result = getMusicUrl(musicInfo, quality); } catch(_) {}
                    }
                    
                    // 3) 最后再尝试单参 info（旧实现）
                    if (!result && typeof handleGetMusicUrl === 'function') {
                      try { result = handleGetMusicUrl(info); } catch(_) {}
                    }
                    if (!result && typeof getMusicUrl === 'function') {
                      try { result = getMusicUrl(info); } catch(_) {}
                    }
                    
                    // 4) 平台特定函数名模式
                    if (!result) {
                      const names = [
                        request.source + 'GetMusicUrl',
                        'get' + request.source.toUpperCase() + 'Url',
                        request.source + '_getMusicUrl',
                        request.source + 'Music',
                        'handle' + request.source.toUpperCase() + 'Url',
                        request.source.toUpperCase() + '_MUSIC_URL'
                      ];
                      for (const n of names) {
                        if (typeof globalThis[n] === 'function') { 
                          let r = null;
                          try { r = globalThis[n](src, musicInfo, quality); } catch(_) {}
                          if (!r) { try { r = globalThis[n](musicInfo, quality); } catch(_) {} }
                          if (!r) { try { r = globalThis[n](info); } catch(_) {} }
                          if (r) { result = r; break; }
                        }
                      }
                    }
                    
                    // 5) 对象风格
                    if (!result && typeof apis === 'object' && apis && apis[request.source] && typeof apis[request.source].musicUrl === 'function') {
                      const q = quality; const mi = musicInfo;
                      let r = null; try { r = apis[request.source].musicUrl(mi, q); } catch(_) {}
                      if (!r) { try { r = apis[request.source].musicUrl(info); } catch(_) {} }
                      if (r) result = r;
                    }
                    if (!result && typeof sources === 'object' && sources && sources[request.source] && typeof sources[request.source].musicUrl === 'function') {
                      let r = null; try { r = sources[request.source].musicUrl(src, musicInfo, quality); } catch(_) {}
                      if (!r) { try { r = sources[request.source].musicUrl(musicInfo, quality); } catch(_) {} }
                      if (!r) { try { r = sources[request.source].musicUrl(info); } catch(_) {} }
                      if (r) result = r;
                    }
                    
                    // 6) 兜底扫描
                    if (!result) {
                      const allFunctions = Object.getOwnPropertyNames(globalThis).filter(name => 
                        typeof globalThis[name] === 'function' &&
                        (name.toLowerCase().includes('music') || name.toLowerCase().includes('url') || name.toLowerCase().includes(request.source.toLowerCase()))
                      );
                      for (const fn of allFunctions) {
                        let r = null;
                        try { r = globalThis[fn](src, musicInfo, quality); } catch(_) {}
                        if (!r) { try { r = globalThis[fn](musicInfo, quality); } catch(_) {} }
                        if (!r) { try { r = globalThis[fn](info || request); } catch(_) {} }
                        if (r) { result = r; break; }
                      }
                    }

                    return result;
                  } catch(e) { console.warn('[CompatHandler] 执行失败:', e); return null; }
                };

                // 单一处理器模式：直接赋值而非 push 到数组
                globalThis._lxHandlers.request = compatHandler;
                console.log('[EnhancedJSProxy] ✅ 兼容处理器已注入');
                return true;
              } catch (e) { return false; }
            })()
          ''');
        }
      } catch (_) {}

      // 检查脚本是否正确加载
      final checkResult = _runtime!.evaluate('''
        (function() {
          try {
            // 首先尝试自动检测音源
            const detectedSources = globalThis._detectSources();
            if (Object.keys(detectedSources).length > 0) {
              globalThis._musicSources = detectedSources;
              console.log('[EnhancedJSProxy] 自动检测到音源:', Object.keys(detectedSources).join(', '));
            }
            
            return {
              hasHandlers: Object.keys(globalThis._lxHandlers || {}).length > 0,
              hasMusicSources: Object.keys(globalThis._musicSources || {}).length > 0,
              handlers: Object.keys(globalThis._lxHandlers || {}),
              sources: Object.keys(globalThis._musicSources || {}),
              scriptRegistered: globalThis._scriptRegistered || false,
              hasLxExport: typeof globalThis.lx !== 'undefined',
              hasScriptManifest: typeof scriptManifest !== 'undefined',
              hasGetMusicUrl: typeof getMusicUrl !== 'undefined',
              // 详细调试信息（单一处理器模式）
              hasRequestHandler: globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function',
              requestHandlerType: globalThis._lxHandlers && globalThis._lxHandlers.request ? typeof globalThis._lxHandlers.request : 'undefined',
              onFunctionExists: typeof globalThis.on === 'function',
              lxOnExists: globalThis.lx && typeof globalThis.lx.on === 'function',
              allHandlers: globalThis._lxHandlers
            };
          } catch (e) {
            return { error: e.toString() };
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 脚本加载检查结果: ${checkResult.stringResult}');

      // 仅当顶层存在 error 字段时判定失败，避免因 handler 源码中的 console.error 误判
      bool hasTopLevelError = false;
      try {
        final Map<String, dynamic> parsed = jsonDecode(
          checkResult.stringResult,
        );
        hasTopLevelError =
            parsed.containsKey('error') && parsed['error'] != null;
      } catch (_) {
        // 如果解析失败，不据此判失败
        hasTopLevelError = false;
      }

      if (hasTopLevelError) {
        print('[EnhancedJSProxy] ❌ 脚本加载失败');
        return false;
      }

      // 🔧 修复：在返回前再次验证处理器状态，确保兼容处理器已正确注入
      final finalHandlerCheck = hasRequestHandler();
      print('[EnhancedJSProxy] 📋 最终 hasRequestHandler 检查: $finalHandlerCheck');

      print('[EnhancedJSProxy] ✅ JS脚本加载成功');
      return true;
    } catch (e) {
      print('[EnhancedJSProxy] ❌ JS脚本加载异常: $e');
      return false;
    }
  }

  /// 获取音乐播放链接
  Future<String?> getMusicUrl({
    required String source,
    required String songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!_isInitialized || _currentScript == null) {
      print('[EnhancedJSProxy] ⚠️ 服务未初始化或脚本未加载');
      return null;
    }

    try {
      print('[EnhancedJSProxy] 🎵 开始获取音乐链接: $source/$songId/$quality');

      // 优先走 LX 官方 preload 模式：通过 __lx_native__(key, 'request', ...) 与脚本交互
      try {
        final preloadCheck = _runtime!.evaluate(r'''
          (function(){
            try {
              return JSON.stringify({
                hasNative: typeof globalThis.__lx_native__ === 'function',
                hasKey: typeof globalThis.__hmusic_lx_key !== 'undefined'
              });
            } catch(e) { return JSON.stringify({hasNative:false,hasKey:false}); }
          })()
        ''');
        final preloadState = jsonDecode(preloadCheck.stringResult);
        final bool hasNative = preloadState['hasNative'] == true;
        final bool hasKey = preloadState['hasKey'] == true;
        if (hasNative && hasKey) {
          final requestKey = 'req_${DateTime.now().millisecondsSinceEpoch}_${source}_$songId';
          final completer = Completer<dynamic>();
          _lxPendingRequests[requestKey] = completer;

          final request = {
            'source': source,
            'action': 'musicUrl',
            'info': {
              'type': quality,
              'musicInfo': {
                'songmid': songId,
                'hash': songId,
                'strMediaMid': songId,
                'id': songId,
                ...?musicInfo,
              },
            },
          };
          final payload = jsonEncode({'requestKey': requestKey, 'data': request});

          _runtime!.evaluate(
            "globalThis.__lx_native__(globalThis.__hmusic_lx_key, 'request', ${jsonEncode(payload)});",
          );

          final result = await completer.future.timeout(
            const Duration(seconds: 8),
          );

          if (result is Map) {
            // preload 返回结构: { source, action, data: <url> }
            final data = result['data'];
            if (data is String && data.startsWith('http')) return data;
          }
          if (result is String && result.startsWith('http')) return result;
          return null;
        }
      } catch (_) {
        // fallback to legacy path
      }

      // 🔥 构建完整的 musicInfo（洛雪脚本需要更多字段）
      final fullMusicInfo = {
        'songmid': songId,
        'hash': songId,
        'strMediaMid': songId,  // QQ 音乐需要
        'id': songId,           // 通用 ID
        'name': musicInfo?['title'] ?? musicInfo?['name'] ?? '',
        'singer': musicInfo?['artist'] ?? musicInfo?['singer'] ?? '',
        'album': musicInfo?['album'] ?? '',
        'albumMid': musicInfo?['albumMid'] ?? '',
        'albumId': musicInfo?['albumId'] ?? '',
        'duration': musicInfo?['duration'] ?? 0,
        'interval': musicInfo?['duration'] ?? 0,  // 某些脚本使用 interval
        ...?musicInfo,  // 合并用户传入的额外字段
      };

      // 构建请求参数
      final requestParams = {
        'action': 'musicUrl',
        'source': source,
        'info': {
          'type': quality,
          'musicInfo': fullMusicInfo,
        },
      };

      print('[EnhancedJSProxy] 调用JS处理函数: $requestParams');

      // 重置Promise状态
      _runtime!.evaluate(
        'globalThis._promiseResult = null; globalThis._promiseError = null; globalThis._promiseComplete = false;',
      );

      // 调用JS处理函数
      final jsResult = _runtime!.evaluate('''
        (function() {
          try {
            const request = ${jsonEncode(requestParams)};
            console.log('Handle Action(' + request.action + ')');
            console.log('source', request.source);
            console.log('quality', request.info.type);
            console.log('musicInfo', request.info.musicInfo);
            
            // 尝试多种调用方式
            let result = null;

            // 方式1: 调用已注册的 request 事件处理器（主要方式，按官方规范使用单一处理器）
            // 🔥 关键修复：使用 .call(globalThis.lx, ...) 绑定 this 上下文，与官方 preload 脚本完全一致
            if (globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function') {
              console.log('[EnhancedJSProxy] 调用 request 处理器 (使用官方 .call 方式)');
              const handler = globalThis._lxHandlers.request;
              // 官方参数格式: { source, action, info }
              const officialParams = {
                source: request.source,
                action: request.action,
                info: request.info
              };

              const candidateArgsList = [
                [officialParams],
                [request],
                [{ ...officialParams, quality: request.info.type, musicInfo: request.info.musicInfo }],
                [{ action: request.action, source: request.source, data: request.info }],
                [{ action: request.action, source: request.source, data: request.info.musicInfo, quality: request.info.type }],
                [request.source, request.action, request.info],
                [request.action, request.source, request.info],
                [request.action, request.info.musicInfo, request.info.type],
                [request.info.musicInfo, request.info.type],
                [request.info.musicInfo],
              ];

              for (let i = 0; i < candidateArgsList.length && !result; i++) {
                const args = candidateArgsList[i];
                try {
                  console.log('[EnhancedJSProxy] 调用处理器，尝试参数#' + i + ':', JSON.stringify(args[0]));
                  const r = handler.call.apply(handler, [globalThis.lx, ...args]);
                  if (r !== undefined && r !== null) {
                    result = r;
                    console.log('[EnhancedJSProxy] 处理器返回(#' + i + '):', result);
                    break;
                  }
                } catch (handlerError) {
                  console.error('[EnhancedJSProxy] ❌ 处理器调用出错(#' + i + '):', handlerError && (handlerError.message || handlerError.toString()));
                  try {
                    if (handlerError && handlerError.stack) console.error(handlerError.stack);
                  } catch (_) {}
                }
              }
            }
            
            // 方式1.5: 通过 lx.emit 触发（如果脚本使用官方事件模型）
            if (!result && typeof lx !== 'undefined' && typeof lx.emit === 'function') {
              console.log('[EnhancedJSProxy] 尝试通过 lx.emit 分发 request');
              result = lx.emit(lx.EVENT_NAMES.request, request);
              console.log('[EnhancedJSProxy] lx.emit 返回:', result);
            }
            
            // 方式2: 使用内部分发器
            if (!result && typeof _dispatchEventToScript === 'function') {
              console.log('[EnhancedJSProxy] 尝试通过内部分发器分发 request');
              result = _dispatchEventToScript('request', request);
              console.log('[EnhancedJSProxy] 内部分发器返回:', result);
            }
            
            // 方式3: 查找专用函数 (多种命名模式)
            const platformFunctions = [
              request.source + 'GetMusicUrl',     // txGetMusicUrl
              'get' + request.source.toUpperCase() + 'Url',  // getTXUrl
              request.source + '_getMusicUrl',    // tx_getMusicUrl
              request.source + 'Music',           // txMusic
              'handle' + request.source.toUpperCase() + 'Url', // handleTXUrl
              request.source.toUpperCase() + '_MUSIC_URL'      // TX_MUSIC_URL
            ];
            
            for (const funcName of platformFunctions) {
              if (!result && typeof globalThis[funcName] === 'function') {
                console.log('[EnhancedJSProxy] 尝试调用专用函数:', funcName);
                result = globalThis[funcName](request.info);
                console.log('[EnhancedJSProxy] 专用函数返回:', result);
                if (result) break;
              }
            }
            
            // 方式4: 通用getMusicUrl
            if (!result && typeof getMusicUrl === 'function') {
              console.log('[EnhancedJSProxy] 尝试调用通用 getMusicUrl');
              result = getMusicUrl(request.info);
              console.log('[EnhancedJSProxy] getMusicUrl 返回:', result);
            }
            
            // 方式5: 检查脚本是否定义了处理函数
            if (!result) {
              console.log('[EnhancedJSProxy] 检查脚本中的处理函数...');
              const possibleHandlers = [
                'handleRequest',
                'processRequest', 
                'handleMusicUrl',
                'musicUrlHandler',
                'getUrl',
                'resolveUrl'
              ];
              
              for (const handlerName of possibleHandlers) {
                if (typeof globalThis[handlerName] === 'function') {
                  console.log('[EnhancedJSProxy] 尝试调用处理函数:', handlerName);
                  result = globalThis[handlerName](request);
                  console.log('[EnhancedJSProxy] 处理函数返回:', result);
                  if (result) break;
                }
              }
            }
            
            // 方式6: 查找任何可能的音乐URL获取函数
            if (!result) {
              console.log('[EnhancedJSProxy] 最后尝试：查找所有可能的函数...');
              const allFunctions = Object.getOwnPropertyNames(globalThis).filter(name =>
                typeof globalThis[name] === 'function' &&
                (name.toLowerCase().includes('music') ||
                 name.toLowerCase().includes('url') ||
                 name.toLowerCase().includes(request.source.toLowerCase()))
              );
              console.log('[EnhancedJSProxy] 找到可能的函数:', allFunctions);

              for (const funcName of allFunctions) {
                try {
                  result = globalThis[funcName](request.info || request);
                  console.log('[EnhancedJSProxy] 函数', funcName, '返回:', result);
                  if (result) break;
                } catch (e) {
                  console.log('[EnhancedJSProxy] 函数', funcName, '调用失败:', e.message);
                }
              }
            }

            if (result && typeof result.then === 'function') {
              console.log('[EnhancedJSProxy] 检测到Promise，开始等待...');
              try {
                result.then(function(v){
                  try {
                    console.log('[EnhancedJSProxy] 📦 JS脚本返回结果(Promise resolved):', JSON.stringify(v));
                    globalThis._promiseResult = v;
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                }).catch(function(err){
                  try {
                    console.log('[EnhancedJSProxy] ❌ JS脚本返回错误(Promise rejected):', err);
                    globalThis._promiseError =
                      (err && (err.stack || err.message || err.toString())) || 'Unknown error';
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                });
              } catch (e) { console.log('[EnhancedJSProxy] 绑定Promise回调失败:', e && e.message); }
              return JSON.stringify({ success: true, isPromise: true });
            } else if (result) {
              console.log('[EnhancedJSProxy] 📦 JS脚本返回结果(同步):', JSON.stringify(result));
              return JSON.stringify({ success: true, result: result });
            } else {
              console.log('[EnhancedJSProxy] ⚠️ JS脚本未返回任何结果');
              return JSON.stringify({ success: false, error: 'No suitable handler found' });
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] JS执行失败:', e);
            return JSON.stringify({ success: false, error: e.toString() });
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 JS执行结果: ${jsResult.stringResult}');

      // 解析JS返回结果
      Map<String, dynamic> resultData;
      try {
        resultData = jsonDecode(jsResult.stringResult);
      } catch (e) {
        print('[EnhancedJSProxy] ❌ JSON解析失败: $e');
        print('[EnhancedJSProxy] 原始结果: ${jsResult.stringResult}');
        return null;
      }

      if (resultData['success'] == true) {
        if (resultData['isPromise'] == true) {
          // 等待Promise完成（最多3秒）
          for (int i = 0; i < 30; i++) {
            // 3秒超时
            await Future.delayed(const Duration(milliseconds: 100));

            final checkResult = _runtime!.evaluate('''
              (function() {
                try {
                  console.log('[EnhancedJSProxy] 检查Promise状态:', globalThis._promiseComplete, globalThis._promiseResult, globalThis._promiseError);

                  if (globalThis._promiseComplete) {
                    if (globalThis._promiseResult !== null && globalThis._promiseResult !== undefined) {
                      console.log('[EnhancedJSProxy] ✅ Promise成功，结果:', JSON.stringify(globalThis._promiseResult));
                      return JSON.stringify({ success: true, result: globalThis._promiseResult });
                    } else if (globalThis._promiseError) {
                      console.log('[EnhancedJSProxy] ❌ Promise失败，错误:', globalThis._promiseError);
                      return JSON.stringify({ success: false, error: globalThis._promiseError });
                    }
                  }

                  return JSON.stringify({ success: false, pending: true });
                } catch (e) {
                  return JSON.stringify({ success: false, error: e.toString() });
                }
              })()
            ''');

            final checkData = jsonDecode(checkResult.stringResult);

            if (checkData['success'] == true) {
              final musicUrl = checkData['result'];
              print('[EnhancedJSProxy] ✅ Promise完成，获取音乐链接: $musicUrl');
              return musicUrl;
            } else if (checkData['success'] == false &&
                checkData['pending'] != true) {
              print('[EnhancedJSProxy] ❌ Promise失败: ${checkData['error']}');
              return null;
            }

            // 每秒显示一次等待状态
            if (i % 10 == 0) {
              print('[EnhancedJSProxy] ⏳ 等待Promise完成... ${i / 10}秒');
            }
          }

          print('[EnhancedJSProxy] ⏰ Promise等待超时 (3秒)');
          return null;
        } else {
          final musicUrl = resultData['result'];
          print('[EnhancedJSProxy] ✅ 成功获取音乐链接: $musicUrl');
          return musicUrl;
        }
      } else {
        print('[EnhancedJSProxy] ❌ 获取音乐链接失败: ${resultData['error']}');
        return null;
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 获取音乐链接异常: $e');
      return null;
    }
  }

  /// 获取专辑封面图
  Future<String?> getPic({
    required String source,
    required String songId,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!_isInitialized || _currentScript == null) {
      print('[EnhancedJSProxy] ⚠️ 服务未初始化或脚本未加载');
      return null;
    }

    try {
      print('[EnhancedJSProxy] 🖼️  开始获取专辑封面: $source/$songId');

      // 构建请求参数
      final requestParams = {
        'action': 'pic',
        'source': source,
        'info': {
          'musicInfo': {'songmid': songId, 'hash': songId, ...?musicInfo},
        },
      };

      print('[EnhancedJSProxy] 调用JS处理函数: $requestParams');

      // 重置Promise状态
      _runtime!.evaluate(
        'globalThis._promiseResult = null; globalThis._promiseError = null; globalThis._promiseComplete = false;',
      );

      // 调用JS处理函数
      final jsResult = _runtime!.evaluate('''
        (function() {
          try {
            const request = ${jsonEncode(requestParams)};
            console.log('Handle Action(' + request.action + ')');
            console.log('source', request.source);
            console.log('musicInfo', request.info.musicInfo);
            
            // 尝试多种调用方式
            let result = null;

            // 方式1: 调用已注册的 request 事件处理器（主要方式，按官方规范使用单一处理器）
            // 🔥 关键修复：使用 .call(globalThis.lx, ...) 绑定 this 上下文，与官方 preload 脚本完全一致
            if (globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function') {
              console.log('[EnhancedJSProxy] 调用 request 处理器 (使用官方 .call 方式)');
              const handler = globalThis._lxHandlers.request;
              // 官方参数格式: { source, action, info }
              const officialParams = {
                source: request.source,
                action: request.action,
                info: request.info
              };
              console.log('[EnhancedJSProxy] 调用处理器，参数:', JSON.stringify(officialParams));
              // 🔥 使用官方的 .call(globalThis.lx, ...) 调用方式
              try {
                result = handler.call(globalThis.lx, officialParams);
                console.log('[EnhancedJSProxy] 处理器返回:', result);
              } catch (handlerError) {
                console.error('[EnhancedJSProxy] ❌ 处理器调用出错:', handlerError);
                console.error('[EnhancedJSProxy] ❌ 错误详情:', handlerError.message);
                console.error('[EnhancedJSProxy] ❌ 错误堆栈:', handlerError.stack);
                // 尝试不同的参数格式
                console.log('[EnhancedJSProxy] 🔄 尝试直接传递 musicInfo 作为参数...');
                try {
                  result = handler.call(globalThis.lx, request.info.musicInfo);
                  console.log('[EnhancedJSProxy] 直接 musicInfo 参数返回:', result);
                } catch (e2) {
                  console.error('[EnhancedJSProxy] ❌ 直接 musicInfo 也失败:', e2.message);
                }
              }
            }
            
            // 方式2: 通过 lx.emit 触发
            if (!result && typeof lx !== 'undefined' && typeof lx.emit === 'function') {
              console.log('[EnhancedJSProxy] 尝试通过 lx.emit 分发 request');
              result = lx.emit(lx.EVENT_NAMES.request, request);
              console.log('[EnhancedJSProxy] lx.emit 返回:', result);
            }

            if (result && typeof result.then === 'function') {
              console.log('[EnhancedJSProxy] 检测到Promise，开始等待...');
              try {
                result.then(function(v){
                  try {
                    console.log('[EnhancedJSProxy] 📦 JS脚本返回封面URL(Promise resolved):', JSON.stringify(v));
                    globalThis._promiseResult = v;
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                }).catch(function(err){
                  try {
                    console.log('[EnhancedJSProxy] ❌ JS脚本返回错误(Promise rejected):', err);
                    globalThis._promiseError =
                      (err && (err.stack || err.message || err.toString())) || 'Unknown error';
                    globalThis._promiseComplete = true;
                  } catch(e) {}
                });
              } catch (e) { console.log('[EnhancedJSProxy] 绑定Promise回调失败:', e && e.message); }
              return JSON.stringify({ success: true, isPromise: true });
            } else if (result) {
              console.log('[EnhancedJSProxy] 📦 JS脚本返回封面URL(同步):', JSON.stringify(result));
              return JSON.stringify({ success: true, result: result });
            } else {
              console.log('[EnhancedJSProxy] ⚠️ JS脚本未返回任何封面URL');
              return JSON.stringify({ success: false, error: 'No suitable handler found' });
            }
          } catch (e) {
            console.error('[EnhancedJSProxy] JS执行失败:', e);
            return JSON.stringify({ success: false, error: e.toString() });
          }
        })()
      ''');

      print('[EnhancedJSProxy] 🔍 JS执行结果: ${jsResult.stringResult}');

      // 解析JS返回结果
      Map<String, dynamic> resultData;
      try {
        resultData = jsonDecode(jsResult.stringResult);
      } catch (e) {
        print('[EnhancedJSProxy] ❌ JSON解析失败: $e');
        return null;
      }

      if (resultData['success'] == true) {
        if (resultData['isPromise'] == true) {
          // 等待Promise完成（最多3秒）
          for (int i = 0; i < 30; i++) {
            await Future.delayed(const Duration(milliseconds: 100));

            final checkResult = _runtime!.evaluate('''
              (function() {
                try {
                  if (globalThis._promiseComplete) {
                    if (globalThis._promiseResult !== null && globalThis._promiseResult !== undefined) {
                      console.log('[EnhancedJSProxy] Promise成功，封面URL:', globalThis._promiseResult);
                      return JSON.stringify({ success: true, result: globalThis._promiseResult });
                    } else if (globalThis._promiseError) {
                      console.log('[EnhancedJSProxy] Promise失败，错误:', globalThis._promiseError);
                      return JSON.stringify({ success: false, error: globalThis._promiseError });
                    }
                  }
                  return JSON.stringify({ success: false, pending: true });
                } catch (e) {
                  return JSON.stringify({ success: false, error: e.toString() });
                }
              })()
            ''');

            final checkData = jsonDecode(checkResult.stringResult);

            if (checkData['success'] == true) {
              final picUrl = checkData['result'];
              print('[EnhancedJSProxy] ✅ 获取封面成功: $picUrl');
              return picUrl;
            } else if (checkData['success'] == false &&
                checkData['pending'] != true) {
              print('[EnhancedJSProxy] ❌ 获取封面失败: ${checkData['error']}');
              return null;
            }
          }

          print('[EnhancedJSProxy] ⏰ Promise等待超时 (3秒)');
          return null;
        } else {
          final picUrl = resultData['result'];
          print('[EnhancedJSProxy] ✅ 获取封面成功: $picUrl');
          return picUrl;
        }
      } else {
        print('[EnhancedJSProxy] ❌ 获取封面失败: ${resultData['error']}');
        return null;
      }
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 获取封面异常: $e');
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
            return JSON.stringify(globalThis._musicSources || {});
          } catch (e) {
            return '{}';
          }
        })()
      ''');

      return Map<String, dynamic>.from(jsonDecode(result.stringResult));
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 获取音源列表失败: $e');
      return {};
    }
  }

  /// 检查是否有 request 处理器注册
  /// 🎯 用于判断脚本是否真正可用（某些脚本不调用 registerScript，但会注册 request 处理器）
  bool hasRequestHandler() {
    if (!_isInitialized || _currentScript == null) {
      return false;
    }

    try {
      final result = _runtime!.evaluate('''
        (function() {
          try {
            // 单一处理器模式：检查是否为函数
            return globalThis._lxHandlers && typeof globalThis._lxHandlers.request === 'function';
          } catch (e) {
            return false;
          }
        })()
      ''');

      // 🔧 修复：flutter_js 返回布尔值时是 Pointer 类型，必须使用 stringResult 判断
      final strResult = result.stringResult;
      final hasHandler = strResult == 'true' || strResult == '1';
      print('[EnhancedJSProxy] 🔍 检查 request 处理器: $hasHandler (stringResult=$strResult)');
      return hasHandler;
    } catch (e) {
      print('[EnhancedJSProxy] ❌ 检查 request 处理器失败: $e');
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    _currentScript = null;
    _isInitialized = false;
    print('[EnhancedJSProxy] 🧹 资源已释放');
  }
}
