import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/js_script.dart';

class JsScriptManager extends StateNotifier<List<JsScript>> {
  static const _kScriptList = 'js_script_list';
  static const _kSelectedScriptId = 'selected_script_id';
  static const _kScriptStorageDir = 'js_scripts';

  String? _selectedScriptId;
  String? get selectedScriptId => _selectedScriptId;
  JsScript? get selectedScript =>
      state.isNotEmpty && _selectedScriptId != null
          ? state.firstWhere(
            (s) => s.id == _selectedScriptId,
            orElse: () => state.first,
          )
          : null;

  JsScriptManager() : super([]) {
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scriptsJson = prefs.getString(_kScriptList);
      final selectedId = prefs.getString(_kSelectedScriptId);

      List<JsScript> scripts = [];

      // 公开版本不包含内置脚本，用户需要自行导入JS脚本

      // 加载用户导入的脚本
      if (scriptsJson != null && scriptsJson.isNotEmpty) {
        final List<dynamic> scriptsList = jsonDecode(scriptsJson);
        for (final scriptMap in scriptsList) {
          try {
            scripts.add(JsScript.fromMap(scriptMap as Map<String, dynamic>));
          } catch (e) {
            print('[XMC] ⚠️ [JsScriptManager] 跳过无效脚本: $e');
          }
        }
      }

      final migration = await _migrateLocalScriptsIfNeeded(scripts, prefs);
      scripts = migration.scripts;
      state = scripts;

      // 公开版本：清理遗留的内置脚本选择
      if (selectedId == 'builtin_xiaoqiu') {
        print('[XMC] 🧹 [JsScriptManager] 检测到遗留的内置脚本选择，自动清理');
        _selectedScriptId = scripts.isNotEmpty ? scripts.first.id : null;
        await _saveScripts(); // 保存清理后的状态
      } else {
        _selectedScriptId =
            selectedId ?? (scripts.isNotEmpty ? scripts.first.id : null);
        if (migration.changed) {
          await _saveScripts();
        }
      }

      print(
        '[XMC] 📚 [JsScriptManager] 加载了 ${scripts.length} 个脚本，当前选中: $_selectedScriptId',
      );
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 加载脚本失败: $e');
      state = [];
    }
  }

  Future<void> _saveScripts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 只保存非内置脚本
      final userScripts = state.where((s) => !s.isBuiltIn).toList();
      final scriptsJson = jsonEncode(
        userScripts.map((s) => s.toMap()).toList(),
      );

      await prefs.setString(_kScriptList, scriptsJson);
      if (_selectedScriptId != null) {
        await prefs.setString(_kSelectedScriptId, _selectedScriptId!);
      }

      print('[XMC] 💾 [JsScriptManager] 已保存 ${userScripts.length} 个用户脚本');
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 保存脚本失败: $e');
    }
  }

  Future<Directory> _getScriptStorageDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final scriptDir = Directory(p.join(appSupportDir.path, _kScriptStorageDir));
    if (!await scriptDir.exists()) {
      await scriptDir.create(recursive: true);
    }
    return scriptDir;
  }

  String _sanitizeFileName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      return 'script';
    }
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<String> _persistLocalScriptContent({
    required String content,
    required String scriptId,
    required String scriptName,
  }) async {
    final scriptDir = await _getScriptStorageDirectory();
    final safeName = _sanitizeFileName(scriptName);
    final targetPath = p.join(scriptDir.path, '${scriptId}_$safeName.js');

    final file = File(targetPath);
    await file.writeAsString(content, flush: true);
    return targetPath;
  }

  String _buildScriptCacheKey(JsScript script) {
    return 'js_cached_content_${script.id}';
  }

  bool _isLikelyTempPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/tmp/') || normalized.contains('/cache/');
  }

  bool _isPathUnderDirectory(String filePath, String dirPath) {
    final normalizedFile = p.normalize(filePath);
    final normalizedDir = p.normalize(dirPath);
    return p.isWithin(normalizedDir, normalizedFile) ||
        normalizedFile == normalizedDir;
  }

  Future<({List<JsScript> scripts, bool changed})> _migrateLocalScriptsIfNeeded(
    List<JsScript> scripts,
    SharedPreferences prefs,
  ) async {
    if (scripts.every((s) => s.source != JsScriptSource.localFile)) {
      return (scripts: scripts, changed: false);
    }

    bool changed = false;
    final migrated = <JsScript>[];
    final scriptDir = await _getScriptStorageDirectory();

    for (final script in scripts) {
      if (script.source != JsScriptSource.localFile) {
        migrated.add(script);
        continue;
      }

      final currentPath = script.content.trim();
      final file = File(currentPath);
      final exists = currentPath.isNotEmpty && await file.exists();
      final alreadyManaged =
          currentPath.isNotEmpty &&
          _isPathUnderDirectory(currentPath, scriptDir.path);

      if (exists && alreadyManaged) {
        migrated.add(script);
        continue;
      }

      String? content;
      if (exists) {
        content = await file.readAsString();
      } else {
        final cached = prefs.getString(_buildScriptCacheKey(script));
        if (cached != null && cached.trim().isNotEmpty) {
          content = cached;
          print('[XMC] 🔁 [JsScriptManager] 使用缓存恢复本地脚本: ${script.name}');
        }
      }

      if (content == null || content.trim().isEmpty) {
        migrated.add(script);
        if (!exists) {
          print(
            '[XMC] ⚠️ [JsScriptManager] 本地脚本路径失效且无可恢复缓存: ${script.name} -> $currentPath',
          );
        }
        continue;
      }

      final persistedPath = await _persistLocalScriptContent(
        content: content,
        scriptId: script.id,
        scriptName: script.name,
      );
      if (persistedPath != currentPath) {
        changed = true;
      }
      migrated.add(script.copyWith(content: persistedPath));

      if (_isLikelyTempPath(currentPath)) {
        print('[XMC] ✅ [JsScriptManager] 已迁移临时目录脚本到持久目录: ${script.name}');
      } else {
        print('[XMC] ✅ [JsScriptManager] 已归档本地脚本到持久目录: ${script.name}');
      }
    }

    return (scripts: migrated, changed: changed);
  }

  // 从本地文件导入脚本
  Future<bool> importFromLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
        allowMultiple: false,
      );

      if (result == null) {
        return false;
      }

      final pickedFile = result.files.single;
      final filePath = pickedFile.path;
      final fileName = pickedFile.name;
      if (filePath == null || filePath.trim().isEmpty) {
        print('[XMC] ❌ [JsScriptManager] 选择的文件路径无效');
        return false;
      }

      // 读取文件内容以验证
      final file = File(filePath);
      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        print('[XMC] ❌ [JsScriptManager] 脚本文件为空');
        return false;
      }

      // 生成脚本名称（去掉.js后缀）
      final scriptName =
          fileName.endsWith('.js')
              ? fileName.substring(0, fileName.length - 3)
              : fileName;

      final existingIndex = state.indexWhere(
        (s) => s.name == scriptName && s.source == JsScriptSource.localFile,
      );
      final scriptId =
          existingIndex >= 0 ? state[existingIndex].id : const Uuid().v4();
      final persistedPath = await _persistLocalScriptContent(
        content: content,
        scriptId: scriptId,
        scriptName: scriptName,
      );

      final script = JsScript(
        id: scriptId,
        name: scriptName,
        description: '从本地文件导入: $fileName',
        source: JsScriptSource.localFile,
        content: persistedPath,
        addedTime: DateTime.now(),
      );

      // 检查是否已存在同名脚本
      if (existingIndex >= 0) {
        // 替换已存在的脚本
        final newState = [...state];
        newState[existingIndex] = script;
        state = newState;
        print('[XMC] 🔄 [JsScriptManager] 替换已存在的脚本: ${script.name}');
      } else {
        // 添加新脚本
        state = [...state, script];
        print('[XMC] ➕ [JsScriptManager] 添加新脚本: ${script.name}');
      }

      // ✅ 只有在添加第一个脚本时（即当前没有选中脚本）才自动选中
      if (_selectedScriptId == null) {
        _selectedScriptId = script.id;
        print('[XMC] 🎯 [JsScriptManager] 首个脚本，自动选中: ${script.name}');
      }
      await _saveScripts();
      return true;
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 导入本地脚本失败: $e');
      return false;
    }
  }

  // 从在线地址导入脚本
  Future<bool> importFromUrl(String url, String name) async {
    try {
      if (url.trim().isEmpty || name.trim().isEmpty) {
        return false;
      }

      final script = JsScript(
        id: const Uuid().v4(),
        name: name.trim(),
        description: '从在线地址导入: $url',
        source: JsScriptSource.url,
        content: url.trim(),
        addedTime: DateTime.now(),
      );

      // 检查是否已存在同名脚本
      final existingIndex = state.indexWhere(
        (s) => s.name == script.name && s.source == JsScriptSource.url,
      );

      if (existingIndex >= 0) {
        // 替换已存在的脚本
        final newState = [...state];
        newState[existingIndex] = script;
        state = newState;
        print('[XMC] 🔄 [JsScriptManager] 替换已存在的脚本: ${script.name}');
      } else {
        // 添加新脚本
        state = [...state, script];
        print('[XMC] ➕ [JsScriptManager] 添加新脚本: ${script.name}');
      }

      // ✅ 只有在添加第一个脚本时（即当前没有选中脚本）才自动选中
      if (_selectedScriptId == null) {
        _selectedScriptId = script.id;
        print('[XMC] 🎯 [JsScriptManager] 首个脚本，自动选中: ${script.name}');
      }
      await _saveScripts();
      return true;
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 导入在线脚本失败: $e');
      return false;
    }
  }

  // 删除脚本（同时清除其缓存）
  Future<void> deleteScript(String scriptId, {WidgetRef? ref}) async {
    final script = state.firstWhere((s) => s.id == scriptId);
    if (script.isBuiltIn) {
      print('[XMC] ⚠️ [JsScriptManager] 无法删除内置脚本: ${script.name}');
      return;
    }

    state = state.where((s) => s.id != scriptId).toList();

    if (_selectedScriptId == scriptId && state.isNotEmpty) {
      _selectedScriptId = state.first.id;
    } else if (_selectedScriptId == scriptId && state.isEmpty) {
      _selectedScriptId = null;
    }

    await _saveScripts();
    print('[XMC] 🗑️ [JsScriptManager] 删除脚本: ${script.name}');

    if (script.source == JsScriptSource.localFile) {
      try {
        final file = File(script.content);
        if (await file.exists()) {
          await file.delete();
          print('[XMC] 🧹 [JsScriptManager] 已删除本地脚本文件: ${script.content}');
        }
      } catch (e) {
        print('[XMC] ⚠️ [JsScriptManager] 删除本地脚本文件失败: $e');
      }
    }

    try {
      final cacheKey = _buildScriptCacheKey(script);
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.remove(cacheKey);
      print('[XMC] 🧹 [JsScriptManager] 已同步清除缓存: $ok');
    } catch (e) {
      print('[XMC] ⚠️ [JsScriptManager] 清除缓存失败: $e');
    }
  }

  // 选择脚本
  Future<void> selectScript(String scriptId) async {
    if (state.any((s) => s.id == scriptId)) {
      _selectedScriptId = scriptId;
      await _saveScripts();
      // 强制更新状态以通知监听者
      state = [...state];
      print('[XMC] 🎯 [JsScriptManager] 选择脚本: $scriptId');
    }
  }

  // 获取脚本的实际内容（对于本地文件，读取文件内容）
  Future<String?> getScriptContent(JsScript script) async {
    try {
      switch (script.source) {
        case JsScriptSource.builtin:
        case JsScriptSource.url:
          return script.content;
        case JsScriptSource.localFile:
          final file = File(script.content);
          if (await file.exists()) {
            return await file.readAsString();
          } else {
            print('[XMC] ❌ [JsScriptManager] 本地文件不存在: ${script.content}');
            return null;
          }
      }
    } catch (e) {
      print('[XMC] ❌ [JsScriptManager] 读取脚本内容失败: $e');
      return null;
    }
  }
}

final jsScriptManagerProvider =
    StateNotifierProvider<JsScriptManager, List<JsScript>>((ref) {
      return JsScriptManager();
    });

// 获取当前选中的脚本
final selectedJsScriptProvider = Provider<JsScript?>((ref) {
  ref.watch(jsScriptManagerProvider);
  final manager = ref.read(jsScriptManagerProvider.notifier);
  return manager.selectedScript;
});
