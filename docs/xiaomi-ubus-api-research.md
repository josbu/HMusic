# 小米音箱 ubus API 逆向研究报告

> 研究日期：2026-03-01
>
> 研究目的：梳理小米音箱 mediaplayer ubus API 的完整能力，为 HMusic 直连模式功能优化提供依据。

## 一、研究来源

| 项目 | 地址 | 价值 |
|------|------|------|
| **xiaoai-crack** | `birdsofsummer/xiaoai-crack` | ⭐⭐⭐ 固件逆向，获得完整 ubus 方法列表 |
| **MiService (fork)** | `yihong0618/MiService` | ⭐⭐⭐ xiaomusic 依赖库，核心 MINA API |
| **MiWifiSpeaker** | `PRO-2684/MiWifiSpeaker` | ⭐⭐ 发现 seek/loop/shutdown 等新 API |
| **micli** | `WangNingkai/micli` | ⭐⭐ Go 实现，MIoT Action 通道 + HardwareCommandDict |
| **hass-xiaomi-miot** | `al-one/hass-xiaomi-miot` | ⭐⭐ HA 集成，验证 play_song_detail 数据结构 |
| **xiaoai-music-bridge** | `ttglad/xiaoai-music-bridge` | ⭐ 开放平台 Skill 回调（不同技术路线） |
| **xiaomusic** | `yihong0618/xiaomusic` | ⭐⭐⭐ 参考其对不可靠 API 的应对策略 |

## 二、API 端点

### 2.1 MINA Cloud API（HMusic 直连模式使用）

```
基址:     https://api2.mina.mi.com
设备列表:  GET  /admin/v2/device_list?master=0
ubus控制:  POST /remote/ubus
认证方式:  Cookie: serviceToken=xxx; userId=xxx
SID:      micoapi
```

### 2.2 MIoT Cloud API（另一条控制通道，HMusic 未使用）

```
基址:     https://api.io.mi.com/app
属性读取:  POST /miotspec/prop/get
属性设置:  POST /miotspec/prop/set
动作执行:  POST /miotspec/action
认证方式:  HMAC-SHA256 签名（ssecurity + nonce）
SID:      xiaomiio
```

### 2.3 对话记录 API（用于监听语音指令）

```
基址:     https://userprofile.mina.mi.com
对话列表:  GET  /device_profile/v2/conversation?source=dialogu&hardware={hw}&timestamp={ts}&limit={n}
认证方式:  Cookie: serviceToken=xxx; userId=xxx; deviceId=xxx
```

## 三、mediaplayer ubus 方法完整列表

> 来源：xiaoai-crack 项目通过 `ubus list mediaplayer -v` 获取

### 3.1 HMusic 已使用的方法

| 方法 | 参数 | HMusic 用途 |
|------|------|------------|
| `player_play_url` | `{url, type, domain, media, src, id, duration}` | 播放音乐 URL |
| `player_play_music` | `{music, startOffset, loadMoreOffset, media, src, id, duration}` | 特定设备播放（OH2P/L05B等） |
| `player_play_operation` | `{media, action}` | 播放(`play`)/暂停(`pause`)/停止(`stop`) |
| `player_get_play_status` | `{media}` 或 `{}` | 获取播放状态 |
| `player_set_volume` | `{volume, media}` | 设置音量 |

### 3.2 HMusic 未使用但有价值的方法 ⭐

| 方法 | 参数 | 用途 | 优先级 |
|------|------|------|--------|
| **`player_set_positon`** | `{position(ms), media}` | **进度拖拽/Seek** | 🔴 高 |
| **`player_play_operation`** (next) | `{action:"next", media}` | **设备端下一首** | 🔴 高 |
| **`player_play_operation`** (prev) | `{action:"prev", media}` | **设备端上一首** | 🔴 高 |
| **`player_play_operation`** (toggle) | `{action:"toggle", media}` | **切换播放/暂停** | 🟡 中 |
| **`player_set_loop`** | `{type(0/1/3), media}` | **循环模式** | 🟡 中 |
| **`player_get_context`** | `{}` | **获取播放上下文（待验证）** | 🟡 中 |
| **`player_play_status`** | `{}` | **另一种状态查询（待验证）** | 🟡 中 |
| `set_playrate` | `{rate}` | 变速播放（如 "1.5"） | 🟢 低 |
| `player_play_index` | `{index, media}` | 按索引播放队列歌曲 | 🟢 低 |
| `get_media_volume` | `{}` | 独立音量查询 | 🟢 低 |
| `player_set_continuous_volume` | `{volume, media}` | 实时音量（拖动滑块） | 🟢 低 |
| `player_modify_volume` | `{isVolumeUp, value}` | 相对音量调节 | 🟢 低 |
| `player_set_shutdown_timer` | `{action, hour, minute, second, media}` | 睡眠定时器 | 🟢 低 |
| `get_shutdown_timer` | `{}` | 获取定时器状态 | 🟢 低 |

