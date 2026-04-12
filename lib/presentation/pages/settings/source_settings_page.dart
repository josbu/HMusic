import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/source_settings_provider.dart';
import '../../providers/js_script_manager_provider.dart';
import '../../providers/js_proxy_provider.dart';
import '../../providers/direct_mode_provider.dart'; // 🎯 导入用于刷新代理设置
import '../../widgets/app_snackbar.dart';
import '../../../data/models/js_script.dart';
import 'package:dio/dio.dart'; // 🎯 导入用于测试代理

class SourceSettingsPage extends ConsumerStatefulWidget {
  const SourceSettingsPage({super.key});

  @override
  ConsumerState<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends ConsumerState<SourceSettingsPage> {
  late TextEditingController _proxyUrlCtrl; // 🎯 代理URL控制器
  bool _initialized = false;
  bool _userModified = false;
  bool _useAudioProxy = false; // 🎯 是否启用音频代理
  ProviderSubscription<SourceSettings>? _settingsSub;
  String _jsSearchStrategy =
      'qqFirst'; // qqFirst|kuwoFirst|neteaseFirst|qqOnly|kuwoOnly|neteaseOnly
  String _playlistResolveStrategy =
      'originalFirst'; // originalFirst|qqFirst|kuwoFirst|neteaseFirst

  @override
  void initState() {
    super.initState();
    _proxyUrlCtrl = TextEditingController(); // 🎯 初始化代理URL控制器

    // 监听 Provider 的变化：当设置加载完成且用户未修改时，同步到本地状态
    _settingsSub = ref.listenManual<SourceSettings>(sourceSettingsProvider, (
      prev,
      next,
    ) {
      // 仅在初始化完成后、且用户未修改的情况下，同步 Provider 的最新值
      if (!_initialized || _userModified) return;
      setState(() {
        _jsSearchStrategy = next.jsSearchStrategy;
        _playlistResolveStrategy = next.playlistResolveStrategy;
        _useAudioProxy = next.useAudioProxy; // 🎯 同步代理开关状态
        _proxyUrlCtrl.text = next.audioProxyUrl; // 🎯 同步代理URL
      });
    });
  }

  @override
  void dispose() {
    _settingsSub?.close();
    _proxyUrlCtrl.dispose(); // 🎯 释放代理URL控制器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoaded = ref.read(sourceSettingsProvider.notifier).isLoaded;
    final settings = ref.watch(sourceSettingsProvider);
    final scripts = ref.watch(jsScriptManagerProvider);
    final scriptManager = ref.read(jsScriptManagerProvider.notifier);
    final selectedScript = scriptManager.selectedScript;

    // 若设置尚未加载完成，显示占位，避免使用默认值误导
    if (!isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('音源设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 🔧 简化的初始化逻辑：只在首次或设置真正变化时同步
    if (!_initialized) {
      _jsSearchStrategy = settings.jsSearchStrategy;
      _playlistResolveStrategy = settings.playlistResolveStrategy;
      _useAudioProxy = settings.useAudioProxy; // 🎯 初始化代理开关
      _proxyUrlCtrl.text = settings.audioProxyUrl; // 🎯 初始化代理URL
      _initialized = true;

      print('[XMC] 🔧 [SourceSettingsPage] 首次初始化完成');
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('音源设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // JS 脚本配置区域（公开版本唯一的音源选项）
          _buildJsScriptCard(context, scripts, selectedScript, scriptManager),

          const SizedBox(height: 16),

          // 🎯 音频代理配置卡片（直连模式专用）
          _buildAudioProxyCard(context, onSurface),

          const SizedBox(height: 24),
          _buildSaveButton(context, settings, selectedScript),
        ],
      ),
    );
  }

  Widget _buildJsScriptCard(
    BuildContext context,
    List<JsScript> scripts,
    JsScript? selectedScript,
    JsScriptManager scriptManager,
  ) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.code_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'JS 脚本配置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: '导入脚本',
                  onSelected:
                      (value) => _handleScriptImport(value, scriptManager),
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'local_file',
                          child: Row(
                            children: [
                              Icon(Icons.file_open),
                              SizedBox(width: 8),
                              Text('本地文件'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'url',
                          child: Row(
                            children: [
                              Icon(Icons.link),
                              SizedBox(width: 8),
                              Text('在线地址'),
                            ],
                          ),
                        ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (scripts.isEmpty) ...[
              Text(
                '暂无可用脚本，请导入脚本',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ] else ...[
              Text(
                '选择脚本 (当前: ${selectedScript?.name ?? "未选择"})',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              ...scripts.map(
                (script) => _buildScriptTile(
                  context,
                  script,
                  selectedScript?.id == script.id,
                  scriptManager,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '搜索源优先级',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              _buildJsSearchStrategyDropdown(context),
              const SizedBox(height: 6),
              Text(
                '说明：仅在“JS 脚本”流程下用于搜索源选择；播放解析仍走JS解析。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '播放解析优先平台',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              _buildPlaylistResolveStrategyDropdown(context),
              const SizedBox(height: 6),
              Text(
                '说明：用于元歌单播放链接解析，首选失败或结果无效时会自动回退。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScriptTile(
    BuildContext context,
    JsScript script,
    bool isSelected,
    JsScriptManager scriptManager,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color:
            isSelected
                ? const Color(0xFF21B0A5).withOpacity(0.08)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border:
            isSelected
                ? Border.all(color: const Color(0xFF21B0A5).withOpacity(0.3))
                : Border.all(color: Colors.transparent),
      ),
      child: ListTile(
        leading: Icon(
          script.source == JsScriptSource.builtin
              ? Icons.integration_instructions
              : script.source == JsScriptSource.localFile
              ? Icons.file_present
              : Icons.link,
          color:
              isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          script.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${script.source.displayName} • ${script.description}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            if (!script.isBuiltIn) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed:
                    () => _confirmDeleteScript(context, script, scriptManager),
                tooltip: '删除脚本',
              ),
            ],
          ],
        ),
        onTap: () async {
          await scriptManager.selectScript(script.id);
          setState(() {}); // 触发UI更新
        },
      ),
    );
  }

  Widget _buildJsSearchStrategyDropdown(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF090E17),
          value: _jsSearchStrategy,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'qqFirst', child: Text('优先 QQ → 酷我/网易回退')),
            DropdownMenuItem(
              value: 'kuwoFirst',
              child: Text('优先 酷我 → QQ/网易回退'),
            ),
            DropdownMenuItem(
              value: 'neteaseFirst',
              child: Text('优先 网易 → QQ/酷我回退'),
            ),
            DropdownMenuItem(value: 'qqOnly', child: Text('仅 QQ')),
            DropdownMenuItem(value: 'kuwoOnly', child: Text('仅 酷我')),
            DropdownMenuItem(value: 'neteaseOnly', child: Text('仅 网易')),
          ],
          onChanged: (v) => setState(() => _jsSearchStrategy = v ?? 'qqFirst'),
        ),
      ),
    );
  }

