import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/device_provider.dart';
import '../../providers/dio_provider.dart';
import '../../../data/models/device.dart';
import '../../widgets/app_snackbar.dart';

class TtsSettingsPage extends ConsumerStatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  ConsumerState<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends ConsumerState<TtsSettingsPage> {
  late TextEditingController _ttsTestTextCtrl;
  String _ttsTestText = '你好，这是TTS测试';

  @override
  void initState() {
    super.initState();
    _ttsTestTextCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _ttsTestTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TTS 文字转语音'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TTS 功能说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: const Color(0xFF21B0A5),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TTS 文字转语音功能',
                          style: TextStyle(
                            color: const Color(0xFF21B0A5),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '可以将文字转换为语音播放到您的播放设备，支持中文等多种语言。',
                          style: TextStyle(
                            color: const Color(0xFF21B0A5).withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // TTS 测试区域
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.record_voice_over_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'TTS 测试',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ttsTestTextCtrl,
                    decoration: const InputDecoration(
                      labelText: '测试文字',
                      hintText: '输入要播放的文字内容',
                      border: OutlineInputBorder(),
                      helperText: '支持中文、英文等多种语言',
                    ),
                    maxLines: 3,
                    onChanged: (value) => _ttsTestText = value,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _testTts(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放TTS'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 TTS测试功能
  Future<void> _testTts() async {
    if (_ttsTestText.trim().isEmpty) {
      if (mounted) {
        AppSnackBar.showWarning(context, '请输入要测试的文字');
      }
      return;
    }

    try {
      // 获取设备状态
      final deviceState = ref.read(deviceProvider);
      if (deviceState.devices.isEmpty) {
        if (mounted) {
          AppSnackBar.showWarning(context, '未找到可用设备，请先在控制页检查设备连接');
        }
        return;
      }

      // 如果没有选中设备，提示用户选择
      if (deviceState.selectedDeviceId == null) {
        if (mounted) {
          final shouldSelectDevice = await _showDeviceSelectionDialog(
            deviceState.devices,
          );
          if (!shouldSelectDevice) return; // 用户取消选择
        }
      }

      final selectedDeviceId = deviceState.selectedDeviceId;
      if (selectedDeviceId == null) {
        if (mounted) {
          AppSnackBar.showWarning(context, '请先选择播放设备');
        }
        return;
      }

      // 显示测试状态
      if (mounted) {
        AppSnackBar.showInfo(context, '正在播放TTS: "$_ttsTestText"');
      }

      // 调用真正的TTS API
      final apiService = ref.read(apiServiceProvider);
      if (apiService != null) {
        await apiService.playTts(
          did: selectedDeviceId,
          text: _ttsTestText.trim(),
        );

        if (mounted) {
          AppSnackBar.showSuccess(context, 'TTS播放成功: "$_ttsTestText"');
        }

        // 🎯 等待TTS播放完成后，自动恢复音乐播放
        print('🎵 TTS播放完成，等待恢复音乐播放...');
        await Future.delayed(const Duration(seconds: 3)); // 等待TTS播放完成

        try {
          // 尝试恢复音乐播放
          await apiService.resumeMusic(did: selectedDeviceId);
          print('🎵 音乐播放已恢复');

          if (mounted) {
            AppSnackBar.showInfo(context, 'TTS播放完成，音乐已恢复播放');
          }
        } catch (e) {
          print('🎵 恢复音乐播放失败: $e');
          // 恢复失败不影响TTS功能，只记录日志
        }
      } else {
        throw Exception('API服务不可用');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          SnackBar(content: Text('TTS播放失败: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  // 🎯 显示设备选择对话框
  Future<bool> _showDeviceSelectionDialog(List<Device> devices) async {
    final selectedDevice = await showDialog<Device>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('选择播放设备'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    leading: Icon(
                      device.isOnline ?? false ? Icons.speaker : Icons.speaker,
                      color:
                          device.isOnline ?? false ? Colors.green : Colors.white54,
                    ),
                    title: Text(device.name),
                    subtitle: Text(
                      device.isOnline ?? false ? '在线' : '离线',
                      style: TextStyle(
                        color:
                            device.isOnline ?? false
                                ? Colors.green
                                : Colors.white54,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(device),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
    );

    if (selectedDevice != null) {
      // 设置选中的设备
      ref.read(deviceProvider.notifier).selectDevice(selectedDevice.id);
      return true;
    }
    return false;
  }
}
