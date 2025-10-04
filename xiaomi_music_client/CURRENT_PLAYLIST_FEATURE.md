# 当前播放列表显示功能

## 功能说明

实现了在控制面板页面显示当前播放列表的功能，解决了点击"全部列表"播放后，无法在控制页面看到当前播放列表和正在播放歌曲的问题。

## 实现内容

### 1. 添加 API 接口 (`lib/data/services/music_api_service.dart`)

```dart
// 获取当前播放列表
Future<Map<String, dynamic>> getCurrentPlaylist({String? did}) async {
  final response = await _client.get(
    '/curplaylist',
    queryParameters: did != null ? {'did': did} : null,
  );
  return response.data as Map<String, dynamic>;
}
```

使用图片中提供的 `curplaylist?did=703835710` 接口。

### 2. 更新播放状态 (`lib/presentation/providers/playback_provider.dart`)

- **PlaybackState 新增字段**：
  ```dart
  final List<String> currentPlaylistSongs; // 🎵 当前播放列表的所有歌曲
  ```

- **refreshStatus 方法增强**：
  - 在每次刷新播放状态时，同时获取当前播放列表
  - 自动将播放列表信息更新到状态中
  - 即使获取失败也不影响原有功能

### 3. 控制面板显示 (`lib/presentation/pages/control_panel_page.dart`)

- **新增 `_buildCurrentPlaylist` 方法**：
  - 显示当前播放列表的所有歌曲
  - 高亮显示正在播放的歌曲（带播放图标）
  - 显示歌曲序号和总数
  - 列表最大高度300px，超出可滚动
  - 美观的卡片设计，与现有UI风格一致

## 功能特点

1. **实时同步**：播放状态刷新时自动更新播放列表
2. **视觉高亮**：当前播放歌曲带有：
   - 主题色背景
   - 播放图标
   - 声波图标
   - 粗体文字
3. **智能显示**：只在有播放列表时显示，不影响其他界面
4. **性能优化**：列表采用 ListView.builder，支持大量歌曲
5. **容错处理**：API 调用失败不影响原有播放功能

## 使用效果

当用户点击"全部列表"或任何播放列表后：
- 控制面板会自动显示当前播放列表卡片
- 卡片显示列表中所有歌曲
- 正在播放的歌曲会被高亮显示
- 用户可以清楚看到当前在列表的哪个位置

## API 依赖

依赖后端 `/curplaylist?did=<device_id>` 接口，预期返回格式：
```json
{
  "cur_playlist": ["歌曲1", "歌曲2", "歌曲3", ...]
}
```

## 测试建议

1. 点击任意播放列表的"播放全部"按钮
2. 返回控制面板查看是否显示播放列表卡片
3. 检查当前播放歌曲是否被正确高亮
4. 切换歌曲后检查高亮是否跟随更新



