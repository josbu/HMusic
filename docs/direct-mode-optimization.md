# HMusic 直连模式优化分析

> 基于 `xiaomi-ubus-api-research.md` 的研究成果，分析 HMusic 直连模式可优化的功能点。
>
> 日期：2026-03-01

## 一、优化项总览

| # | 优化项 | 优先级 | 难度 | 影响面 |
|---|--------|--------|------|--------|
| 1 | 实现 seek 进度拖拽 | 🔴 高 | ⭐ 简单 | 服务层 + 策略层 + UI层 |
| 2 | 实现设备端 next/prev | 🔴 高 | ⭐ 简单 | 服务层（可选） |
| 3 | playMusic 传入 duration 参数 | 🔴 高 | ⭐ 简单 | 服务层 |
| 4 | 实现 player_set_loop 循环模式 | 🟡 中 | ⭐ 简单 | 服务层 + 策略层 |
| 5 | 修正 setPlayMode 的实现方式 | 🟡 中 | ⭐ 简单 | 服务层 |
| 6 | 从状态中提取 loop_type | 🟡 中 | ⭐ 简单 | 策略层 |
| 7 | 实验 OH2P 的 player_play_status 和 player_get_context | 🟡 中 | ⭐⭐ 中等 | 服务层 |
| 8 | 实现 set_playrate 变速播放 | 🟢 低 | ⭐ 简单 | 服务层 + UI层 |
| 9 | 实现睡眠定时器 | 🟢 低 | ⭐ 简单 | 服务层 + UI层 |

---

## 二、高优先级优化

### 优化 1：实现 seek 进度拖拽 ⭐⭐⭐

**现状问题**

策略层 `seekTo()` 是空实现，UI 层进度条在非本地模式下被禁用：

```dart
// mi_iot_direct_playback_strategy.dart:980
@override
Future<void> seekTo(int seconds) async {
  debugPrint('⚠️ [MiIoTDirect] 直连模式暂不支持进度拖动');
  // 小米IoT API目前不支持进度控制  ← ❌ 错误！实际上是支持的！
}
```

```dart
// now_playing_page.dart / control_panel_page.dart
final canSeek = playbackState.isLocalMode;  // 直连模式 isLocalMode=false → 进度条被禁用
```

**研究发现**

固件中存在 `player_set_positon` 方法（注意拼写错误是原始 API 的）：

```
method: player_set_positon
path: mediaplayer
message: {"position": <毫秒值>, "media": "app_ios"}
```

**需要改动的文件**

1. **`mi_iot_service.dart`** — 新增 `seekTo(deviceId, positionMs)` 方法
2. **`mi_iot_direct_playback_strategy.dart`** — 实现 `seekTo(seconds)` 方法，同步更新本地计时器
3. **`now_playing_page.dart`** — 修改进度条启用条件（直连模式也允许拖动）
4. **`control_panel_page.dart`** — 同上

**实现要点**

```dart
// mi_iot_service.dart — 新增方法
Future<bool> seekTo(String deviceId, int positionMs) async {
  return await _sendUbusRequest(
    deviceId: deviceId,
    method: 'player_set_positon',  // ⚠️ 注意：原始 API 拼写少了一个 i
    message: {'position': positionMs, 'media': 'app_ios'},
  );
}
```

```dart
// mi_iot_direct_playback_strategy.dart — 实现 seekTo
@override
Future<void> seekTo(int seconds) async {
  final positionMs = seconds * 1000;
  final success = await _miService.seekTo(_deviceId, positionMs);
  if (success) {
    // 同步本地计时器：重置起始时间为 now - seconds
    _localPlayStartTime = DateTime.now().subtract(Duration(seconds: seconds));
    _localAccumulatedPause = Duration.zero;
    _localPauseStartTime = null;
  }
}
```

```dart
// UI 层 — 修改进度条启用条件
// 改为：直连模式也允许 seek（但 OH2P 等 detail=null 设备可能需要特殊处理）
final canSeek = playbackState.isLocalMode || playbackState.isDirectMode;
```

> ⚠️ **风险**：需要在 OH2P 和 L05B 上实际测试验证。如果 OH2P 不支持此方法，需要做降级处理。

---

### 优化 2：playMusic 传入 duration 参数 ⭐⭐⭐

**现状问题**

`player_play_url` 和 `player_play_music` 都支持 `duration` 参数，但 HMusic 当前完全没有传递：

```dart
// mi_iot_service.dart:972 — player_play_url
final message1 = jsonEncode({
  'url': playUrl,
  'type': 2,
  'media': 'app_ios',
  // ❌ 缺少 duration 参数
});

// mi_iot_service.dart:1032 — player_play_music
final message2 = jsonEncode({
  'startaudioid': audioId,
  'music': jsonEncode(music),
  // ❌ 缺少 duration 参数
});
```

**研究发现**

固件接口定义显示两个方法都接受 `duration` 参数：

```
player_play_url:   {url, type, domain, media, src, id, duration}
player_play_music: {music, startOffset, loadMoreOffset, media, src, id, duration}
```

