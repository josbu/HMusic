# JS 音源：移除统一API回退 🚫

## 问题描述

用户反馈：
> **当我选了 JS 脚本，那么就不要再用其他的来解析音源**

### 原来的行为 ❌

当用户选择 **JS 脚本音源** 时，如果 JS 解析失败，系统会自动回退到 **统一API**：

```
[XMC] 🎵 [Play] JS源播放：解析直链或构造API链接
[XMC] 🎵 [Play] JS解析失败，回退到统一API
🎵 [UnifiedAPI] 获取播放链接: songId=002tNzue0g8xQA, platform=qq, quality=320k
❌ [UnifiedAPI] 完整响应: {data: , code: 403, error: (°ー°〃) 源站反馈此音频需要付费}
[XMC] ❌ [Play] 统一API回退失败
```

**问题**:
1. ❌ 用户选择了 JS 音源，但系统擅自切换到统一API
2. ❌ 统一API可能返回付费提示或其他错误
3. ❌ 混淆了用户的音源选择，违背了用户意图

## 解决方案 ✅

### 修改原则

**JS 音源选择后，保持纯净性**：
- ✅ 只使用 JS 解析方法（QuickJS → WebView JS → LocalJS）
- ✅ JS 解析失败时，直接提示用户失败原因
- ❌ 不再回退到统一API

### 修改位置

**文件**: `lib/presentation/pages/music_search_page.dart`

#### 1️⃣ 播放音乐时的回退逻辑（第 656-669 行）

**修改前**:
```dart
} else {
  // 公开版本：使用统一API作为回退
  print('[XMC] 🎵 [Play] JS解析失败，回退到统一API');
  try {
    final unifiedService = ref.read(unifiedApiServiceProvider);
    final unifiedUrl = await unifiedService.getMusicUrl(
      songId: id,
      platform: platform,
      quality: '320k',
    );
    // ... 使用统一API播放
  } catch (e) {
    // ... 统一API也失败
  }
}
```

**修改后**:
```dart
} else {
  // 🚫 JS 音源解析失败：不再回退到统一API
  print('[XMC] ❌ [Play] JS解析失败，无法获取播放链接');
  if (mounted) {
    AppSnackBar.show(
      context,
      SnackBar(
        content: Text('播放失败: JS脚本无法解析该歌曲\n请尝试其他歌曲或重新加载脚本'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
  return; // 直接返回，不继续执行
}
```

#### 2️⃣ 解析播放URL时的回退逻辑（第 454-456 行）

**修改前**:
```dart
// 最后回退到统一API解析
try {
  final unifiedService = ref.read(unifiedApiServiceProvider);
  final url = await unifiedService.getMusicUrl(
    songId: id,
    platform: platform,
    quality: '320k',
  );
  if (url != null && url.isNotEmpty) return url;
} catch (_) {}

return null;
```

**修改后**:
```dart
// 🚫 不再回退到统一API，保持 JS 音源的纯净性
print('[XMC] ⚠️ [Resolve] 所有JS解析方法均失败，返回null');
return null;
```

## 新的行为流程 🎯

### JS 音源模式

```
用户点击播放
    ↓
尝试 QuickJS 代理解析
    ↓ 失败
尝试 WebView JS 解析
    ↓ 失败
尝试 LocalJS 解析
    ↓ 失败
❌ 显示错误提示：JS脚本无法解析该歌曲
   请尝试其他歌曲或重新加载脚本
```

### 统一API模式（不受影响）

```
用户点击播放
    ↓
直接使用统一API
    ↓
获取播放链接并播放
```

## 用户体验改进 💡

### 修改前 ❌
1. 用户选择 JS 音源
2. JS 解析失败
3. **系统偷偷切换到统一API**
4. 统一API返回错误（付费/限制等）
5. 用户困惑：为什么会有统一API的错误？

### 修改后 ✅
1. 用户选择 JS 音源
2. JS 解析失败
3. **系统明确提示 JS 解析失败**
4. 用户清楚问题所在
5. 可以选择：
   - 尝试其他歌曲
   - 重新加载 JS 脚本
   - 切换到统一API音源

## 失败场景处理 🛠️

当 JS 解析失败时，用户会看到清晰的提示：

```
🔴 播放失败: JS脚本无法解析该歌曲
   请尝试其他歌曲或重新加载脚本
```

### 可能的失败原因
1. **JS 脚本未加载或初始化失败**
   - 解决：到设置页面重新加载脚本

2. **音乐平台限制**
   - VIP 专属歌曲
   - 地区限制
   - 版权保护
   - 解决：尝试其他歌曲

3. **JS 脚本过期**
   - 音乐平台API变更
   - 解决：更新到最新的 JS 脚本

4. **网络问题**
   - 无法连接音乐平台服务器
   - 解决：检查网络连接

## 测试步骤 ✅

1. **设置 JS 音源**
   - 进入设置页面
   - 选择 "JS 外部源"
   - 加载 JS 脚本

2. **搜索并播放**
   - 搜索歌曲
   - 点击播放
   - 观察日志和提示

3. **预期结果**
   - ✅ JS 解析成功：正常播放
   - ✅ JS 解析失败：显示红色提示，不再尝试统一API

4. **日志验证**
   ```
   [XMC] 🎵 [Play] JS源播放：解析直链或构造API链接
   [XMC] ❌ [Play] JS解析失败，无法获取播放链接
   ```
   
   **不应该再出现**:
   ```
   ❌ [XMC] 🎵 [Play] JS解析失败，回退到统一API
   ❌ 🎵 [UnifiedAPI] 获取播放链接...
   ```

## 代码影响范围 📊

### 修改的文件
- ✅ `lib/presentation/pages/music_search_page.dart`

### 影响的功能
- ✅ 在线音乐播放（搜索页面）
- ✅ 播放 URL 解析

### 不影响的功能
- ✅ 统一API音源模式（仍正常工作）
- ✅ 本地音乐播放
- ✅ 服务器音乐播放
- ✅ 音乐搜索功能

## 音源模式对比 📋

| 音源模式 | 搜索方式 | 解析方式 | 失败处理 |
|---------|---------|---------|---------|
| **JS 音源** | 原生API | JS 脚本解析 | ❌ 不回退，直接提示 |
| **统一API** | 统一API | 统一API | ✅ 可以平台回退 |

## 总结 🎉

### 核心改变
**尊重用户的音源选择，保持 JS 音源的纯净性**

### 好处
1. ✅ **明确性**: 用户清楚知道自己在用什么音源
2. ✅ **可控性**: 用户可以自主决定是否切换音源
3. ✅ **透明性**: 失败原因明确，不会混淆
4. ✅ **一致性**: JS 音源就是 JS 音源，不会偷偷切换

### 用户指南
- 如果 JS 解析经常失败 → 考虑更新 JS 脚本或切换到统一API
- 如果想要更稳定的体验 → 使用统一API音源
- 如果想要最新的音源支持 → 使用 JS 音源并保持脚本更新

---

**修改完成时间**: 2025-01-04  
**测试状态**: ✅ 通过编译检查，待运行测试

🎵 **现在按 `R` 热重载，测试 JS 音源播放！**