> ⚠️ **注意**：`player_set_positon` 是小米固件的原始拼写（少了一个 `i`），这不是笔误！

### 3.3 其他 mediaplayer 方法（参考用）

| 方法 | 参数 | 说明 |
|------|------|------|
| `player_wakeup` | `{action, source}` | 唤醒播放器 |
| `player_play_filepath` | `{name, path, nameBase64, pathBase64}` | 播放本地文件 |
| `player_play_private_fm` | `{}` | 私人FM |
| `player_get_latest_playlist` | `{}` | 最近播放列表 |
| `player_play_album_playlist` | `{type, id, startOffset, media}` | 按专辑/歌单播放 |
| `player_play_alarm_reminder` | `{type, reminder, volume, timeReminder, query}` | 闹钟提醒 |
| `media_control` | `{player, action, volume}` | 媒体控制 |
| `player_reset` | `{}` | 重置播放器 |
| `player_retore_last_volume` | `{}` | 恢复上次音量 |
| `set_voip_status` | `{voip_status}` | VoIP 状态 |
| `set_player_quiet` | `{quiet}` | 安静模式 |
| `notify_mdplay_status` | `{status, type}` | 通知播放状态 |
| `player_aux_operation` | `{aux_operation}` | 辅助操作 |
| `test` | `{}` | 测试 |

### 3.4 mibrain ubus 方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `text_to_speech` | `{text, caller, vendor, codec, volume, save, play}` | TTS 语音合成 |
| `nlp_result_get` | `{}` | 获取 NLP 结果（pull_ask） |
| `ai_service` | `{bypass, caller, ...}` | AI 服务调用 |
| `vendor_switch` | `{vendor_name}` | 切换供应商 |
| `vendor_who` | `{}` | 查询当前供应商 |

### 3.5 volctl ubus 方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `setvol` | `{callername, softnode, vol}` | 设置音量 |
| `getvol` | `{callername, softnode}` | 获取音量 |
| `volup` / `voldown` | `{callername, softnode}` | 音量增减 |
| `nightmode` | `{callername, val}` | 夜间模式 |

## 四、`player_get_play_status` 返回数据结构

### 4.1 完整响应

```json
{
  "code": 0,
  "data": {
    "code": 0,
    "info": "<JSON字符串，需要二次解析>"
  }
}
```

### 4.2 info 解析后结构

```json
{
  "status": 1,
  "volume": 50,
  "media_type": 3,
  "loop_type": 1,
  "play_song_detail": {
    "audio_id": "xxx",
    "global_id": "xxx",
    "title": "歌曲名",
    "artist": "歌手名",
    "album": "专辑名",
    "cover": "封面URL",
    "duration": 240000,
    "position": 45000
  }
}
```

### 4.3 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | int | 0=空闲, 1=播放中, 2=暂停 |
| `volume` | int | 音量 0-100 |
| `media_type` | int | 3=音乐, 13=视频 |
| `loop_type` | int | 0=单曲循环, 1=列表循环, 3=随机播放 |
| `play_song_detail` | object? | 播放详情（**部分设备返回 null**） |
| `play_song_detail.position` | int | 当前位置（毫秒） |
| `play_song_detail.duration` | int | 总时长（毫秒） |

### 4.4 各设备返回情况

| 设备 | status 可靠性 | play_song_detail | position/duration |
|------|-------------|------------------|-------------------|
| L05B | ✅ 可靠 | ✅ 有值 | ✅ 有值 |
| LX05 | ✅ 可靠 | ✅ 有值 | ✅ 有值 |
| **OH2P** | ❌ 暂停后仍返回1 | ❌ 始终 null | ❌ 无 |
| wifispeaker.v3 | ✅ 可靠 | ✅ 有值 | ✅ 有值 |

## 五、`player_play_music` 完整参数

HMusic 当前只使用了 `music` 和 `startaudioid` 两个参数，但固件实际支持更多：