**假设**：如果播放时传入 `duration`（毫秒），OH2P 在 `player_get_play_status` 中可能返回更完整的 `play_song_detail`。即使不能改善 OH2P 的状态返回，也不会有副作用。

**需要改动的文件**

1. **`mi_iot_service.dart`** — `playMusic()` 方法签名新增 `duration` 参数，并传入 ubus 请求

**实现要点**

```dart
// mi_iot_service.dart — playMusic 签名变更
Future<bool> playMusic({
  required String deviceId,
  required String musicUrl,
  bool compatMode = false,
  String? musicName,
  int? durationMs,  // ← 新增：歌曲时长（毫秒）
}) async {
  ...
  // player_play_url
  final message1 = jsonEncode({
    'url': playUrl,
    'type': 2,
    'media': 'app_ios',
    if (durationMs != null) 'duration': durationMs,  // ← 新增
  });

  // player_play_music
  final message2 = jsonEncode({
    'startaudioid': audioId,
    'music': jsonEncode(music),
    if (durationMs != null) 'duration': durationMs,  // ← 新增
  });
}
```

---

### 优化 3：实现设备端 next/prev action（可选增强）

**现状**

HMusic 直连模式的 `next()`/`previous()` 是通过本地播放列表管理实现的（在 APP 端维护列表索引），不调用设备端的 ubus API。这种方式已经可以工作。

但设备端的 `player_play_operation` 支持 `next`/`prev` action，可以作为补充。

**适用场景**

- 当用户通过语音在音箱端播放了音乐（非 HMusic 发起），`next`/`prev` 可以操控音箱自己的播放队列
- 与 APP 端列表管理互补

**需要改动的文件**

1. **`mi_iot_service.dart`** — 新增 `next()`/`previous()` 方法

```dart
Future<bool> next(String deviceId) async {
  return await _sendPlayerOperation(deviceId, 'next');
}

Future<bool> previous(String deviceId) async {
  return await _sendPlayerOperation(deviceId, 'prev');
}
```

> ⚠️ **注意**：当前策略层的 `next()`/`previous()` 已有完善的本地列表管理逻辑，此优化为可选增强，不建议替换现有实现。

---

## 三、中优先级优化

### 优化 4：实现 player_set_loop 循环模式

**现状问题**

`setPlayMode()` 使用 `player_play_operation` 发送 `set_loop_mode`/`set_random` 等 action 字符串，这不是正确的 API 调用方式：

```dart
// mi_iot_service.dart:1192 — 错误的实现
String _getPlayModeCommand(String playMode) {
  switch (playMode) {
    case MiPlayMode.PLAY_TYPE_ONE:
      return 'set_loop_mode';   // ← 这些不是 player_play_operation 的有效 action！
    case MiPlayMode.PLAY_TYPE_RND:
      return 'set_random';
  }
}
// 然后通过 _sendPlayerOperation(deviceId, command) 发送
// 实际上 player_play_operation 只接受 play/pause/stop/next/prev/toggle
```

**研究发现**

正确的循环模式设置方法是 `player_set_loop`：

```
method: player_set_loop
path: mediaplayer
message: {"type": <0|1|3>, "media": "common"}
```

| type | 含义 |
|------|------|
| 0 | 单曲循环 |
| 1 | 列表循环 |
| 3 | 随机播放 |

**需要改动的文件**

1. **`mi_iot_service.dart`** — 新增 `setLoopType()` 方法，修改 `setPlayMode()` 实现

```dart
Future<bool> setLoopType(String deviceId, int type) async {
  return await _sendUbusRequest(
    deviceId: deviceId,
    method: 'player_set_loop',
    message: {'type': type, 'media': 'common'},
  );
}
```

---

### 优化 5：修正 setPlayMode 的模式映射

**现状问题**

`_getPlayModeCommand()` 返回的字符串（如 `set_loop_mode`）不是 `player_play_operation` 的有效 action。

**需要改动**

将 `MiPlayMode` 常量映射到 `player_set_loop` 的 type 值：

```dart
int _playModeToLoopType(String playMode) {
  switch (playMode) {
    case MiPlayMode.PLAY_TYPE_ONE:  // 单曲循环
    case MiPlayMode.PLAY_TYPE_SIN:  // 单曲播放
      return 0;
    case MiPlayMode.PLAY_TYPE_ALL:  // 全部循环
    case MiPlayMode.PLAY_TYPE_SEQ:  // 顺序播放
      return 1;
    case MiPlayMode.PLAY_TYPE_RND:  // 随机播放
      return 3;
    default:
      return 1;
  }
}

Future<bool> setPlayMode({...}) async {
  final loopType = _playModeToLoopType(playMode);
  return await setLoopType(deviceId, loopType);
}
```

---

### 优化 6：从播放状态中提取 loop_type

**现状问题**

`getPlayMode()` 方法无论什么情况都返回 `PLAY_TYPE_ALL`（硬编码默认值）：

