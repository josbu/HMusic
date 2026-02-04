import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int _maxBytes = 2 * 1024 * 1024; // 2MB
  static const String _logDirName = 'logs';
  static const String _logFileName = 'app.log';
  static const String _logFileBackupName = 'app.log.1';

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
      await _logFile!.writeAsString('$line\n', mode: FileMode.append, flush: false);
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

  String _sanitize(String input) {
    var out = input;
    // Mask tokens
    final tokenPatterns = [
      RegExp(r'(passToken\\s*[:=]\\s*)([^,\\s]+)', caseSensitive: false),
      RegExp(r'(serviceToken\\s*[:=]\\s*)([^,\\s]+)', caseSensitive: false),
      RegExp(r'(ssecurity\\s*[:=]\\s*)([^,\\s]+)', caseSensitive: false),
      RegExp(r'(passToken=)([^;\\s]+)', caseSensitive: false),
      RegExp(r'(serviceToken=)([^;\\s]+)', caseSensitive: false),
      RegExp(r'(ssecurity=)([^;\\s]+)', caseSensitive: false),
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
    out = out.replaceAllMapped(RegExp(r'\\b1\\d{10}\\b'), (m) {
      final s = m.group(0)!;
      return '${s.substring(0, 3)}****${s.substring(7)}';
    });
    return out;
  }
}