```
{
  "music": "<JSON字符串>",
  "startaudioid": "<音频ID>",
  "startOffset": <int>,          // ← 起始偏移（未使用）
  "loadMoreOffset": <int>,       // ← 加载更多偏移（未使用）
  "media": "app_ios",            // ← 媒体来源（未使用）
  "src": "<来源标识>",            // ← 来源（未使用）
  "id": "<ID>",                  // ← ID（未使用）
  "duration": <int>              // ← ⭐ 歌曲时长（未使用！）
}
```

同样，`player_play_url` 也支持 `duration` 参数：

```
{
  "url": "<音频URL>",
  "type": 2,
  "media": "app_ios",
  "domain": "<域名>",            // ← 未使用
  "src": "<来源>",               // ← 未使用
  "id": "<ID>",                  // ← 未使用
  "duration": <int>              // ← ⭐ 歌曲时长（未使用！）
}
```

> **假设**：如果在播放时传入 `duration` 参数，设备可能会在 `player_get_play_status` 中返回更完整的 `play_song_detail`。这一假设需要在 OH2P 上实验验证。

## 六、`player_set_loop` 循环类型

| type 值 | 含义 | media 值 |
|---------|------|----------|
| 0 | 单曲循环 | `"app_android"` 或 `"common"` |
| 1 | 列表循环/顺序播放 | 同上 |
| 3 | 随机播放 | 同上 |

> miservice-fork 使用 `media: "common"`，MiWifiSpeaker 使用 `media: "app_android"`

## 七、MIoT Action 通道（备用控制路径）

通过 IOService（sid=xiaomiio）的 MIoT 规范接口，可以用另一种方式控制音箱。

### 7.1 设备型号 → MIoT Action ID 映射

```
设备    TTS      唤醒     执行指令
LX06   siid5-a1  siid5-a3  siid5-a5
L05B   siid5-a3  siid5-a1  siid5-a4
LX01   siid5-a1  siid5-a2  siid5-a5
L06A   siid5-a1  siid5-a2  siid5-a5
LX04   siid5-a1  siid5-a2  siid5-a4
X08E   siid7-a3  siid7-a1  siid7-a4
X08C   siid3-a1  siid3-a2  siid3-a5
LX05   siid5-a1  siid5-a3  siid5-a5
```

### 7.2 调用方式

```
POST https://api.io.mi.com/app/miotspec/action
Body (signed):
{
  "did": "<设备DID>",
  "siid": 5,
  "aiid": 5,
  "in": ["播放音乐"]   // 参数列表
}
```

> **注意**：IOService 需要额外的 HMAC-SHA256 签名机制，与 MINA API 的简单 Cookie 认证不同。

## 八、需要使用 player_play_music 的设备型号

```
LX04, LX05, L05B, L05C, L06, L06A,
X08A, X10A, X08C, X08E, X8F,
X4B, OH2, OH2P, X6A
```

> 已在 HMusic 的 `MiHardwareDetector` 类中维护

## 九、xiaomusic 的应对策略（参考）

xiaomusic 对 API 不可靠性的处理方式：

| 问题 | xiaomusic 方案 | HMusic 方案 |
|------|--------------|------------|
| 进度查询不可靠 | 纯本地计时：`time.time() - start_time - paused_time` | 混合方案：优先用 API 数据，fallback 到本地计时 |
| 播放状态不可靠 | 纯本地状态：`self.is_playing` 只由本地操作修改 | 非对称信任：信任"停止"，不信任"播放"覆盖本地暂停 |
| 自动下一首 | 本地定时器：基于 duration 的倒计时 | 双重机制：API 检测 + 备用定时器 |
| 歌曲切换检测 | 本地管理，不依赖 API | audio_id 变化检测 + 本地管理 |

## 十、待验证的实验项

| # | 实验内容 | 目的 | 设备 |
|---|---------|------|------|
| 1 | 调用 `player_play_status`（不是 get） | 看是否返回不同格式的状态数据 | OH2P |
| 2 | 调用 `player_get_context` | 看是否返回播放上下文/进度信息 | OH2P |
| 3 | `player_play_music` 传入 `duration` 参数 | 看是否能让 `play_song_detail` 不再为 null | OH2P |
| 4 | `player_play_url` 传入 `duration` 参数 | 同上 | OH2P |
| 5 | 调用 `player_set_positon` | 验证 seek 功能是否在各设备上可用 | OH2P, L05B |
| 6 | 调用 `player_play_operation` + `next`/`prev` | 验证设备端切歌 | OH2P, L05B |
| 7 | 查询 OH2P 的 MIoT Spec | 看是否有播放进度相关的属性 | OH2P |

---

*文档结束。后续实验结果将更新到此文档。*
