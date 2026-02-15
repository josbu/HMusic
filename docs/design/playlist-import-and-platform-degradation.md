# 外部歌单导入 + 平台降级解析 — 设计文档 v6

> 创建日期：2026-02-15
> 最后更新：2026-02-15
> 状态：待实施

---

## 目录

- [一、功能概述](#一功能概述)
- [二、平台标识统一（P0 前置）](#二平台标识统一p0-前置)
- [三、旧数据迁移（P0 前置）](#三旧数据迁移p0-前置)
- [四、数据模型变更](#四数据模型变更)
- [五、Provider 层变更](#五provider-层变更)
- [六、统一解析服务 SongResolverService（🔜 后续迭代）](#六统一解析服务-songresolverservice🔜-后续迭代)
- [七、熔断器 PlatformCircuitBreaker（🔜 后续迭代）](#七熔断器-platformcircuitbreaker🔜-后续迭代)
- [八、歌单导入功能](#八歌单导入功能)
- [九、导入 UX 细节](#九导入-ux-细节)
- [十、搜索异常分类（渐进式改造）](#十搜索异常分类渐进式改造)
- [十一、搜索候选匹配评分（🔜 后续迭代）](#十一搜索候选匹配评分🔜-后续迭代)
- [十二、错误消息分层](#十二错误消息分层)
- [十三、存储层：数据库迁移（已推迟）](#十三存储层数据库迁移已推迟)
- [十三·五、模式隔离与统一存储策略](#十三五模式隔离与统一存储策略)
- [十四、文件变更清单](#十四文件变更清单)
- [十五、测试清单](#十五测试清单)
- [附录 A：降级解析示例](#附录-a降级解析示例)
- [附录 B：实施计划](#附录-b实施计划)

---

## 一、功能概述

### 1.1 目标

为 HMusic 添加导入 QQ音乐、酷我、网易云歌单的功能。导入后作为「本地元歌单」存储，播放时支持跨平台降级解析。

### 1.2 核心能力

> **交付边界说明**：本文档包含完整设计愿景（第一~十五章），但分阶段实施。
> 本期交付范围以**附录 B Phase 1~5** 为准，标记为 🔜 的能力推迟到后续迭代。

| 能力 | 说明 | 本期 |
|------|------|------|
| 歌单导入 | 粘贴分享链接，自动识别平台，解析歌单内容，一键导入 | ✅ |
| 平台标识统一 | 全代码库 canonical 归一化，消除 'wangyi' 等不一致 | ✅ |
| 多平台 songId 积累 | 每首歌存储多个平台的 songId，降级搜索时动态入库 | ✅ 模型就绪，🔜 运行时积累依赖统一解析服务 |
| 跨平台降级解析 | 原始平台解析失败时，自动尝试其他平台搜索 + 解析 | 🔜 依赖统一解析服务 |
| 熔断器 | 连续解析失败的平台自动降优先级，避免反复踩坑 | 🔜 依赖统一解析服务 |
| 统一解析服务 | 合并现有 3 处独立解析逻辑为 1 个 service | 🔜 playback_provider 4851行，风险高 |

---

## 二、平台标识统一（P0 前置）

### 2.1 双层标识体系

| 层 | 标识值 | 用途 |
|---|--------|------|
| **Canonical（内部存储 + JS 传参）** | `tx` / `kw` / `wy` | 模型字段、platformSongIds 的 key、传给 JS 脚本 |
| **Config（配置 + UI + 搜索路由）** | `qq` / `kuwo` / `netease` | 搜索策略设置（如 `qqFirst`）、搜索 API 路由、用户可见文案 |

**设计理由**：`source_settings_provider.dart` 的 `jsSearchStrategy`（`qqFirst`/`kuwoFirst`/`neteaseFirst`）及 UI 层已广泛使用 config 标识。强行全改为 canonical 会动太多设置页面和持久化数据，收益低风险高。

### 2.2 归一化工具

**新建文件**：`lib/core/utils/platform_id.dart`

```dart
import 'package:flutter/foundation.dart' show mapEquals;

class PlatformId {
  // --- Canonical 值 ---
  static const tx = 'tx';   // QQ音乐
  static const kw = 'kw';   // 酷我
  static const wy = 'wy';   // 网易云

  /// 任意输入 → canonical
  static String normalize(String raw) {
    switch (raw.toLowerCase()) {
      case 'qq': case 'tx': case 'tencent':
        return tx;
      case 'kuwo': case 'kw':
        return kw;
      case 'netease': case 'wy': case 'wangyi': case '163':
        return wy;
      default:
        return raw.toLowerCase();
    }
  }

  /// canonical → 搜索 API key（NativeMusicSearchService 用）
  static String toSearchKey(String canonical) {
    switch (canonical) {
      case tx: return 'qq';
      case kw: return 'kuwo';
      case wy: return 'netease';
      default: return canonical;
    }
  }

  /// canonical → 用户可见名称
  static String toDisplayName(String canonical) {
    switch (canonical) {
      case tx: return 'QQ音乐';
      case kw: return '酷我';
      case wy: return '网易云';
      default: return canonical;
    }
  }

  /// 原始平台优先的降级顺序
  /// 未知平台（normalize 后不在 tx/kw/wy 中）→ 回退到默认 [tx, kw, wy]
  static List<String> degradeOrder(String originalPlatform) {
    final norm = normalize(originalPlatform);
    const base = [tx, kw, wy];
    // 未知平台不插入降级列表头部，直接用默认顺序
    if (!base.contains(norm)) return base;
    return [norm, ...base.where((p) => p != norm)];
  }

  /// 深比较两个平台 songId Map
  static bool platformSongIdsEqual(
    Map<String, String>? a,
    Map<String, String>? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return mapEquals(a, b);
  }
}
```

### 2.3 现有代码全量改造点

| 文件 | 行号 | 现状 | 改为 |
|------|------|------|------|
| `native_music_search_service.dart` | :186 | `platform: 'qq'` | `platform: PlatformId.tx` |
| `native_music_search_service.dart` | :282 | `platform: 'kuwo'` | `platform: PlatformId.kw` |
| `native_music_search_service.dart` | :413 | `platform: 'wangyi'` | `platform: PlatformId.wy` |
| `webview_js_source_service.dart` | :2598-2620 | 手写 switch + default→tx | `PlatformId.normalize()` + default 保持原值不兜底 |
| `playlist_detail_page.dart` | :747-752 | 手写三元映射 | `PlatformId.normalize(platform)` |
| `playback_provider.dart` | :4624-4630 | `_mapPlatformName()` 手写 | 改为 `PlatformId.normalize()` |
| `playback_provider.dart` | :3500-3508 | `_isSamePlatform()` 手写 | `PlatformId.normalize(a) == PlatformId.normalize(b)` |
| `playback_provider.dart` | :3516-3528 | `_searchByPlatform()` switch | 用 `PlatformId.toSearchKey()` 路由 |
| `playback_provider.dart` | :4575-4582 | 内联 JS `mapPlat` 函数 | Dart 侧预 normalize，JS 不再二次映射 |
| `music_search_page.dart` | :949 | 内联 JS `mapPlat` 函数 | 同上 |
| `local_js_source_service.dart` | :667-670 | 内联 JS `mapPlat` 函数 | 同上 |
| `music_search_provider.dart` | :243-276 | switch `'qq'/'kuwo'/'netease'` | **不改**，config 层保持旧语义 |
| `source_settings_provider.dart` | :24 | `jsSearchStrategy: 'qqFirst'` | **不改**，config 层保持旧语义 |

---

## 三、旧数据迁移（P0 前置）

### 3.1 问题

SharedPreferences 中已存的 `LocalPlaylistSong.platform` 值可能是 `qq`/`kuwo`/`wangyi`/`netease` 等旧值。

### 3.2 方案：存储迁移时一并归一化

> **注意**：旧数据迁移在 `loadPlaylists()` 初始化时自动执行（见第十三·五章 §6 迁移规则）。
> 流程：检测旧 key → 读取旧 JSON → 归一化 platform → 写入新 key 结构 → 标记 modeScope → 删除旧 key。
>
> 同时处理两套旧存储：`local_playlists_cache`（→ modeScope='xiaomusic'）和 `direct_mode_playlists`（→ modeScope='direct'）。

### 3.3 归一化规则（仍适用）

迁移过程中对每首歌的 `platform` 和 `platformSongIds` key 调用 `PlatformId.normalize()`：
- `'qq'` → `'tx'`
- `'kuwo'` → `'kw'`
- `'wangyi'` / `'netease'` / `'163'` → `'wy'`

**特点**：幂等操作，跑多少次都安全。

---

## 四、数据模型变更

### 4.1 LocalPlaylistSong 新增字段

```dart
@JsonSerializable()
class LocalPlaylistSong {
  // --- 现有字段（不变）---
  final String title;
  final String artist;
  final String? platform;           // canonical (tx/kw/wy)
  final String? songId;             // 原始平台 songId
  final String? localPath;
  final String? coverUrl;
  final String? cachedUrl;
  final DateTime? urlExpireTime;
  final int? duration;

  // --- 新增 ---
  final Map<String, String>? platformSongIds;
  // 跨平台 songId 映射，降级搜索时动态积累
  // 导入时初始化: {'kw': 'originalSongId'}
  // 降级后扩展: {'kw': '123', 'tx': '456', 'wy': '789'}
}
```

**同步更新**：
- `copyWith()` 加 `platformSongIds` 参数
- `==` 使用 `PlatformId.platformSongIdsEqual()` 做深比较
- `hashCode` 加入新字段（使用 `Object.hashAll(platformSongIds?.entries.toList() ?? [])` 或类似方式）
- JSON 序列化注解
- 重新 `build_runner build`

### 4.2 LocalPlaylist 新增字段

```dart
@JsonSerializable(explicitToJson: true)
class LocalPlaylist {
  // --- 现有字段（不变）---
  final String id;
  final String name;
  final List<LocalPlaylistSong> songs;
  final DateTime createdAt;
  final DateTime updatedAt;

  // --- 新增 ---
  final String? sourcePlatform;      // 歌单来源 canonical (tx/kw/wy)，手动创建时 null
  final String? sourcePlaylistId;    // 来源歌单ID（用于去重检测）
}
```

**同步更新**：`copyWith`、`==`、`hashCode`、JSON 序列化、`build_runner` 重新生成。

---

## 五、Provider 层变更

> **注意**：本章描述 `LocalPlaylistNotifier` 的接口设计。底层存储使用 SharedPreferences（按歌单拆分 key，见第十三章 SP 优化方案），Provider 负责管理状态和写入串行化。

### 5.1 写入互斥锁

**问题**：多个方法并发执行「读 state → 改 → 写 SP」会互相覆盖。虽然 SharedPreferences 写入本身是原子的，但 Provider 层的 read-modify-write 仍需串行。

**方案**：所有写路径统一走 `_serialWrite`。

```dart
class LocalPlaylistNotifier extends StateNotifier<LocalPlaylistState> {
  Future<void>? _writeLock;

  LocalPlaylistNotifier() : super(const LocalPlaylistState()) {
    _init();
  }

  /// 串行写入保障
  Future<T> _serialWrite<T>(Future<T> Function() action) async {
    while (_writeLock != null) {
      await _writeLock;
    }
    final completer = Completer<void>();
    _writeLock = completer.future;
    try {
      return await action();
    } finally {
      _writeLock = null;
      completer.complete();
    }
  }

  // 所有写方法走 _serialWrite：
  Future<void> createPlaylist(String name) => _serialWrite(() async { ... });
  Future<void> deletePlaylist(String name) => _serialWrite(() async { ... });
  Future<void> addMusicToPlaylist({...}) => _serialWrite(() async { ... });
  Future<void> importPlaylist({...}) => _serialWrite(() async { ... });
  Future<void> updateSongFields({...}) => _serialWrite(() async { ... });

  // 只读方法不走锁，直接读 state 快照
  bool isPlaylistImported(...) { ... }
}
```

### 5.2 原子更新接口

> 底层写入对应歌单的 `local_playlist_songs_{id}` key（单歌单 O(1)），Provider 层负责刷新 state。

```dart
/// 原子更新歌曲的多个字段
Future<void> updateSongFields({
  required String playlistName,   // 歌单名称
  required int songIndex,         // 歌曲在列表中的索引
  String? cachedUrl,
  DateTime? urlExpireTime,
  int? duration,
  Map<String, String>? platformSongIds,  // 增量合并，非覆盖
}) => _serialWrite(() async {
  await _repo.updateSongFields(
    songId,
    cachedUrl: cachedUrl,
    urlExpireTime: urlExpireTime,
    duration: duration,
    platformSongIds: platformSongIds,
  );
  // 刷新内存 state（可以精确更新或全量 reload）
  await _refreshCurrentPlaylist();
});
```

旧的 `updateSongCache`、`updateSongDuration` 保留，内部改为调用 `updateSongFields`，保持向后兼容。

### 5.3 新增方法

```dart
/// 检查歌单是否已导入（去重）— 遍历内存 state 匹配
/// 去重键：modeScope + sourcePlatform + sourcePlaylistId
String? isPlaylistImported(String modeScope, String sourcePlatform, String sourcePlaylistId) {
  final match = state.playlists.firstWhereOrNull(
    (p) => p.modeScope == modeScope &&
            p.sourcePlatform == sourcePlatform &&
            p.sourcePlaylistId == sourcePlaylistId,
  );
  return match?.name;  // 返回已有歌单名，或 null 表示未导入
}

/// 歌单名去重（自动追加后缀），按当前 scope 内去重
String _deduplicateName(String name, String modeScope) {
  final existingNames = state.playlists
      .where((p) => p.modeScope == modeScope)
      .map((p) => p.name)
      .toSet();
  if (!existingNames.contains(name)) return name;
  for (int i = 2; i <= 99; i++) {
    final candidate = '$name ($i)';
    if (!existingNames.contains(candidate)) return candidate;
  }
  return '$name (${DateTime.now().millisecondsSinceEpoch})';
}

/// 导入外部歌单（事务性写入，全有或全无）
Future<void> importPlaylist({
  required String name,
  required String sourcePlatform,
  required String sourcePlaylistId,
  required List<LocalPlaylistSong> songs,
  String modeScope = 'xiaomusic',
}) => _serialWrite(() async {
  final deduped = _deduplicateName(name, modeScope);
  final now = DateTime.now();
  final playlist = LocalPlaylist(
    id: now.millisecondsSinceEpoch.toString(),
    name: deduped,
    songs: songs,
    sourcePlatform: sourcePlatform,
    sourcePlaylistId: sourcePlaylistId,
    modeScope: modeScope,
    createdAt: now,
    updatedAt: now,
  );

  // 一次性写入（先组装完整对象，再写 SP）
  final updatedPlaylists = [...state.playlists, playlist];
  state = state.copyWith(playlists: updatedPlaylists);
  await _savePlaylists();
});

/// 按当前播放模式返回可见歌单列表
List<LocalPlaylist> getVisiblePlaylists(PlaybackMode mode) {
  final allowedScopes = mode == PlaybackMode.xiaomusic
      ? ['xiaomusic', 'shared']
      : ['direct', 'shared'];
  return state.playlists
      .where((p) => allowedScopes.contains(p.modeScope))
      .toList();
}

/// 增量合并歌曲到已有歌单
Future<int> mergePlaylistSongs({
  required String playlistName,
  required List<LocalPlaylistSong> newSongs,
}) => _serialWrite(() async {
  // ... 对比已有歌曲(platform+songId)，只添加新增
  // 返回新增数量
});
```

---

## 六、统一解析服务 SongResolverService（🔜 后续迭代）

### 6.1 设计目标

合并现有 3 处独立的解析逻辑为 1 个 service：

| 现有代码 | 处理 |
|---------|------|
| `playlist_detail_page.dart:678-918` `_resolveUrlWithCache()` | **删除**，改为调用 `SongResolverService` |
| `playback_provider.dart:3400-3474` 跨平台回退逻辑 | **删除**，改为调用 `SongResolverService` |
| `playback_provider.dart:4520-4618` `_resolveUrlByJS()` | **下沉**到 `SongResolverService` 内部 |

### 6.2 服务接口

```dart
/// lib/data/services/song_resolver_service.dart

class SongResolverService {
  final Ref _ref;
  final PlatformCircuitBreaker _breaker = PlatformCircuitBreaker();

  SongResolverService(this._ref);

  /// 核心方法：解析单首歌曲的播放URL
  Future<SongResolveResult> resolve({
    required String title,
    required String artist,
    required String originalPlatform,       // canonical (tx/kw/wy)
    required String originalSongId,
    Map<String, String>? knownPlatformSongIds,
    String quality = '320k',
    String? album,
    int? duration,
    String? coverUrl,
  });

  /// 重置熔断器
  void resetBreaker() => _breaker.reset();
}
```

### 6.3 返回值

```dart
class SongResolveResult {
  final String? url;                  // 播放 URL
  final int? duration;                // 时长
  final String? resolvedPlatform;     // 实际成功的平台 canonical
  final String? resolvedSongId;       // 该平台的 songId（用于入库 platformSongIds）
  final ResolveOutcome outcome;       // 结果类型
}

enum ResolveOutcome {
  success,          // 解析成功
  searchNotFound,   // 所有平台都搜不到该歌曲
  resolveFailed,    // 搜到了但 JS 全部解析失败
  networkError,     // 网络层异常
}
```

### 6.4 内部解析流程

```
resolve() 被调用
  │
  ├─① 构建平台列表: PlatformId.degradeOrder(originalPlatform)
  ├─② 应用熔断器: _breaker.adjustOrder(platforms)
  │
  └─③ 遍历每个平台 p:
       │
       ├─ a. 查 knownPlatformSongIds[p] 是否有 songId
       │     ├─ 有: 跳过搜索，直接进入 JS 解析
       │     └─ 没有: 调搜索 API（使用 searchWithOutcome）
       │           ├─ networkError: 记录，跳到下一平台
       │           ├─ noResults: 跳到下一平台（不计熔断）
       │           └─ success: 取第一条，拿到 songId
       │
       └─ b. 拿 songId 进入 JS 解析（QuickJS → WebView → LocalJS 三层）
             ├─ 成功: _breaker.recordSuccess(p) → 返回 SongResolveResult
             └─ 失败: _breaker.recordResolveFailure(p) → 下一个平台
  │
  └─④ 全部失败 → 按优先级判定 outcome 并返回
```

### 6.5 最终 Outcome 判定规则

遍历所有平台后，收集每个平台的结果，按以下优先级判定：

```
优先级：resolveFailed > networkError > searchNotFound

- 出现过解析失败（有 songId 但 JS 解不出 URL）→ resolveFailed
  提示："解析失败，请检查 JS 脚本是否可用"

- 纯网络异常 → networkError
  提示："网络异常，请检查网络后重试"

- 全部搜不到 → searchNotFound
  提示："各平台均未找到该歌曲"
```

### 6.6 Provider 注册

```dart
final songResolverProvider = Provider<SongResolverService>((ref) {
  final service = SongResolverService(ref);

  // 监听 JS 脚本切换，自动重置熔断器
  ref.listen<JSProxyState>(jsProxyProvider, (prev, next) {
    if (prev?.currentScript != next.currentScript && next.currentScript != null) {
      service.resetBreaker();
      debugPrint('🔄 [SongResolver] JS脚本切换，熔断器已重置');
    }
  });

  ref.onDispose(() {
    debugPrint('🧹 [SongResolver] Provider disposed');
  });

  return service;
});
```

**Provider 生命周期说明**：`ref.listen` 在 Provider 内注册，生命周期与 Provider 一致，Riverpod 保证不会重复注册。

---

## 七、熔断器 PlatformCircuitBreaker（🔜 后续迭代）

### 7.1 作用域

**全局会话级共享，不按歌单隔离。**

**理由**：熔断器追踪的是「JS 脚本对某平台是否能用」，跟歌单无关。歌单 A 里 QQ 解析连续失败 → 歌单 B 里大概率也失败。

### 7.2 重置时机

- 用户切换 JS 脚本时（由 `songResolverProvider` 内的 `ref.listen` 自动触发）
- App 冷启动时（Provider 重建）
- **不在切歌单时重置**

### 7.3 实现

```dart
class PlatformCircuitBreaker {
  final Map<String, int> _consecutiveResolveFailures = {};
  static const threshold = 3;

  /// 调整平台顺序：熔断的排到最后
  List<String> adjustOrder(List<String> original) {
    final ok = original.where((p) => !isTripped(p)).toList();
    final tripped = original.where((p) => isTripped(p)).toList();
    if (ok.isEmpty) { reset(); return original; }  // 全熔断则重置
    return [...ok, ...tripped];
  }

  void recordResolveFailure(String platform) {
    _consecutiveResolveFailures[platform] =
        (_consecutiveResolveFailures[platform] ?? 0) + 1;
  }

  void recordSuccess(String platform) {
    _consecutiveResolveFailures[platform] = 0;
  }

  bool isTripped(String platform) =>
      (_consecutiveResolveFailures[platform] ?? 0) >= threshold;

  void reset() => _consecutiveResolveFailures.clear();
}
```

### 7.4 关键区分

| 情况 | 是否计入熔断 | 原因 |
|------|-------------|------|
| 搜索不到（某平台没有这首歌） | ❌ 不计 | 平台内容问题，跟 JS 脚本无关 |
| 解析失败（有 songId 但拿不到 URL） | ✅ 计入 | JS 脚本对该平台可能有问题 |
| 网络异常 | ❌ 不计 | 临时网络问题，不应影响后续判断 |

---

## 八、歌单导入功能

### 8.1 入口改造

**文件**：`playlist_page.dart` 的 FAB `+` 按钮

**改造**：点击弹出一级选择 BottomSheet：

```
┌─────────────────────────────┐
│  📝  新建空歌单               │
│  🔗  导入外部歌单             │
└─────────────────────────────┘
```

- 选「新建空歌单」→ 走现有逻辑（不变）
- 选「导入外部歌单」→ 弹出链接输入 BottomSheet

**兼容**：`showCreate=true` 路由参数仍弹出一级选择。

### 8.2 导入交互流程

```
用户粘贴文本（纯链接 或 "分享文案+链接"）
  │
  ├─① extractBestUrl(): 从文本提取最佳音乐平台 URL
  │     └─ 优先匹配音乐平台 URL (y.qq.com/kuwo.cn/163cn.tv/163.com)
  │     └─ 无音乐 URL → fallback 到第一个 URL
  ├─② identifyPlatform(): 识别平台 (tx/kw/wy)
  │     └─ 识别失败 → 提示"不支持的链接格式"
  ├─③ extractPlaylistId(): 提取歌单 ID
  │     └─ 网易云短链需跟重定向
  ├─④ isPlaylistImported(): 去重检测 (modeScope+sourcePlatform+sourcePlaylistId)
  │     └─ 已导入 → 弹三选一：
  │         ├─「增量更新」→ 获取最新歌单 → 对比已有 → 只添加新增歌曲
  │         ├─「重新导入」→ 删旧歌单 → 完整导入
  │         └─「取消」→ 中止
  ├─⑤ fetchPlaylistDetail(): 调平台 API 获取歌曲总数
  │     ├─ totalCount > 500 → 前置弹确认：「共 N 首，仅支持前 500 首，是否继续？」
  │     │     └─ 用户拒绝 → 中止（不落库，全有或全无）
  │     └─ Loading 状态："正在解析歌单..."
  ├─⑥ _cleanImportedSongs(): 清洗无效歌曲
  │     ├─ 返回 CleanResult（songs + skippedReasons 统计）
  │     ├─ 清洗后 0 首 → 提示"歌单内没有可导入的有效歌曲"
  │     └─ 超过 500 首 → 截断，记录 SkipReason.truncated
  ├─⑦ importPlaylist(): 事务性入库（全有或全无）
  │     ├─ CancelToken 取消时不执行任何写入
  │     └─ 名称冲突按当前 modeScope 内去重，自动追加后缀
  └─⑧ 刷新列表 + 展示导入结果
        ├─ 基本：「已导入「xxx」，共 N 首」
        ├─ 有跳过：「已导入 N 首，跳过 M 首（重复 X、无标题 Y）」
        └─ 有截断：「已导入 500 首（原歌单 N 首，截断 M 首）」
```

### 8.3 URL 提取与清洗

```dart
/// 已知的音乐平台域名
static const _musicDomains = [
  'y.qq.com', 'i.y.qq.com', 'c.y.qq.com',  // QQ音乐
  'kuwo.cn',                                   // 酷我
  '163cn.tv', '163.com', 'netease.com',       // 网易云
];

/// 从任意文本提取最佳音乐平台 URL
/// 优先选匹配音乐平台的 URL，找不到才 fallback 到第一个 URL
static String? extractBestUrl(String text) {
  final allUrls = RegExp(r'https?://[^\s<>"]+')
      .allMatches(text)
      .map((m) => _sanitizeUrl(m.group(0)!))
      .toList();
  if (allUrls.isEmpty) return null;

  // 优先选音乐平台 URL
  for (final url in allUrls) {
    final lower = url.toLowerCase();
    if (_musicDomains.any((d) => lower.contains(d))) return url;
  }
  // fallback 到第一个
  return allUrls.first;
}

/// 清洗 URL 尾部标点
static String _sanitizeUrl(String url) {
  // 去尾部中英文标点、引号
  url = url.replaceAll(
    RegExp(r'''[)）\]】》>,，。、；;！!？?'"'"']+$'''),
    '',
  );
  // 括号配对修正
  url = _fixBracketPairing(url, '(', ')');
  url = _fixBracketPairing(url, '（', '）');
  return url;
}

static String _fixBracketPairing(String url, String open, String close) {
  final openCount = open.allMatches(url).length;
  final closeCount = close.allMatches(url).length;
  var result = url;
  for (int i = 0; i < closeCount - openCount; i++) {
    if (result.endsWith(close)) {
      result = result.substring(0, result.length - close.length);
    }
  }
  return result;
}
```

### 8.4 平台识别规则

```dart
static String? identifyPlatform(String url) {
  final lower = url.toLowerCase();
  // QQ音乐
  if (lower.contains('y.qq.com') || lower.contains('i.y.qq.com') ||
      lower.contains('c.y.qq.com')) return PlatformId.tx;
  // 酷我
  if (lower.contains('kuwo.cn')) return PlatformId.kw;
  // 网易云
  if (lower.contains('163cn.tv') || lower.contains('163.com') ||
      lower.contains('netease')) return PlatformId.wy;
  return null;
}
```

### 8.5 歌单 ID 提取

```dart
Future<String?> extractPlaylistId(String url, String platform) async {
  switch (platform) {
    case PlatformId.tx:
      final uri = Uri.parse(url);
      // 优先：query param id=xxx
      final queryId = uri.queryParameters['id'];
      if (queryId != null && queryId.isNotEmpty) return queryId;
      // 备选：路径中数字 ID
      final pathMatch = RegExp(r'/(?:playlist|playsquare|details)/(\d+)')
          .firstMatch(uri.path);
      if (pathMatch != null) return pathMatch.group(1);
      // 兜底：路径最后一段纯数字
      final segments = uri.pathSegments
          .where((s) => RegExp(r'^\d{6,}$').hasMatch(s));
      return segments.isNotEmpty ? segments.last : null;

    case PlatformId.kw:
      // kuwo.cn/...playlist_detail/xxx 或 ?pid=xxx
      final match = RegExp(r'playlist_detail/(\d+)').firstMatch(url);
      if (match != null) return match.group(1);
      return Uri.parse(url).queryParameters['pid'];

    case PlatformId.wy:
      // 可能是短链，需跟重定向
      String realUrl = url;
      if (url.contains('163cn.tv')) {
        realUrl = await _followRedirect(url);
      }
      final uri = Uri.parse(realUrl.replaceFirst('#/', ''));
      return uri.queryParameters['id'];
  }
  return null;
}
```

### 8.6 歌单详情 API（主备接口）

```dart
class PlaylistImportService {
  static const _timeout = Duration(seconds: 15);

  static final _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
    'Accept': 'application/json',
  };

  Future<ImportedPlaylist> fetchPlaylistDetail(String platform, String id) async {
    switch (platform) {
      case PlatformId.tx: return _fetchQQ(id);
      case PlatformId.kw: return _fetchKuwo(id);
      case PlatformId.wy: return _fetchNetease(id);
      default: throw ImportException(ImportError.unsupportedPlatform);
    }
  }

  Future<ImportedPlaylist> _fetchQQ(String id) async {
    final errors = <String>[];
    // 主接口
    try {
      return await _fetchQQPrimary(id).timeout(_timeout);
    } catch (e) {
      errors.add('主接口: $e');
      debugPrint('⚠️ [Import] QQ 主接口失败: $e');
    }
    // 备用接口
    try {
      return await _fetchQQFallback(id).timeout(_timeout);
    } catch (e) {
      errors.add('备用接口: $e');
      debugPrint('❌ [Import] QQ 备用接口也失败: $e');
    }
    throw ImportException(
      ImportError.fetchFailed,
      platform: PlatformId.tx,
      detail: 'QQ音乐歌单获取失败',
      debugInfo: errors.join('\n'),
    );
  }

  // _fetchKuwo / _fetchNetease 同理，各有主备接口
}
```

**各平台必须 Headers**：
- **QQ**：`Referer: https://y.qq.com/`
- **酷我**：`Referer: https://www.kuwo.cn/`，可能需要 `Cookie: kw_token=xxx`
- **网易**：`Referer: https://music.163.com/`

### 8.7 导入结果（非异常式）

```dart
/// 跳过原因枚举
enum SkipReason {
  emptyTitle,   // 空标题
  duplicate,    // platform+songId 重复
  truncated,    // 超过 500 首截断
}

/// 清洗结果（含跳过原因统计）
class CleanResult {
  final List<LocalPlaylistSong> songs;
  final Map<SkipReason, int> skippedReasons;  // 各原因 → 跳过数
  final int totalCount;                        // 原始歌曲总数
}

/// 导入结果
class ImportResult {
  final bool success;
  final String? playlistName;
  final int importedCount;
  final int totalCount;                        // 来源歌单原始总数
  final Map<SkipReason, int> skippedReasons;   // 各跳过原因统计
  final int? mergedCount;                      // 增量更新时新增数
  final ImportError? error;
}
```

展示规则：

```dart
// 基本
var msg = '已导入「${result.playlistName}」，共 ${result.importedCount} 首';

// 有跳过
final skipped = result.skippedReasons;
if (skipped.isNotEmpty) {
  final parts = <String>[];
  if (skipped[SkipReason.duplicate] != null) parts.add('重复 ${skipped[SkipReason.duplicate]} 首');
  if (skipped[SkipReason.emptyTitle] != null) parts.add('无标题 ${skipped[SkipReason.emptyTitle]} 首');
  if (skipped[SkipReason.truncated] != null) parts.add('截断 ${skipped[SkipReason.truncated]} 首');
  msg += '（跳过：${parts.join("、")}）';
}
```

### 8.8 歌曲质量清洗

```dart
/// 清洗导入的歌曲列表，返回含跳过原因统计的结果
CleanResult _cleanImportedSongs(List<LocalPlaylistSong> raw) {
  final seen = <String>{};
  final cleaned = <LocalPlaylistSong>[];
  final skippedReasons = <SkipReason, int>{};

  void skip(SkipReason reason) =>
      skippedReasons[reason] = (skippedReasons[reason] ?? 0) + 1;

  for (final song in raw) {
    // 无 songId → 跳过
    if (song.songId == null || song.songId!.isEmpty) {
      skip(SkipReason.emptyTitle);
      continue;
    }
    // 空标题 → 跳过
    if (song.title.trim().isEmpty) {
      skip(SkipReason.emptyTitle);
      continue;
    }
    // platform+songId 去重
    final key = '${song.platform}:${song.songId}';
    if (seen.contains(key)) {
      skip(SkipReason.duplicate);
      continue;
    }
    seen.add(key);
    cleaned.add(song);
  }

  // 超过 500 首截断
  final truncated = cleaned.length > 500 ? cleaned.length - 500 : 0;
  if (truncated > 0) {
    skip(SkipReason.truncated);
    skippedReasons[SkipReason.truncated] = truncated;
  }
  final finalSongs = cleaned.take(500).toList();

  return CleanResult(
    songs: finalSongs,
    skippedReasons: skippedReasons,
    totalCount: raw.length,
  );
}
```

### 8.9 错误类型定义

```dart
enum ImportError {
  unsupportedPlatform,  // 不支持的平台
  invalidUrl,           // 无法识别的链接
  playlistNotFound,     // 歌单不存在或已删除
  fetchFailed,          // 网络/接口错误（带平台名）
}

/// 已导入歌单的处理方式（不再作为错误，改为用户选择）
enum ImportAction {
  freshImport,   // 全新导入
  mergeUpdate,   // 增量更新（只添加新歌曲）
  reimport,      // 重新导入（删旧 + 全量导入）
}

class ImportException implements Exception {
  final ImportError error;
  final String? platform;
  final String? detail;
  final String? debugInfo;

  const ImportException(this.error, {this.platform, this.detail, this.debugInfo});

  String get userMessage {
    switch (error) {
      case ImportError.fetchFailed:
        return '${PlatformId.toDisplayName(platform ?? "")}歌单获取失败，请稍后重试';
      case ImportError.playlistNotFound:
        return '歌单不存在或已被删除';
      case ImportError.invalidUrl:
        return '链接格式无法识别，请粘贴 QQ音乐/酷我/网易云 的歌单链接';
      case ImportError.unsupportedPlatform:
        return '暂不支持该平台';
    }
  }
}
```

---

## 九、导入 UX 细节

### 9.1 导入过程分阶段文案

弱网时单一"正在解析歌单..."会让用户误判卡死。改为按阶段更新 Loading 文案：

```dart
enum ImportStage {
  identifying,    // "正在识别平台..."
  resolving,      // "正在解析链接..."（网易短链重定向在这一步）
  fetching,       // "正在获取歌曲列表..."（调平台 API）
  cleaning,       // "正在整理歌曲..."（清洗 + 截断）
  saving,         // "正在写入本地..."（入库）
}
```

**UI 实现**：导入 BottomSheet 内使用 `StatefulWidget`，持有 `ImportStage` 状态：

```
┌─────────────────────────────────┐
│        导入外部歌单               │
│                                 │
│    🔄  正在获取歌曲列表...        │  ← 阶段文案动态更新
│    ━━━━━━━━━━━━━░░░░░░░░░       │  ← 线性进度条（不确定模式）
│                                 │
│    已识别: QQ音乐                │  ← 可选：显示已完成步骤
│    歌单ID: 8232088011           │
│                                 │
│              [取消]              │
└─────────────────────────────────┘
```

回调方式：`PlaylistImportService` 接受 `onStageChanged` 回调：

```dart
Future<ImportResult> importFromUrl(
  String text, {
  void Function(ImportStage stage)? onStageChanged,
});
```

### 9.2 已导入歌单的来源标识

在歌单列表卡片中显示来源平台标记，让用户能识别哪些是导入的、来自哪个平台。

**歌单卡片改造**：

```
┌─────────────────────────────────────┐
│  🎵  我喜欢的音乐                     │
│      128 首歌曲 · 来自 QQ音乐         │  ← 手动创建的歌单不显示来源
│                                     │
│  🎵  DJ合集                          │
│      56 首歌曲 · 来自 网易云           │  ← 导入歌单显示平台标记
└─────────────────────────────────────┘
```

**实现**：

```dart
// 歌单卡片 subtitle 拼接
String _buildSubtitle(LocalPlaylist playlist) {
  final count = '${playlist.songs.length} 首歌曲';
  if (playlist.sourcePlatform != null) {
    final source = PlatformId.toDisplayName(playlist.sourcePlatform!);
    return '$count · 来自 $source';
  }
  return count;
}
```

**长按/点击查看来源详情**：歌单编辑页或详情页 AppBar 的 info 按钮可展示：
- 来源平台
- 来源歌单 ID
- 导入时间（即 `createdAt`）

这样当用户遇到"该歌单已导入"提示时，能在列表中找到对应歌单。

### 9.3 多链接粘贴处理

用户可能粘贴多段文本或多个链接（如分享文案含活动页链接 + 歌单链接）。

**策略**：优先选匹配音乐平台的 URL，找不到才 fallback 到第一个。

```dart
static (String? url, bool hasMultiple) extractBestUrlWithInfo(String text) {
  final allUrls = RegExp(r'https?://[^\s<>"]+')
      .allMatches(text)
      .map((m) => _sanitizeUrl(m.group(0)!))
      .toList();
  if (allUrls.isEmpty) return (null, false);

  // 优先选音乐平台 URL
  for (final url in allUrls) {
    final lower = url.toLowerCase();
    if (_musicDomains.any((d) => lower.contains(d))) {
      return (url, allUrls.length > 1);
    }
  }
  // fallback 到第一个
  return (allUrls.first, allUrls.length > 1);
}
```

调用侧：

```dart
final (url, hasMultiple) = PlaylistImportService.extractBestUrlWithInfo(text);
if (url == null) {
  AppSnackBar.showError(context, '未识别到有效链接');
  return;
}
if (hasMultiple) {
  AppSnackBar.showInfo(context, '检测到多个链接，已自动选择音乐平台链接');
}
```

### 9.4 导入中取消

**支持取消**。导入是异步操作，用户可以在 Loading 阶段点击「取消」中断。

> **数据一致性保证（全有或全无）**：
> - CancelToken 取消发生在「获取歌曲」阶段时，**不执行任何写入**，不产生半成品歌单
> - `importPlaylist()` 采用事务性写入：先在内存组装完整歌单对象，一次性写入 SharedPreferences
> - 用户永远不会看到「只有名字没有歌曲的空壳歌单」

**实现方式**：使用 `CancelToken`（Dio 已支持）+ mounted 检查

```dart
class _ImportBottomSheetState extends State<_ImportBottomSheet> {
  CancelToken? _cancelToken;
  bool _isCancelled = false;

  Future<void> _startImport(String text) async {
    _cancelToken = CancelToken();

    try {
      final result = await importService.importFromUrl(
        text,
        cancelToken: _cancelToken,
        onStageChanged: (stage) {
          if (mounted && !_isCancelled) {
            setState(() => _currentStage = stage);
          }
        },
      );
      // ... 处理结果
    } on ImportCancelledException {
      // 用户取消，静默处理
      debugPrint('📋 [Import] 用户取消导入');
    }
  }

  void _cancel() {
    _isCancelled = true;
    _cancelToken?.cancel('用户取消');
    Navigator.pop(context);
  }
}
```

`PlaylistImportService` 内部在每个阶段切换前检查 `cancelToken.isCancelled`：

```dart
Future<ImportResult> importFromUrl(
  String text, {
  CancelToken? cancelToken,
  void Function(ImportStage)? onStageChanged,
}) async {
  onStageChanged?.call(ImportStage.identifying);
  _checkCancelled(cancelToken);
  // ... 识别平台

  onStageChanged?.call(ImportStage.resolving);
  _checkCancelled(cancelToken);
  // ... 解析链接

  onStageChanged?.call(ImportStage.fetching);
  // Dio 请求自动通过 cancelToken 取消
  // ...
}

void _checkCancelled(CancelToken? token) {
  if (token?.isCancelled == true) {
    throw ImportCancelledException();
  }
}
```

### 9.5 导入按钮防抖

**防止重复点击**：导入按钮点击后立即 disable，直到操作完成或取消。

```dart
bool _isImporting = false;

void _onImportPressed() {
  if (_isImporting) return;  // 防抖
  setState(() => _isImporting = true);

  _startImport(textController.text).whenComplete(() {
    if (mounted) setState(() => _isImporting = false);
  });
}
```

BottomSheet 中导入按钮：

```dart
FilledButton(
  onPressed: _isImporting ? null : _onImportPressed,  // disable 状态
  child: _isImporting
    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
    : const Text('导入'),
),
```

### 9.6 App 退后台再恢复

**场景**：用户点导入后切到其他 App 复制链接，再切回来。

**处理原则**：

| 阶段 | 退后台行为 |
|------|-----------|
| 输入链接（未点导入） | 无需处理，TextField 状态由 Flutter 自动保持 |
| 导入中（Loading） | 网络请求在后台尽力继续，多数情况下能完成。若系统中断，回前台后提示重试 |
| 导入完成（SnackBar） | 如果 BottomSheet 已关闭，SnackBar 在回前台后正常显示 |

**注意事项**：
- 所有 `setState` 和 `Navigator` 调用前必须检查 `mounted`
- 网络异常（含后台被中断）统一显示：「导入中断，请重试」
- **不做**持久化的"导入任务恢复"——中断后用户重新粘贴即可

> ⚠️ iOS 后台限制：App 进入后台约 30 秒后可能被系统挂起，网络请求会被中断。
> 这不是 bug，是系统限制。措辞上不承诺"后台一定能完成"。

### 9.7 导入成功后自动切换 Tab

导入完成后，自动切换到「本地元歌单」tab 页，让用户立刻看到刚导入的歌单。

**实现方式**：`playlist_page.dart` 的 TabController 需要可被外部控制。

```dart
// playlist_page.dart 中

// 导入成功回调：
void _onImportSuccess(String playlistName) {
  // 1. 切换到本地元歌单 tab（假设 index=1 是本地歌单 tab）
  _tabController.animateTo(1);

  // 2. SnackBar 提示
  AppSnackBar.showSuccess(context, '已导入「$playlistName」');
}
```

**注意**：导入 BottomSheet 在成功后 `Navigator.pop(context)` 关闭自己，然后由 `playlist_page.dart` 的回调处理 tab 切换。BottomSheet 通过返回值传递结果：

```dart
// 调用侧
final result = await showModalBottomSheet<ImportResult>(
  context: context,
  builder: (ctx) => ImportBottomSheet(...),
);
if (result != null && result.success) {
  _onImportSuccess(result.playlistName!);
}
```

### 9.8 歌单详情页来源信息 + 一键复制来源 ID

**文件**：`playlist_detail_page.dart`

**规则**：仅对有 `sourcePlatform` 的导入歌单显示来源信息入口。

**交互**：
- AppBar 右侧增加 ℹ️ 按钮（仅导入歌单可见）
- 点击弹出 BottomSheet，显示：

| 信息 | 来源 |
|------|------|
| 歌单名称 | `playlist.name` |
| 来源平台 | `PlatformId.toDisplayName(playlist.sourcePlatform!)` |
| 来源歌单 ID | `playlist.sourcePlaylistId` + 右侧复制按钮 |
| 导入时间 | `playlist.createdAt` 格式化 |

- 复制按钮：`Clipboard.setData(ClipboardData(text: ...))` + SnackBar「已复制」
- 手动创建的歌单（`sourcePlatform == null`）不显示此按钮

### 9.9 歌单卡片来源标记

**文件**：`playlist_page.dart` 的歌单列表卡片

导入歌单的副标题拼接来源信息：

```dart
// subtitle
final subtitle = playlist.sourcePlatform != null
    ? '${playlist.count} 首歌曲 · 来自 ${PlatformId.toDisplayName(playlist.sourcePlatform!)}'
    : '${playlist.count} 首歌曲';
```

---

## 十、搜索异常分类（渐进式改造）

### 10.1 问题

`native_music_search_service.dart` 所有异常 `catch → return []`，无法区分「搜不到」和「网络错误」。

### 10.2 方案：新增 WithOutcome 方法，旧方法不动

```dart
class SearchResult {
  final List<OnlineMusicResult> results;
  final SearchOutcome outcome;
  const SearchResult(this.results, this.outcome);
}

enum SearchOutcome {
  success,       // 搜索成功（有结果）
  noResults,     // 正常搜索但无结果
  networkError,  // 网络异常
}

class NativeMusicSearchService {
  // 新方法：SongResolverService 调用
  Future<SearchResult> searchQQWithOutcome({...});
  Future<SearchResult> searchKuwoWithOutcome({...});
  Future<SearchResult> searchNeteaseWithOutcome({...});

  // 旧方法保留：现有调用方不受影响
  Future<List<OnlineMusicResult>> searchQQ({...}) async {
    final result = await searchQQWithOutcome(...);
    return result.results;
  }
}
```

**好处**：不破坏现有契约（搜索页、playback_provider、封面服务等依赖空列表的逻辑不变），新老代码共存。

---

## 十一、搜索候选匹配评分（🔜 后续迭代）

### 11.1 问题

降级搜索时（用 `title + artist` 在其他平台搜），搜索结果可能返回多条候选。当前设计取第一条，但第一条不一定是最匹配的。

### 11.2 评分策略

在 `SongResolverService` 内部对候选结果评分，选最优匹配：

```dart
class _SongMatcher {
  /// 从搜索结果中选最佳匹配
  /// 返回 null 表示无可信匹配
  static OnlineMusicResult? bestMatch({
    required String targetTitle,
    required String targetArtist,
    required List<OnlineMusicResult> candidates,
    int? targetDuration,  // 秒，可选
  }) {
    if (candidates.isEmpty) return null;

    double bestScore = -1;
    OnlineMusicResult? best;

    for (final c in candidates) {
      double score = 0;

      // 标题匹配（权重最高）
      score += _titleSimilarity(targetTitle, c.title) * 60;

      // 歌手匹配
      score += _artistSimilarity(targetArtist, c.artist) * 30;

      // 时长匹配（可选辅助，±5秒以内加分）
      if (targetDuration != null && c.duration != null) {
        final diff = (targetDuration - c.duration!).abs();
        if (diff <= 5) score += 10;
        else if (diff <= 15) score += 5;
      }

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    // 阈值：至少标题部分匹配 + 歌手沾边
    // 低于 40 分认为不可信，不选
    if (bestScore < 40) {
      debugPrint('⚠️ [SongMatcher] 最高分 $bestScore 低于阈值 40，放弃匹配');
      return null;
    }

    return best;
  }

  /// 标题相似度 [0.0, 1.0]
  /// 策略：normalize 后比较（去空格、大小写、标点）
  static double _titleSimilarity(String a, String b) {
    final na = _normalizeText(a);
    final nb = _normalizeText(b);
    if (na == nb) return 1.0;
    if (na.contains(nb) || nb.contains(na)) return 0.8;
    // 简单 Jaccard：按字符集合
    final sa = na.runes.toSet();
    final sb = nb.runes.toSet();
    if (sa.isEmpty || sb.isEmpty) return 0.0;
    return sa.intersection(sb).length / sa.union(sb).length;
  }

  /// 歌手相似度 [0.0, 1.0]
  /// 考虑多歌手用 / & , 分隔的情况
  static double _artistSimilarity(String a, String b) {
    final na = _normalizeText(a);
    final nb = _normalizeText(b);
    if (na == nb) return 1.0;
    if (na.contains(nb) || nb.contains(na)) return 0.7;
    // 拆分多歌手
    final partsA = _splitArtists(a);
    final partsB = _splitArtists(b);
    final intersection = partsA.intersection(partsB);
    if (intersection.isNotEmpty) return 0.6;
    return 0.0;
  }

  static String _normalizeText(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s\-_·・\.\(\)（）【】\[\]]+'), '');

  static Set<String> _splitArtists(String s) =>
      s.split(RegExp(r'[/&,、，]+'))
          .map((e) => _normalizeText(e.trim()))
          .where((e) => e.isNotEmpty)
          .toSet();
}
```

### 11.3 集成位置

在第六章 `SongResolverService` 内部流程的步骤 ③-a 「搜索成功后取候选」改为：

```
└─ success: 调 _SongMatcher.bestMatch() 选最优
      ├─ 有匹配: 拿到 songId → 进入 JS 解析
      └─ 无可信匹配（score < 40）: 视为 noResults，跳到下一平台
```

### 11.4 只取 Top 5

搜索 API 通常返回 20-30 条结果，评分只需要前 5 条（靠前的更可能匹配）。

```dart
final top5 = searchResult.results.take(5).toList();
final match = _SongMatcher.bestMatch(
  targetTitle: title,
  targetArtist: artist,
  candidates: top5,
  targetDuration: duration,
);
```

---

## 十二、错误消息分层

### 12.1 设计原则

| 层 | 面向 | 内容 | 示例 |
|---|------|------|------|
| **用户层** | SnackBar / 对话框 | 简短、可操作、无技术术语 | "QQ音乐歌单获取失败，请稍后重试" |
| **调试层** | `debugPrint` + 异常详情 | 完整错误栈、HTTP 状态码、原始响应 | `❌ [Import] QQ 主接口返回 403: {"code":-1}` |

### 12.2 ImportException 已支持分层

```dart
class ImportException implements Exception {
  final ImportError error;
  final String? platform;
  final String? detail;       // 用户可见的补充说明（可选）
  final String? debugInfo;    // 仅 debugPrint 输出

  /// 用户层消息（SnackBar 展示）
  String get userMessage { ... }

  @override
  String toString() => 'ImportException($error, platform=$platform, '
      'detail=$detail, debug=$debugInfo)';
}
```

### 12.3 调用侧示范

```dart
try {
  final result = await importService.importFromUrl(text, ...);
  AppSnackBar.showSuccess(context, '已导入「${result.playlistName}」...');
} on ImportException catch (e) {
  // 用户看到简短消息
  AppSnackBar.showError(context, e.userMessage);
  // 开发者看到完整信息
  debugPrint('❌ [Import] ${e.toString()}');
} catch (e) {
  // 兜底：未知错误
  AppSnackBar.showError(context, '导入失败，请重试');
  debugPrint('❌ [Import] 未知异常: $e');
}
```

### 12.4 SongResolverService 同理

```dart
// 播放失败时
switch (result.outcome) {
  case ResolveOutcome.searchNotFound:
    AppSnackBar.showError(context, '各平台均未找到该歌曲');
  case ResolveOutcome.resolveFailed:
    AppSnackBar.showError(context, '解析失败，请检查 JS 脚本');
  case ResolveOutcome.networkError:
    AppSnackBar.showError(context, '网络异常，请检查网络');
}
// debugPrint 已在 service 内部完成，外部不需要重复
```

---

## 十三、存储层：数据库迁移（已推迟）

> ⚠️ **状态：已推迟**
>
> Isar 原作者已弃坑（2025-01 GitHub issue #1689），社区 fork 活跃度一般。
> 本次改为**优化 SharedPreferences 存储粒度**（按歌单拆分 key），见附录 B Phase 3。
> 数据库迁移（Drift 或其他方案）待后续评估。

### 13.1 决策记录

#### 为什么不用 Isar

| 时间线 | 事件 |
|--------|------|
| 2025-01 | Isar 原作者在 GitHub issue #1689 宣布弃坑 |
| 2025 上半年 | 社区 fork（`isar_community`、`isar_plus`）出现，但活跃度一般 |
| 2026-02（本次评估） | 社区 fork 无人成为明确继任者，长期维护风险高 |

**评估结论**：
- Isar ❌ 不采用 — 原作者弃坑，社区 fork 不稳定
- Drift/SQLite — 🔜 后续评估（完整数据库方案，收益高但改动大）
- **SharedPreferences 优化** ✅ 本期采用 — 按歌单拆分 key，解决全量读写问题

#### 本期方案：SharedPreferences 存储粒度优化

**核心改动**：

| 旧方案 | 新方案 |
|--------|--------|
| 单一 key `local_playlists_cache` 存整个列表 JSON | 元数据 key `local_playlists_meta` + 每歌单 key `local_playlist_songs_{id}` |
| 每次 `updateSongCache` 全量序列化 O(N) | 只写对应歌单 key O(1) |
| 写入互斥无保障 | `_serialWrite` 互斥锁 |

具体实现见**附录 B Phase 3**。

#### 后续路线图

当歌单数据量或查询复杂度超出 SharedPreferences 承载能力时，再评估迁移到 Drift（SQLite）：
- 前提：Drift 生态成熟、项目数据量确实达到瓶颈
- 迁移路径：SP JSON → Drift SQLite（与本次的 key 拆分方案兼容）

---

## 十三·五、模式隔离与统一存储策略

> **状态：本期实施** ✅
>
> 本章定义 xiaomusic 模式与直连模式的歌单数据隔离规则。
> 两种模式采用**统一存储** + **`modeScope` 逻辑隔离**，而非物理分库。

### 13.5.1 设计原则

- xiaomusic 和直连是两个播放模式，UI 和功能入口隔离。
- 元歌单采用统一存储，通过 `modeScope` 字段做逻辑隔离。
- 隔离的是「可见性与行为」，不是「物理存储介质」。

### 13.5.2 数据模型补充

`LocalPlaylist` 新增字段：

```dart
@JsonKey(defaultValue: 'xiaomusic')
final String modeScope;  // 取值：'xiaomusic' / 'direct' / 'shared'
```

**约束规则**：

| 场景 | modeScope 值 |
|------|-------------|
| 外部歌单导入 | 固定 `'xiaomusic'` |
| 直连模式手动创建歌单 | `'direct'` |
| xiaomusic 模式手动创建歌单 | `'xiaomusic'` |
| 未来跨模式共享（保留） | `'shared'` |

**向后兼容**：旧 JSON 数据缺失 `modeScope` 字段时，`@JsonKey(defaultValue: 'xiaomusic')` 自动补齐，与旧数据语义一致。

### 13.5.3 查询与展示规则

| 当前播放模式 | 可见元歌单 modeScope | 服务端歌单 |
|-------------|---------------------|-----------|
| xiaomusic | `['xiaomusic', 'shared']` | ✅ 可展示 |
| direct（直连） | `['direct', 'shared']` | ❌ 不展示 |

- 禁止跨模式直接读取不在可见范围内的歌单。
- Provider 新增方法 `getVisiblePlaylists(PlaybackMode mode)` 用于过滤。
- 所有歌单列表展示入口必须经过此方法。

### 13.5.4 写入规则

| 操作 | modeScope 规则 |
|------|---------------|
| 新建空歌单 | 按当前播放模式写入对应 modeScope |
| 外部歌单导入 | 固定写入 `modeScope = 'xiaomusic'` |
| 歌曲缓存/platformSongIds 更新 | 仅更新当前可见歌单，不跨 scope 操作 |
| 删除歌单 | 仅删除当前 scope 下目标歌单 |

### 13.5.5 去重规则调整

- 外部歌单去重键改为：**`modeScope + sourcePlatform + sourcePlaylistId`**
- 目的：防止未来 `shared` 或跨模式场景下误判同一来源歌单。
- 歌单名称冲突仍按当前 scope 内去重（自动追加 ` (2)` 后缀）。

### 13.5.6 迁移规则（从两套旧存储到统一存储）

**现状**：当前存在两套独立的歌单存储：

| 旧存储 | SharedPreferences key | 数据模型 | 特点 |
|--------|----------------------|---------|------|
| 本地元歌单 | `local_playlists_cache` | `LocalPlaylist` + `LocalPlaylistSong` | 完整模型（含缓存URL/duration等） |
| 直连模式歌单 | `direct_mode_playlists` | `LocalPlaylistModel`（简化版） | 歌曲仅存名称字符串 `List<String>` |

**迁移目标**：统一为新的 key 结构 + `modeScope` 标记。

| 旧 key | 迁移目标 | modeScope |
|--------|---------|-----------|
| `local_playlists_cache` | 新统一存储（`local_playlists_meta` + `local_playlist_songs_{id}`） | `'xiaomusic'` |
| `direct_mode_playlists` | 同上 | `'direct'` |

**迁移流程**（在 `loadPlaylists()` 初始化时自动执行）：

1. 检查迁移标记 `'playlist_migration_done'`，已完成则跳过
2. 读取旧 key `local_playlists_cache` → 解析 → 写入新结构 → 标记 `modeScope = 'xiaomusic'` → 同时归一化 platform
3. 读取旧 key `direct_mode_playlists` → 解析 `LocalPlaylistModel` → 转换为 `LocalPlaylist`（歌曲名称字符串 → `LocalPlaylistSong(title=名称, artist='未知歌手')`) → 标记 `modeScope = 'direct'`
4. 写入迁移标记 `'playlist_migration_done' = true`
5. 清理旧 key

**幂等要求**：重复迁移不重复写入（按歌单 id 判重）。

### 13.5.7 UI 入口规则

- **xiaomusic 模式**：显示「导入外部歌单」入口
- **direct 模式**：**隐藏导入入口**
  - 理由：直连模式的播放链路不经过 JS 解析服务，导入的在线歌曲无法播放
  - 避免用户导入后发现不能播放的困惑

### 13.5.8 错误与提示文案

| 场景 | 行为 |
|------|------|
| 模式切换后歌单列表变化 | 首次切换时 SnackBar 提示：「当前显示的是 X 模式歌单」 |
| direct 模式下触发导入入口（如保留禁用态） | 提示：「仅 xiaomusic 模式支持导入外部歌单」 |

### 13.5.9 测试要求

- [ ] 模式切换不串台：xiaomusic 创建/导入的歌单在 direct 模式不可见，反之亦然
- [ ] 迁移正确：两套旧 key 数据都能进入统一存储并带正确 modeScope
- [ ] 去重正确：同 `sourcePlatform + sourcePlaylistId` 在不同 scope 不冲突
- [ ] 当前模式写入不会污染另一模式数据
- [ ] 旧用户升级后数据完整无丢失

### 13.5.10 文件变更清单

| 文件 | 改动 |
|------|------|
| `lib/data/models/local_playlist.dart` | 新增 `modeScope` 字段 |
| `lib/presentation/providers/local_playlist_provider.dart` | 所有增删改查加 modeScope 过滤；新增双来源迁移逻辑 |
| `lib/presentation/pages/playlist_page.dart` | 按模式控制导入入口显隐；查询时传入当前模式做可见性过滤 |

---

## 十四、文件变更清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `lib/core/utils/platform_id.dart` | 平台 canonical 定义 + normalize + degradeOrder + toSearchKey + toDisplayName |
| `lib/data/services/song_resolver_service.dart` | 🔜 统一解析服务（后续迭代） |
| `lib/data/services/playlist_import_service.dart` | URL 提取/清洗 + 平台识别 + 歌单 ID 提取 + 歌单详情 API（主备） + 歌曲清洗 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `lib/data/models/local_playlist.dart` | Song 新增 `platformSongIds`；Playlist 新增 `sourcePlatform`/`sourcePlaylistId`/`modeScope`；`==`/`hashCode` 更新 |
| `lib/data/models/local_playlist.g.dart` | `build_runner build` 重新生成 |
| `lib/presentation/providers/local_playlist_provider.dart` | `_serialWrite` 写入锁；存储粒度拆分（meta+songs per playlist）；双来源迁移（local_playlists_cache + direct_mode_playlists）；modeScope 过滤；新增 `importPlaylist`/`isPlaylistImported`/`getVisiblePlaylists`/`_deduplicateName`/`updateSongFields`/`mergePlaylistSongs` |
| `lib/presentation/pages/playlist_page.dart` | FAB 改为两级 BottomSheet（新建/导入）；direct 模式隐藏导入入口；modeScope 过滤歌单列表；来源标记；导入成功后自动切 tab |
| `lib/presentation/pages/playlist_detail_page.dart` | 来源信息 BottomSheet + 一键复制来源 ID |
| `lib/presentation/providers/playback_provider.dart` | `_mapPlatformName`/`_isSamePlatform`/`_searchByPlatform` → `PlatformId` |
| `lib/data/services/native_music_search_service.dart` | platform 写入改 canonical |
| `lib/data/services/webview_js_source_service.dart` | 平台映射改 `PlatformId.normalize()`，default 不再兜底 tx |
| `lib/presentation/pages/music_search_page.dart` | 内联 JS `mapPlat` → Dart 侧预 normalize |
| `lib/data/services/local_js_source_service.dart` | 同上 |

### 删除文件

无（旧 model 保留用于迁移，标记 deprecated）

---

## 十五、测试清单

| 类别 | 测试项 |
|------|--------|
| **PlatformId** | `normalize('wangyi')=='wy'`；`normalize('qq')=='tx'`；`normalize('163')=='wy'`；`degradeOrder('kw')==['kw','tx','wy']`；**`degradeOrder('spotify')==['tx','kw','wy']`**（未知平台回退）；`toSearchKey('tx')=='qq'`；`platformSongIdsEqual` 深比较 |
| **URL 提取** | 纯链接；"分享文案+链接"；多链接优先选音乐平台 URL；无链接返回 null；尾部 `）` `，` `。` `'` 被正确去除；括号配对修正 |
| **平台识别** | `i.y.qq.com`→tx；`c.y.qq.com`→tx；`kuwo.cn`→kw；`163cn.tv`→wy；`music.163.com`→wy；未知→null |
| **歌单 ID 提取** | QQ query param；QQ 路径式；酷我 path；酷我 query；网易短链重定向；网易 `#/playlist?id=` |
| **旧数据迁移** | 双来源迁移：`local_playlists_cache`→modeScope='xiaomusic'；`direct_mode_playlists`→modeScope='direct'；歌曲数量正确；platform 已归一化；迁移后旧 key 已删除；二次启动不重复迁移 |
| **搜索候选评分** | 🔜（后续迭代）完全匹配 score≈90+；标题相似 artist 相同 score≈70+；无匹配 score<40 返回 null |
| **熔断器** | 🔜（后续迭代）3 次 resolveFailure 触发熔断；1 次 success 重置 |
| **写入锁** | 并发 create+update 不互相覆盖（Provider 层） |
| **去重** | modeScope+sourcePlatform+sourcePlaylistId 检测已导入；不同 scope 同源不冲突 |
| **名称冲突** | 按当前 scope 内去重；自动追加 `(2)`；多次导入同名递增；`(2)` 已存在时跳到 `(3)` |
| **歌曲清洗** | 无 songId 跳过；空标题跳过；platform+songId 去重；清洗后 0 首报错；跳过原因统计正确 |
| **500 首截断** | 前置确认弹窗（>500时）；截断后跳过原因含 SkipReason.truncated |
| **错误消息分层** | ImportException.userMessage 不含技术细节；debugInfo 包含 HTTP 状态码和原始响应；兜底 catch 显示通用消息 |
| **模式隔离** | xiaomusic 创建的歌单在 direct 不可见；direct 创建的在 xiaomusic 不可见；导入固定归属 xiaomusic；模式切换不污染另一模式数据 |
| **导入 UX** | 阶段文案按顺序切换；多链接优先选音乐平台 URL；重复点击导入按钮被防抖；取消导入不落库（全有或全无）；已导入弹三选一；来源标记在歌单卡片正确显示；来源信息 BottomSheet + 复制来源 ID；导入结果展示跳过原因；导入完成后自动切 tab；direct 模式隐藏导入入口 |

---

## 附录 A：降级解析示例

```
歌曲 A（导入自酷我）
  初始存储: platform=kw, songId='123', platformSongIds={'kw':'123'}

第一次播放:
  ① 无缓存
  ② 平台顺序: [kw, tx, wy]（熔断器无状态）
  ③ kw:123 → JS 解析 → 成功 ✅
     存 cachedUrl，熔断器 recordSuccess('kw')

第二次播放（URL 已过期，kw 的 JS 解析挂了）:
  ① 缓存过期
  ② 平台顺序: [kw, tx, wy]
  ③ kw:123 → JS 解析 → 失败，recordResolveFailure('kw')=1
  ④ tx: platformSongIds 没有 tx → 搜索 "歌名+歌手"
     → 搜到 tx:456 → 入库 platformSongIds={'kw':'123','tx':'456'}
     → tx:456 → JS 解析 → 成功 ✅
     存 cachedUrl，recordSuccess('tx')

后续连续 3 首都是 kw 解析失败（kw 失败计数达到 3）:
  熔断器触发 → 后续歌曲平台顺序变为 [tx, wy, kw]
  直接从 tx 开始，跳过 kw 的无用尝试

用户导入新的 JS 脚本:
  ref.listen 触发 → 熔断器 reset → 所有平台恢复默认优先级
```

---

## 附录 B：实施计划

### B.1 关键决策

| 决策 | 结论 | 原因 |
|------|------|------|
| Isar 数据库 | ❌ 不用 | 原作者弃坑（2025-01 issue #1689），社区 fork 活跃度一般，风险太高 |
| 存储方案 | SharedPreferences 优化 | 按歌单拆分存储 key，单歌曲更新从 O(N) 变 O(1) |
| 统一解析服务 | 推迟 | playback_provider.dart 有 4851 行，合并 3 处解析路径风险过高 |
| 搜索评分 / 熔断器 | 推迟 | 与导入核心功能无直接依赖，后续迭代 |

### B.2 实施阶段

严格顺序：Phase 1 → 2 → 3 → 4 → 5，每个依赖前一个。

#### Phase 1: 平台标识统一 (P0 前置)

**新建**：`lib/core/utils/platform_id.dart`
- `PlatformId` 类：`normalize()`, `degradeOrder()`, `toSearchKey()`, `toDisplayName()`, `platformSongIdsEqual()`

**修改 10 处映射点**：

| 文件 | 位置 | 改动 |
|------|------|------|
| `native_music_search_service.dart` | :186 | `'qq'` → `PlatformId.tx` |
| 同上 | :282 | `'kuwo'` → `PlatformId.kw` |
| 同上 | :413 | `'wangyi'` → `PlatformId.wy` |
| `webview_js_source_service.dart` | :2598-2620 | switch → `PlatformId.normalize()` |
| `playlist_detail_page.dart` | :747-752 | → `PlatformId.normalize()` |
| `playback_provider.dart` | :4624-4632 | `_mapPlatformName()` → `PlatformId.normalize()` |
| 同上 | :3500-3508 | `_isSamePlatform()` → normalize 比较 |
| 同上 | :3516-3528 | `_searchByPlatform()` → canonical match |
| `music_search_page.dart` | :949 | JS `mapPlat` → Dart 预 normalize |
| `local_js_source_service.dart` | :667-670 | 同上 |

#### Phase 2: 数据模型扩展

**修改**：`lib/data/models/local_playlist.dart`

- `LocalPlaylistSong` 新增 `platformSongIds: Map<String, String>?`
- `LocalPlaylist` 新增 `sourcePlatform: String?` + `sourcePlaylistId: String?` + `modeScope: String`（默认 `'xiaomusic'`）
- `modeScope` 使用 `@JsonKey(defaultValue: 'xiaomusic')` 保证向后兼容
- 更新 copyWith / == / hashCode / JSON 序列化
- 运行 `flutter pub run build_runner build --delete-conflicting-outputs`

#### Phase 3: Provider 层增强

**修改**：`lib/presentation/providers/local_playlist_provider.dart`

1. **写入互斥锁** `_serialWrite`
2. **存储拆分**：
   - `'local_playlists_meta'` — 歌单基本信息
   - `'local_playlist_songs_{id}'` — 每个歌单独立
3. **旧数据双来源迁移**：
   - 旧 key `local_playlists_cache` → 拆分 → 归一化 platform → 标记 `modeScope = 'xiaomusic'`
   - 旧 key `direct_mode_playlists` → 转换 → 标记 `modeScope = 'direct'`
   - 迁移标记 `'playlist_migration_done'`，幂等
4. **新增方法**：`importPlaylist()`, `isPlaylistImported(modeScope, ...)`, `getVisiblePlaylists()`, `_deduplicateName(name, modeScope)`, `updateSongFields()`, `mergePlaylistSongs()`
5. **旧方法改造**：全部包裹 `_serialWrite`

#### Phase 4: 歌单导入服务

**新建**：`lib/data/services/playlist_import_service.dart`

- `importFromUrl(text, {onStageChanged, cancelToken})` — 主入口
- URL 提取 + 清洗 + 多链接检测
- 平台识别（y.qq.com / kuwo.cn / 163cn.tv）
- 歌单 ID 提取（各平台 URL 模式）
- 歌单详情 API（主备各一，3 个平台共 6 个端点）
- 歌曲清洗（去重 + 空标题过滤 + 500 首截断）
- ImportResult / ImportError / ImportException / ImportStage 类型

#### Phase 5: 导入 UI

**修改**：`lib/presentation/pages/playlist_page.dart`

1. FAB `onPressed` → 一级选择 BottomSheet（新建 / 导入）；direct 模式下隐藏导入入口
2. 导入 BottomSheet：TextField + 防抖按钮 + 5 阶段 Loading + CancelToken（取消=不落库）
3. 500 首前置确认（拉取详情前弹确认）；已导入歌单弹三选一（增量更新/重新导入/取消）
4. 导入成功后自动切换 local tab + 展示导入结果（含跳过原因统计）
5. 歌单卡片来源标记（`来自 QQ音乐` 等）
6. 歌单详情页来源信息 BottomSheet + 一键复制来源 ID
7. 模式切换后歌单列表按 modeScope 过滤（参见第十三·五章）

### B.3 推迟项（后续迭代）

| 项 | 设计文档章节 | 预计改动量 |
|----|------------|-----------|
| 统一解析服务 SongResolverService | 第六章 | ~600 行（含删除重复代码） |
| 熔断器 PlatformCircuitBreaker | 第七章 | ~100 行 |
| 搜索候选匹配评分 _SongMatcher | 第十一章 | ~200 行 |
| searchXxxWithOutcome 方法 | 第十章 | ~150 行 |
| 数据库迁移（Drift 或其他） | 第十三章需重写 | 待评估 |

### B.4 验证清单

- [ ] Phase 1：现有搜索和播放功能不受影响，`flutter analyze` 无 warning
- [ ] Phase 2：`build_runner` 成功，旧 JSON 反序列化正常（modeScope 默认 'xiaomusic'）
- [ ] Phase 3：旧用户升级自动迁移两套旧 key，现有 CRUD 功能正常
- [ ] Phase 3：模式切换不串台（xiaomusic 歌单在 direct 不可见，反之亦然）
- [ ] Phase 4：3 个平台真实歌单链接导入成功，去重/截断/短链跳转正常
- [ ] Phase 4：多链接粘贴能正确选到音乐平台 URL
- [ ] Phase 5：FAB 两级菜单（xiaomusic）/ 直接创建（direct）
- [ ] Phase 5：500 首前置确认、已导入三选一、跳过原因展示
- [ ] Phase 5：来源信息 BottomSheet + 一键复制来源 ID
- [ ] Phase 5：取消导入不残留半成品歌单
- [ ] 端到端：导入歌单 → 播放歌曲 → 解析成功