  Widget _buildSaveButton(
    BuildContext context,
    SourceSettings settings,
    JsScript? selectedScript,
  ) {
    return FilledButton.icon(
      onPressed: () => _saveSettings(settings, selectedScript),
      icon: const Icon(Icons.save_rounded),
      label: const Text('保存'),
    );
  }

  Future<void> _handleScriptImport(
    String type,
    JsScriptManager scriptManager,
  ) async {
    bool success = false;

    if (type == 'local_file') {
      success = await scriptManager.importFromLocalFile();
    } else if (type == 'url') {
      success = await _showUrlImportDialog(scriptManager);
    }

    if (success && mounted) {
      AppSnackBar.show(
        context,
        const SnackBar(content: Text('脚本导入成功'), backgroundColor: Colors.green),
      );
    } else if (!success && mounted) {
      AppSnackBar.show(
        context,
        const SnackBar(content: Text('脚本导入失败'), backgroundColor: Colors.red),
      );
    }
  }

  Future<bool> _showUrlImportDialog(JsScriptManager scriptManager) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('导入在线脚本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '脚本名称',
                    hintText: '给脚本起个名字',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: '脚本地址',
                    hintText: 'https://example.com/script.js',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty &&
                      urlController.text.trim().isNotEmpty) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('导入'),
              ),
            ],
          ),
    );

    if (result == true) {
      return await scriptManager.importFromUrl(
        urlController.text.trim(),
        nameController.text.trim(),
      );
    }

    return false;
  }

  Future<void> _confirmDeleteScript(
    BuildContext context,
    JsScript script,
    JsScriptManager scriptManager,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除脚本'),
            content: Text('确定要删除脚本 "${script.name}" 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await scriptManager.deleteScript(script.id);
    }
  }

  Future<void> _saveSettings(
    SourceSettings settings,
    JsScript? selectedScript,
  ) async {
    try {
      final newSettings = settings.copyWith(
        enabled: true, // 公开版本始终启用 JS 脚本
        primarySource: 'js_external', // 公开版本固定使用 JS 脚本
        scriptUrl:
            selectedScript?.source == JsScriptSource.url
                ? selectedScript?.content ?? ''
                : (selectedScript?.source == JsScriptSource.builtin
                    ? selectedScript?.content ?? ''
                    : ''),
        scriptPreset: selectedScript?.id ?? 'custom',
        localScriptPath:
            selectedScript?.source == JsScriptSource.localFile
                ? selectedScript?.content ?? ''
                : '',
        jsSearchStrategy: _jsSearchStrategy,
        playlistResolveStrategy: _playlistResolveStrategy,
        // 🎯 保存代理配置
        useAudioProxy: _useAudioProxy,
        audioProxyUrl: _proxyUrlCtrl.text.trim(),
      );

      await ref.read(sourceSettingsNotifierProvider).save(newSettings);

      // 保存后尝试将所选脚本加载到 QuickJS 代理，确保播放解析使用所选脚本
      bool scriptLoadSuccess = true;
      String? scriptLoadError;
      if (selectedScript != null) {
        try {
          scriptLoadSuccess = await ref
              .read(jsProxyProvider.notifier)
              .loadScriptByScript(selectedScript);

          // 如果加载失败，获取错误信息
          if (!scriptLoadSuccess) {
            final jsProxyState = ref.read(jsProxyProvider);
            scriptLoadError = jsProxyState.error ?? '脚本加载失败';
          }
        } catch (e) {
          scriptLoadSuccess = false;
          scriptLoadError = '脚本加载异常: $e';
        }
      }

      // 🎯 刷新直连模式的代理设置（如果已登录）
      ref.read(directModeProvider.notifier).refreshProxySettings();

      if (!mounted) return;

      // 🔧 根据脚本加载结果显示不同的提示
      if (!scriptLoadSuccess && scriptLoadError != null) {
        // 脚本加载失败，显示警告
        AppSnackBar.show(
          context,
          SnackBar(
            content: Text('设置已保存，但脚本加载失败: $scriptLoadError'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        // 全部成功
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text('音源设置已保存'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildPlaylistResolveStrategyDropdown(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF090E17),
          value: _playlistResolveStrategy,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'originalFirst', child: Text('按导入原平台优先')),
            DropdownMenuItem(value: 'qqFirst', child: Text('QQ 优先')),
            DropdownMenuItem(value: 'kuwoFirst', child: Text('酷我 优先')),
            DropdownMenuItem(value: 'neteaseFirst', child: Text('网易 优先')),
          ],
          onChanged:
              (v) => setState(
                () => _playlistResolveStrategy = v ?? 'originalFirst',
              ),
        ),
      ),
    );
  }

  /// 🎯 音频代理配置卡片（直连模式专用）
  Widget _buildAudioProxyCard(BuildContext context, Color onSurface) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_sync_outlined,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '音频代理服务器',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '直连模式专用，解决CDN播放限制',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _useAudioProxy,
                  onChanged: (value) {
                    setState(() {
                      _useAudioProxy = value;
                      _userModified = true;
                    });
                  },
                ),
              ],
            ),

            if (_useAudioProxy) ...[
              const SizedBox(height: 16),

              // 代理URL输入框
              TextField(
                controller: _proxyUrlCtrl,
                decoration: InputDecoration(
                  labelText: '代理服务器地址',
                  hintText: 'https://your-worker.workers.dev',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: '填入你部署的 Cloudflare Worker 地址',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  _userModified = true;
                },
              ),

              const SizedBox(height: 12),

              // 测试连接按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _testProxyConnection(context),
                      icon: const Icon(Icons.network_check, size: 18),
                      label: const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showProxyHelp(context),
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('部署教程'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 🎯 测试代理连接
  Future<void> _testProxyConnection(BuildContext context) async {
    final proxyUrl = _proxyUrlCtrl.text.trim();

    if (proxyUrl.isEmpty) {
      if (mounted) {
        AppSnackBar.show(
          context,
          const SnackBar(
            content: Text('请先输入代理地址'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // 显示加载提示
    if (mounted) {
      AppSnackBar.show(
        context,
        const SnackBar(
          content: Text('正在测试连接...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      // 测试健康检查端点
      final healthUrl =
          proxyUrl.endsWith('/') ? '${proxyUrl}health' : '$proxyUrl/health';
      final response = await dio.get(healthUrl);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['status'] == 'ok') {
          if (mounted) {
            AppSnackBar.show(
              context,
              SnackBar(
                content: Text('连接成功！服务版本: ${data['version'] ?? '未知'}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            AppSnackBar.show(
              context,
              const SnackBar(
                content: Text('连接成功，但响应格式异常'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          AppSnackBar.show(
            context,
            SnackBar(
              content: Text('连接失败: HTTP ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('连接失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 🎯 显示代理部署帮助
  Future<void> _showProxyHelp(BuildContext context) async {
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.cloud_outlined),
                SizedBox(width: 8),
                Text('部署音频代理'),
              ],
            ),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '为什么需要代理？',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '小爱音箱直接访问音乐CDN可能被限制（User-Agent/Referer检查）。\n'
                    '通过代理转发可以绕过这些限制。',
                  ),
                  SizedBox(height: 16),
                  Text('部署步骤：', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                    '1. 注册 Cloudflare 账号\n'
                    '2. 进入 Workers & Pages\n'
                    '3. 创建新 Worker\n'
                    '4. 粘贴项目提供的代码\n'
                    '5. 部署后获取URL',
                  ),
                  SizedBox(height: 16),
                  Text('免费额度：', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('每天 100,000 次请求，个人使用完全足够！'),
                  SizedBox(height: 16),
                  Text(
                    '📁 代码位置：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'cloudflare-worker/worker.js\n'
                    'cloudflare-worker/README.md',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
    );
  }
}
