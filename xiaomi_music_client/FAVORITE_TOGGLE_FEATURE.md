# 收藏/取消收藏功能实现

## 功能说明

实现了完整的收藏和取消收藏功能，用户可以通过点击收藏按钮在"收藏"和"取消收藏"之间切换。

## API接口

### 加入收藏
```json
POST /cmd
{
  "did": "设备ID",
  "cmd": "加入收藏"
}
```

### 取消收藏
```json
POST /cmd
{
  "did": "设备ID",
  "cmd": "取消收藏"
}
```

## 实现细节

### 1. 数据模型更新 (`lib/presentation/providers/playback_provider.dart`)

#### PlaybackState 添加收藏状态字段
```dart
class PlaybackState {
  // ... 其他字段
  final bool isFavorite; // ⭐ 当前歌曲是否已收藏
  
  const PlaybackState({
    // ... 其他参数
    this.isFavorite = false, // 默认未收藏
  });
}
```

### 2. 业务逻辑实现 (`lib/presentation/providers/playback_provider.dart`)

#### 新增方法

##### `removeFromFavorites()` - 取消收藏
```dart
/// 💔 取消收藏
Future<void> removeFromFavorites() async {
  // 验证设备和API服务
  // 执行取消收藏命令
  await apiService.executeCommand(did: selectedDid, command: '取消收藏');
  state = state.copyWith(isFavorite: false);
}
```

##### `toggleFavorites()` - 切换收藏状态
```dart
/// ⭐💔 切换收藏状态
Future<void> toggleFavorites() async {
  if (state.isFavorite) {
    await removeFromFavorites();
  } else {
    await addToFavorites();
  }
}
```

#### 修改方法

##### `addToFavorites()` - 更新收藏状态
```dart
/// ⭐ 加入收藏
Future<void> addToFavorites() async {
  // ... 验证逻辑
  await apiService.executeCommand(did: selectedDid, command: '加入收藏');
  state = state.copyWith(isFavorite: true); // 更新状态
}
```

##### `refreshStatus()` - 歌曲切换时重置收藏状态
```dart
// 🎯 如果歌曲切换，清除旧的封面图和收藏状态
state = state.copyWith(
  // ... 其他字段
  isFavorite: isSongChanged ? false : state.isFavorite, // 切歌时重置
);
```

### 3. UI实现 (`lib/presentation/pages/control_panel_page.dart`)

#### 智能收藏按钮
```dart
IconButton(
  // 动态图标：实心表示已收藏，空心表示未收藏
  icon: Icon(
    state.isFavorite
        ? Icons.favorite_rounded        // 已收藏：实心红心
        : Icons.favorite_border_rounded,// 未收藏：空心红心
  ),
  iconSize: 28,
  // 动态颜色：已收藏红色，未收藏粉色
  color: favoriteEnabled
      ? (state.isFavorite ? Colors.redAccent : Colors.pinkAccent)
      : onSurface.withOpacity(0.4),
  // 点击切换收藏状态
  onPressed: favoriteEnabled
      ? () => ref.read(playbackProvider.notifier).toggleFavorites()
      : null,
  // 动态提示文本
  tooltip: state.isFavorite ? '取消收藏' : '加入收藏',
)
```

## 功能特性

✅ **智能切换** - 单击按钮即可在收藏/取消收藏之间切换  
✅ **视觉反馈** - 使用不同图标和颜色表示收藏状态  
  - 未收藏：空心红心 + 粉色
  - 已收藏：实心红心 + 红色  
✅ **自动重置** - 切换歌曲时自动重置收藏状态  
✅ **错误处理** - 完善的错误提示和日志记录  
✅ **状态保护** - 只有在有当前播放歌曲时才允许操作  

## 使用方法

1. 在播放控制面板找到收藏按钮（位于定时关机按钮右侧）
2. 点击空心红心图标添加到收藏
3. 再次点击实心红心图标取消收藏
4. 切换歌曲时收藏状态会自动重置

## 调试日志

```
⭐ 加入收藏: 歌曲名
✅ 已加入收藏

💔 取消收藏: 歌曲名
✅ 已取消收藏
```

## 注意事项

⚠️ **状态管理**
- 收藏状态仅在客户端维护
- 切换歌曲时会自动重置为未收藏状态
- 未来可考虑从服务端同步收藏列表以实现持久化

⚠️ **前置条件**
- 必须选择设备
- 必须有当前播放的歌曲
- API服务必须已初始化

## 测试建议

1. ✅ 测试加入收藏功能
2. ✅ 测试取消收藏功能
3. ✅ 测试切换歌曲后状态重置
4. ✅ 测试无设备/无歌曲时的禁用状态
5. ✅ 测试网络错误处理

