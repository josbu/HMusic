import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/source_settings_provider.dart';
import '../../widgets/app_snackbar.dart';

class SourceSettingsPage extends ConsumerStatefulWidget {
  const SourceSettingsPage({super.key});

  @override
  ConsumerState<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends ConsumerState<SourceSettingsPage> {
  late TextEditingController _apiCtrl;
  late TextEditingController _jsCtrl;
  String _scriptPreset = 'xiaoqiu';
  String _platform = 'qq';
  bool _initialized = false;
  // _jsEnabled 已由 _primary 状态隐含控制，无需单独使用
  String _primary = 'unified'; // 'unified' | 'js_external'

  @override
  void initState() {
    super.initState();
    _apiCtrl = TextEditingController();
    _jsCtrl = TextEditingController();

    // Riverpod 限制：listen 不能放在 initState，这里不监听
  }

  void _initializeFromProvider(SourceSettings s) {
    if (_initialized) return;
    _apiCtrl.text = s.unifiedApiBase;
    _platform = s.platform == 'auto' ? 'qq' : s.platform;
    _jsCtrl.text =
        s.scriptUrl.isNotEmpty
            ? s.scriptUrl
            : 'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js';
    _primary = s.primarySource;
    _scriptPreset = s.scriptPreset;
    _initialized = true;
  }

  @override
  void dispose() {
    _apiCtrl.dispose();
    _jsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(sourceSettingsProvider);

    // 只在首次初始化时同步provider状态到本地控件
    if (!_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeFromProvider(settings);
        setState(() {});
      });
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('音源设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 音源选择卡片
          Card(
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.surfaceVariant.withOpacity(0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '音源类型',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择音乐搜索和播放的数据来源',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 统一API 选项
                  _buildSourceOption(
                    context,
                    title: '统一 API',
                    subtitle: '稳定快速的多平台接口',
                    icon: Icons.cloud_outlined,
                    value: 'unified',
                    isSelected: _primary == 'unified',
                    onTap: () => setState(() => _primary = 'unified'),
                  ),
                  const SizedBox(height: 12),
                  // JS外置脚本 选项
                  _buildSourceOption(
                    context,
                    title: 'JS 外置脚本',
                    subtitle: '使用第三方脚本源',
                    icon: Icons.code_outlined,
                    value: 'js_external',
                    isSelected: _primary == 'js_external',
                    onTap: () => setState(() => _primary = 'js_external'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 配置区域
          if (_primary == 'unified') ...[
            Card(
              elevation: 0,
              color: Theme.of(
                context,
              ).colorScheme.surfaceVariant.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '统一 API 配置',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '优先平台',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _platform,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'qq', child: Text('QQ音乐')),
                            DropdownMenuItem(
                              value: 'wangyi',
                              child: Text('网易云音乐'),
                            ),
                            DropdownMenuItem(
                              value: 'kugou',
                              child: Text('酷狗音乐'),
                            ),
                            DropdownMenuItem(
                              value: 'kuwo',
                              child: Text('酷我音乐'),
                            ),
                            DropdownMenuItem(
                              value: 'migu',
                              child: Text('咪咕音乐'),
                            ),
                          ],
                          onChanged:
                              (v) => setState(() => _platform = v ?? 'qq'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_primary == 'js_external') ...[
            Card(
              elevation: 0,
              color: Theme.of(
                context,
              ).colorScheme.surfaceVariant.withOpacity(0.3),
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '脚本预置',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _scriptPreset,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'xiaoqiu',
                              child: Text('xiaoqiu.js'),
                            ),

                            DropdownMenuItem(
                              value: 'custom',
                              child: Text('自定义脚本'),
                            ),
                          ],
                          onChanged: (v) {
                            final selected = v ?? 'xiaoqiu';
                            setState(() => _scriptPreset = selected);
                            if (selected == 'xiaoqiu') {
                              _jsCtrl.text =
                                  'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js';
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '脚本地址',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _jsCtrl,
                      decoration: InputDecoration(
                        hintText: '输入或选择预置脚本地址',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              try {
                final current = ref.read(sourceSettingsProvider);
                final newSettings = current.copyWith(
                  unifiedApiBase: current.unifiedApiBase, // 固定使用默认值
                  platform: _platform,
                  enabled: _primary == 'js_external',
                  scriptUrl: _jsCtrl.text.trim(),
                  primarySource: _primary,
                  scriptPreset: _scriptPreset,
                );

                await ref
                    .read(sourceSettingsNotifierProvider)
                    .save(newSettings);
                if (!mounted) return;

                AppSnackBar.show(
                  context,
                  const SnackBar(
                    content: Text('音源设置已保存'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                AppSnackBar.show(
                  context,
                  SnackBar(
                    content: Text('保存失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primaryContainer.withOpacity(0.3)
                  : Colors.transparent,
          border: Border.all(
            color:
                isSelected
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? colorScheme.primary.withOpacity(0.1)
                        : colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color:
                    isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
