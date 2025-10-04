import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/device.dart';
import 'auth_provider.dart';
import 'dio_provider.dart';

// 用于区分"未传入参数"和"传入 null"
const _undefined = Object();

class DeviceState {
  final List<Device> devices;
  final String? selectedDeviceId;
  final bool isLoading;
  final String? error;

  const DeviceState({
    this.devices = const [],
    this.selectedDeviceId,
    this.isLoading = false,
    this.error,
  });

  DeviceState copyWith({
    List<Device>? devices,
    Object? selectedDeviceId = _undefined,
    bool? isLoading,
    String? error,
  }) {
    return DeviceState(
      devices: devices ?? this.devices,
      selectedDeviceId:
          selectedDeviceId == _undefined
              ? this.selectedDeviceId
              : selectedDeviceId as String?,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class DeviceNotifier extends StateNotifier<DeviceState> {
  final Ref ref;

  DeviceNotifier(this.ref) : super(const DeviceState()) {
    // 监听认证状态变化
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next is AuthAuthenticated && prev is! AuthAuthenticated) {
        // 用户登录后自动加载设备列表
        debugPrint('DeviceProvider: 用户已认证，自动加载设备列表');
        Future.delayed(const Duration(milliseconds: 1000), () {
          loadDevices();
        });
      }
      if (next is AuthInitial) {
        // 登出时清空设备状态
        state = const DeviceState();
      }
    });
  }

  Future<void> loadDevices() async {
    final apiService = ref.read(apiServiceProvider);
    if (apiService == null) {
      state = state.copyWith(isLoading: false, error: 'API 服务未初始化');
      return;
    }

    try {
      state = state.copyWith(isLoading: true);

      final response = await apiService.getSettings(needDeviceList: true);

      debugPrint('🔍 [DeviceProvider] mi_did: ${response['mi_did']}');

      // 🎯 优先使用 devices 字段（用户配置的设备）
      final devicesConfig = response['devices'] as Map<String, dynamic>? ?? {};
      final deviceList = response['device_list'] as List<dynamic>? ?? [];

      debugPrint('🔍 [DeviceProvider] devices 配置数量: ${devicesConfig.length}');
      debugPrint('🔍 [DeviceProvider] device_list 扫描数量: ${deviceList.length}');

      List<Device> devices = [];

      // 🎯 方案1：优先从 devices 配置中读取（更可靠）
      if (devicesConfig.isNotEmpty) {
        debugPrint('🔍 [DeviceProvider] 使用 devices 配置构建设备列表');
        devices =
            devicesConfig.entries
                .map((entry) {
                  final deviceData = entry.value as Map<String, dynamic>;
                  final did = deviceData['did']?.toString() ?? entry.key;
                  final name = deviceData['name']?.toString() ?? '未知设备';
                  final hardware = deviceData['hardware']?.toString();

                  // 从 device_list 中查找对应设备的在线状态
                  bool isOnline = false;
                  String? ip;
                  for (final item in deviceList) {
                    final itemData = item as Map<String, dynamic>;
                    if (itemData['miotDID']?.toString() == did) {
                      isOnline = itemData['presence']?.toString() == 'online';
                      ip = itemData['address']?.toString();
                      break;
                    }
                  }

                  debugPrint(
                    '🔍 [DeviceProvider] 设备: $name ($did), 在线: $isOnline',
                  );

                  return Device(
                    id: did,
                    name: name,
                    type: hardware,
                    isOnline: isOnline,
                    ip: ip,
                  );
                })
                .where((device) => device.id.isNotEmpty)
                .toList();
      }
      // 🎯 方案2：如果 devices 配置为空，尝试从 device_list 中过滤 current: true 的设备
      else if (deviceList.isNotEmpty) {
        debugPrint('🔍 [DeviceProvider] devices 配置为空，尝试从 device_list 中过滤');
        final selectedDeviceList =
            deviceList.where((json) {
              final deviceData = json as Map<String, dynamic>;
              final isCurrent = deviceData['current'] == true;
              debugPrint(
                '🔍 [DeviceProvider] 设备 ${deviceData['name']} (${deviceData['miotDID']}), current: $isCurrent',
              );
              return isCurrent;
            }).toList();

        devices =
            selectedDeviceList
                .map((json) {
                  final deviceData = json as Map<String, dynamic>;
                  final deviceID = deviceData['deviceID']?.toString() ?? '';
                  final miotDID = deviceData['miotDID']?.toString() ?? '';
                  final deviceName =
                      deviceData['name']?.toString() ??
                      deviceData['alias']?.toString() ??
                      '未知设备';

                  return Device(
                    id: miotDID.isNotEmpty ? miotDID : deviceID,
                    name: deviceName,
                    type: deviceData['hardware']?.toString(),
                    isOnline: deviceData['presence']?.toString() == 'online',
                    ip: deviceData['address']?.toString(),
                  );
                })
                .where((device) => device.id.isNotEmpty)
                .toList();
      }

      debugPrint('🔍 [DeviceProvider] 解析后的 devices 数量: ${devices.length}');
      debugPrint(
        '🔍 [DeviceProvider] 当前 selectedDeviceId: ${state.selectedDeviceId}',
      );

      // 🎯 在设备列表最前面插入"本机播放"设备
      final allDevices = [
        Device.localDevice, // 本地设备始终在最前面
        ...devices,
      ];
      debugPrint('🔍 [DeviceProvider] 添加本机设备后的总数量: ${allDevices.length}');

      state = state.copyWith(
        devices: allDevices,
        isLoading: false,
        error: null,
      );

      // 🎯 设备选择逻辑（使用 allDevices，包含本机设备）
      if (allDevices.isEmpty) {
        debugPrint('🎯 [DeviceProvider] 设备列表为空（理论上不应该发生，因为至少有本机设备）');
        state = state.copyWith(selectedDeviceId: null);
      } else if (state.selectedDeviceId == null) {
        // 没有选中任何设备时，自动选中第一个在线设备（优先本机设备）
        final onlineDevice = allDevices.firstWhere(
          (d) => d.isOnline == true,
          orElse: () => allDevices.first,
        );
        debugPrint(
          '🎯 [DeviceProvider] 自动选中设备: ${onlineDevice.name} (${onlineDevice.id})',
        );
        state = state.copyWith(selectedDeviceId: onlineDevice.id);
      } else {
        // 已选中设备时，检查该设备是否还在列表中
        final exists = allDevices.any((d) => d.id == state.selectedDeviceId);
        if (!exists) {
          // 之前选中的设备不在列表中，重新选择一个在线设备
          final onlineDevice = allDevices.firstWhere(
            (d) => d.isOnline == true,
            orElse: () => allDevices.first,
          );
          debugPrint('🎯 [DeviceProvider] 之前的设备已移除，重新选中: ${onlineDevice.name}');
          state = state.copyWith(selectedDeviceId: onlineDevice.id);
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectDevice(String deviceId) {
    state = state.copyWith(selectedDeviceId: deviceId);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceState>((
  ref,
) {
  return DeviceNotifier(ref);
});