```dart
// mi_iot_service.dart:1232
return MiPlayMode.PLAY_TYPE_ALL; // 默认返回全部循环
```

**研究发现**

`player_get_play_status` 返回的 info 中包含 `loop_type` 字段，直接解析即可获取当前循环模式。

**需要改动**

```dart
Future<String?> getPlayMode(String deviceId) async {
  final status = await getPlayStatus(deviceId);
  if (status == null) return null;

  final loopType = status['loop_type'] as int?;
  switch (loopType) {
    case 0: return MiPlayMode.PLAY_TYPE_ONE;
    case 1: return MiPlayMode.PLAY_TYPE_ALL;
    case 3: return MiPlayMode.PLAY_TYPE_RND;
    default: return MiPlayMode.PLAY_TYPE_ALL;
  }
}
```

---

### 优化 7：实验 OH2P 的未知 API

**目标**

在 OH2P 上测试两个未知方法，看能否获取到更完整的播放状态：

1. `player_play_status`（与 `player_get_play_status` 不同）
2. `player_get_context`

**实现方式**

在 `mi_iot_service.dart` 中新增两个实验性方法，先在日志中输出返回值：

```dart
/// 实验性：调用 player_play_status（区别于 player_get_play_status）
Future<Map<String, dynamic>?> getPlayStatusAlt(String deviceId) async {
  final result = await _sendUbusRequest(
    deviceId: deviceId,
    method: 'player_play_status',
    message: {},
    returnResult: true,
  );
  debugPrint('🔬 [MiIoT] player_play_status 返回: $result');
  return result is Map<String, dynamic> ? result : null;
}

/// 实验性：调用 player_get_context
Future<Map<String, dynamic>?> getPlayContext(String deviceId) async {
  final result = await _sendUbusRequest(
    deviceId: deviceId,
    method: 'player_get_context',
    message: {},
    returnResult: true,
  );
  debugPrint('🔬 [MiIoT] player_get_context 返回: $result');
  return result is Map<String, dynamic> ? result : null;
}
```

> 📝 这两个方法纯实验用途，根据 OH2P 返回结果决定后续是否集成。

---

## 四、低优先级优化

### 优化 8：变速播放

```dart
// 新增方法
Future<bool> setPlayRate(String deviceId, String rate) async {
  return await _sendUbusRequest(
    deviceId: deviceId,
    method: 'set_playrate',
    message: {'rate': rate},  // "0.5", "1.0", "1.5", "2.0"
  );
}
```

### 优化 9：睡眠定时器

```dart
// 设置定时暂停
Future<bool> setSleepTimer(String deviceId, {int hour = 0, int minute = 30}) async {
  return await _sendUbusRequest(
    deviceId: deviceId,
    method: 'player_set_shutdown_timer',
    message: {'action': 'pause_later', 'hour': hour, 'minute': minute, 'second': 0, 'media': 'app_ios'},
  );
}

// 取消定时
Future<bool> cancelSleepTimer(String deviceId) async {
  return await _sendUbusRequest(
    deviceId: deviceId,
    method: 'player_set_shutdown_timer',
    message: {'action': 'cancel_ending'},
  );
}

// 查询剩余时间
Future<Map<String, dynamic>?> getSleepTimer(String deviceId) async {
  return await _sendUbusRequest(
    deviceId: deviceId,
    method: 'get_shutdown_timer',
    message: {},
    returnResult: true,
  );
}
```

---

## 五、文件改动影响范围

| 文件 | 优化项 | 改动类型 |
|------|--------|----------|
| `lib/data/services/mi_iot_service.dart` | 1,2,3,4,5,6,7,8,9 | 新增/修改方法 |
| `lib/data/services/mi_iot_direct_playback_strategy.dart` | 1,6 | 实现 seek + 提取 loop_type |
| `lib/data/services/playback_strategy.dart` | — | 无需改动 |
| `lib/presentation/pages/now_playing_page.dart` | 1 | 修改进度条启用条件 |
| `lib/presentation/pages/control_panel_page.dart` | 1 | 修改进度条启用条件 |
| `lib/data/services/mi_hardware_detector.dart` | — | 无需改动 |

---

## 六、推荐实施顺序

```
第一批（核心功能）
  ├── 优化 2: playMusic 传入 duration        → 最简单，可能改善 OH2P
  ├── 优化 1: 实现 seek 进度拖拽              → 用户最期待的功能
  └── 优化 7: 实验 OH2P 的未知 API            → 可能发现新的突破口

第二批（完善体验）
  ├── 优化 4: 实现 player_set_loop            → 正确的循环模式控制
  ├── 优化 5: 修正 setPlayMode                → 修复错误实现
  └── 优化 6: 提取 loop_type                  → 显示真实循环状态

第三批（锦上添花）
  ├── 优化 3: 设备端 next/prev                → 可选增强
  ├── 优化 8: 变速播放                        → 新功能
  └── 优化 9: 睡眠定时器                      → 新功能
```

---

*文档结束。实施时请配合 `xiaomi-ubus-api-research.md` 参考 API 细节。*
