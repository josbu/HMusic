import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum LogExportLevel {
  essential('精简'),
  standard('标准'),
  full('完整');

  const LogExportLevel(this.displayName);
  final String displayName;
}

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int _maxBytes = 2 * 1024 * 1024; // 2MB
  static const String _logDirName = 'logs';
  static const String _logFileName = 'app.log';
  static const String _logFileBackupName = 'app.log.1';
  static const String _sessionContextFileName = 'session_context.json';

  Directory? _logDir;
  File? _logFile;
  Future<void> _writeQueue = Future.value();

  static Future<void> init() => instance._init();

  Future<void> _init() async {
    final baseDir = await getApplicationDocumentsDirectory();
    _logDir = Directory('${baseDir.path}/$_logDirName');
    if (!await _logDir!.exists()) {
      await _logDir!.create(recursive: true);
    }
    _logFile = File('${_logDir!.path}/$_logFileName');
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
  }

  Future<List<File>> getLogFiles() async {
    if (_logDir == null) return [];
    final main = File('${_logDir!.path}/$_logFileName');
    final backup = File('${_logDir!.path}/$_logFileBackupName');
    final files = <File>[];
    if (await main.exists()) files.add(main);
    if (await backup.exists()) files.add(backup);
    return files;
  }

  Future<void> saveSessionContext(Map<String, dynamic> context) async {
    if (_logDir == null) {
      await _init();
    }
    final file = File('${_logDir!.path}/$_sessionContextFileName');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(context),
      flush: true,
    );
  }

  /// 生成用于分享的精简日志文件（只保留最近的日志尾部）
  Future<File?> buildShareableLogFile({
    LogExportLevel level = LogExportLevel.standard,
  }) async {
    if (_logDir == null) {
      await _init();
    }

    final maxBytesPerFile = switch (level) {
      LogExportLevel.essential => 120 * 1024,
      LogExportLevel.standard => 220 * 1024,
      LogExportLevel.full => 700 * 1024,
    };

    final files = await getLogFiles();
    if (files.isEmpty) {
      return null;
    }

    final sections = <String>[];
    for (final file in files) {
      final tail = await _readTailAsString(file, maxBytesPerFile);
      if (tail.trim().isEmpty) {
        continue;
      }
      final filtered = _filterForExport(tail, level);
      if (filtered.trim().isEmpty) {
        continue;
      }
      final fileName =
          file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : file.path;
      sections.add(
        '===== $fileName (${level.displayName}, tail ${maxBytesPerFile}B) =====\n$filtered',
      );
    }

    if (sections.isEmpty) {
      return null;
    }

    final tmpDir = await getTemporaryDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final output = File('${tmpDir.path}/hmusic_logs_$ts.txt');
    final content =
        StringBuffer()
          ..writeln('HMusic Log Export')
          ..writeln('generated_at=${DateTime.now().toIso8601String()}')
          ..writeln('level=${level.displayName}')
          ..writeln('files=${files.length}')
          ..writeln()
          ..writeln(await _buildSessionContextSection())
          ..writeln()
          ..writeln(sections.join('\n\n'));

    await output.writeAsString(content.toString(), flush: true);
    return output;
  }

  Future<String> _buildSessionContextSection() async {
    if (_logDir == null) {
      return '===== session_context =====\n<unavailable>';
    }
    final file = File('${_logDir!.path}/$_sessionContextFileName');
    if (!await file.exists()) {
      return '===== session_context =====\n<missing>';
    }
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) {
        return '===== session_context =====\n<empty>';
      }
      return '===== session_context =====\n$text';
    } catch (e) {
      return '===== session_context =====\n<read_failed: $e>';
    }
  }

  String _filterForExport(String input, LogExportLevel level) {
    final lines = const LineSplitter().convert(input);
    final deduped = _dedupeRepeatedHeartbeat(lines);

    final filtered = switch (level) {
      LogExportLevel.full => deduped.where((line) => !_isToolNoiseLine(line)),
      LogExportLevel.standard => deduped.where(
        (line) => !_isToolNoiseLine(line) && !_isLowValueNoiseLine(line),
      ),
      LogExportLevel.essential => deduped.where(_isEssentialLine),
    };

    return filtered.join('\n');
  }

  List<String> _dedupeRepeatedHeartbeat(List<String> lines) {
    const marker = '[ProxyServer] 健康检查通过 - 统计: 0次请求, 0次成功, 0次失败';
    int heartbeatSkipped = 0;
    final result = <String>[];
    for (final line in lines) {
      if (line.contains(marker)) {
        heartbeatSkipped += 1;
        continue;
      }
      result.add(line);
    }
    if (heartbeatSkipped > 0) {
      result.add('[HEARTBEAT] 已省略重复健康检查日志: $heartbeatSkipped 行');
    }
    return result;
  }

  bool _isToolNoiseLine(String line) {
    return line.contains('Checking for available port on') ||
        line.contains('WFIsolatedShortcutRunner') ||
        line.contains('Indexing for request:') ||
        line.contains('Resolved Preferred localizations:') ||
        line.contains('Inserted en/languageModel') ||
        line.contains('Sandbox extensions') ||
        line.contains('Finished in ') ||
        line.contains('Indexed: ') ||
        line.contains('Errored: ') ||
        line.contains('_dartVmService._tcp.local') ||
        line.contains('ext.flutter.') ||
        line.contains('[{"id":');
  }

  bool _isLowValueNoiseLine(String line) {
    return line.contains('⏳ 等待初始化完成') ||
        line.contains('🎨 build - _updateChecked') ||
        line.contains('playerState: playing=') ||
        line.contains('buffered: ') ||
        line.contains('speed: ') ||
        line.contains('processingState: ') ||
        line.contains('position: 0ms');
  }

  bool _isEssentialLine(String line) {
    if (_isToolNoiseLine(line)) {
      return false;
    }
    const criticalKeywords = [
      '❌',
      '失败',
      '异常',
      'error',
      'Error',
      '⚠️',
      '登录响应: code=',
      '自动加载结果',
      '脚本加载',
      'request 处理器',
      '初始化完成',
      'Session',
      'session_context_',
    ];
    for (final keyword in criticalKeywords) {
      if (line.contains(keyword)) {
        return true;
      }
    }

    // 保留关键路径上的简要状态，便于复盘流程
    const importantTags = [
      '[MiIoT]',
      '[DirectMode]',
      '[AuthProvider]',
      '[Initialization]',
      '[JSProxyProvider]',
      '[EnhancedJSProxy]',
      '[SourceSettings]',
      '[JsScriptManager]',
      '[PlaybackProvider]',
      '[ProxyServer]',
      '[Session]',
    ];
    for (final tag in importantTags) {
      if (line.contains(tag)) {
        return true;
      }
    }
    return false;
  }

  void d(String message, {String? tag}) => _log('D', message, tag: tag);
  void i(String message, {String? tag}) => _log('I', message, tag: tag);
  void w(String message, {String? tag}) => _log('W', message, tag: tag);
  void e(String message, {Object? error, StackTrace? stack, String? tag}) {
    final err = error != null ? ' error=$error' : '';
    final st = stack != null ? '\n$stack' : '';
    _log('E', '$message$err$st', tag: tag);
  }

  void _log(String level, String message, {String? tag}) {
    final ts = DateTime.now().toIso8601String();
    final tagText = tag == null ? '' : '[$tag] ';
    final line = _sanitize('[$ts][$level] $tagText$message');
    _enqueueWrite(line);
  }

  void _enqueueWrite(String line) {
    _writeQueue = _writeQueue.then((_) async {
      if (_logFile == null) return;
      await _rotateIfNeeded(_logFile!);
      await _logFile!.writeAsString(
        '$line\n',
        mode: FileMode.append,
        flush: false,
      );
    });
  }

  Future<void> _rotateIfNeeded(File file) async {
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      if (length <= _maxBytes) return;
      final backup = File('${_logDir!.path}/$_logFileBackupName');
      if (await backup.exists()) {
        await backup.delete();
      }
      await file.rename(backup.path);
      await file.create(recursive: true);
    } catch (_) {}
  }

  Future<String> _readTailAsString(File file, int maxBytes) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final length = await raf.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(start);
      final bytes = await raf.read(length - start);
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    } finally {
      await raf?.close();
    }
  }

  String _sanitize(String input) {
    var out = input;
    // Mask tokens
    final tokenPatterns = [
      RegExp(r'(passToken\s*[:=]\s*)([^,\s]+)', caseSensitive: false),
      RegExp(r'(serviceToken\s*[:=]\s*)([^,\s]+)', caseSensitive: false),
      RegExp(r'(ssecurity\s*[:=]\s*)([^,\s]+)', caseSensitive: false),
      RegExp(r'(passToken=)([^;\s]+)', caseSensitive: false),
      RegExp(r'(serviceToken=)([^;\s]+)', caseSensitive: false),
      RegExp(r'(ssecurity=)([^;\s]+)', caseSensitive: false),
      RegExp(r'V1:[A-Za-z0-9+/=]+'),
    ];
    for (final pattern in tokenPatterns) {
      out = out.replaceAllMapped(pattern, (m) {
        if (m.groupCount >= 2) {
          return '${m.group(1)}***';
        }
        return 'V1:***';
      });
    }
    // Mask phone numbers (China mobile 11 digits)
    out = out.replaceAllMapped(RegExp(r'\b1\d{10}\b'), (m) {
      final s = m.group(0)!;
      return '${s.substring(0, 3)}****${s.substring(7)}';
    });
    return out;
  }
}
