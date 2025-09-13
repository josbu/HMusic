import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/js_proxy_provider.dart';

/// JS代理执行器测试页面
class JSProxyTestPage extends ConsumerStatefulWidget {
  const JSProxyTestPage({Key? key}) : super(key: key);

  @override
  ConsumerState<JSProxyTestPage> createState() => _JSProxyTestPageState();
}

class _JSProxyTestPageState extends ConsumerState<JSProxyTestPage> {
  final TextEditingController _scriptController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController(
    text: 'test',
  );
  final TextEditingController _songIdController = TextEditingController(
    text: '123456',
  );
  final TextEditingController _qualityController = TextEditingController(
    text: '320k',
  );

  String _testResult = '';

  @override
  void initState() {
    super.initState();
    // 预填充测试脚本
    _scriptController.text = '''
// 简单的测试脚本
console.log('测试脚本开始执行...');

// 模拟音源配置
const musicSources = {
  'test': {
    name: 'test',
    type: 'music', 
    actions: ['musicUrl'],
    qualitys: ['128k', '320k', 'flac']
  }
};

// 注册事件处理器
globalThis.lx.on(globalThis.lx.EVENT_NAMES.request, async ({action, source, info}) => {
  console.log('收到请求:', action, source, info);
  
  if (action === 'musicUrl') {
    // 模拟返回一个测试链接
    const testUrl = `https://test.example.com/music/\${source}/\${info.musicInfo.songmid}/\${info.type}`;
    console.log('返回测试链接:', testUrl);
    return testUrl;
  }
  
  throw new Error('不支持的操作: ' + action);
});

// 发送初始化完成事件
globalThis.lx.send(globalThis.lx.EVENT_NAMES.inited, {
  status: true,
  sources: musicSources
});

console.log('测试脚本加载完成');
''';
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _sourceController.dispose();
    _songIdController.dispose();
    _qualityController.dispose();
    super.dispose();
  }

  Future<void> _loadScript() async {
    final jsProxy = ref.read(jsProxyProvider.notifier);
    final success = await jsProxy.loadScript(
      _scriptController.text,
      scriptName: '测试脚本',
    );

    setState(() {
      _testResult = success ? '✅ 脚本加载成功' : '❌ 脚本加载失败';
    });
  }

  Future<void> _getMusicUrl() async {
    final jsProxy = ref.read(jsProxyProvider.notifier);
    final url = await jsProxy.getMusicUrl(
      source: _sourceController.text,
      songId: _songIdController.text,
      quality: _qualityController.text,
    );

    setState(() {
      _testResult = url != null ? '✅ 获取成功: $url' : '❌ 获取失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final jsProxyState = ref.watch(jsProxyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('JS代理执行器测试'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态显示
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('状态信息', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      '初始化状态: ${jsProxyState.isInitialized ? "✅ 已初始化" : "❌ 未初始化"}',
                    ),
                    Text(
                      '加载状态: ${jsProxyState.isLoading ? "⏳ 加载中..." : "✅ 空闲"}',
                    ),
                    Text('当前脚本: ${jsProxyState.currentScript ?? "无"}'),
                    Text(
                      '支持的音源: ${jsProxyState.supportedSources.keys.join(', ')}',
                    ),
                    if (jsProxyState.error != null)
                      Text(
                        '错误: ${jsProxyState.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // JS脚本输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('JS脚本', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _scriptController,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '在此输入JS脚本...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: jsProxyState.isLoading ? null : _loadScript,
                      child: Text(jsProxyState.isLoading ? '加载中...' : '加载脚本'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 音乐URL测试
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '音乐URL测试',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sourceController,
                            decoration: const InputDecoration(
                              labelText: '音源',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _songIdController,
                            decoration: const InputDecoration(
                              labelText: '歌曲ID',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _qualityController,
                            decoration: const InputDecoration(
                              labelText: '音质',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed:
                          (jsProxyState.isInitialized &&
                                  jsProxyState.currentScript != null)
                              ? _getMusicUrl
                              : null,
                      child: const Text('获取音乐链接'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 测试结果
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('测试结果', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        _testResult.isEmpty ? '等待测试结果...' : _testResult,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color:
                              _testResult.startsWith('✅')
                                  ? Colors.green
                                  : _testResult.startsWith('❌')
                                  ? Colors.red
                                  : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 快捷操作
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('快捷操作', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            ref.read(jsProxyProvider.notifier).clearScript();
                            setState(() {
                              _testResult = '🧹 已清除脚本';
                            });
                          },
                          child: const Text('清除脚本'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final sources =
                                ref
                                    .read(jsProxyProvider.notifier)
                                    .getSupportedSourcesList();
                            setState(() {
                              _testResult = '📋 支持的音源: ${sources.join(', ')}';
                            });
                          },
                          child: const Text('查看音源'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
