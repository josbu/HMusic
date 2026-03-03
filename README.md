# HMusic - 智能音乐播放器 🎵

> 一款支持小米 AI 音箱的音乐播放器，**双模式支持**：xiaomusic 服务端模式 + 小米 IoT 直连模式

[![Release](https://img.shields.io/github/v/release/hpcll/HMusic?label=版本)](https://github.com/hpcll/HMusic/releases)

## 🚀 v2.3.0 重点更新

- 播放链路稳定性大幅提升，直连模式与 xiaomusic 模式行为更一致。
- 新增外部歌单导入与平台归一化，跨平台歌曲解析更稳。
- 新增并增强 `pushUrl`、`getPlayerStatus` 等联动能力。
- 修复自动下一首、切歌竞态、进度同步、通知栏控制等关键问题。
- 修复 iOS 导入 LX 脚本闪退与 OH2P 设备进度/seek 异常问题。
- 音源策略更新：网易默认直连，QQ/酷我默认走代理（QQ 直连仅实验开关）。
- 产物发布升级：Android 提供通用包 + 三架构包，iOS 提供 unsigned 自签包。

> ⚠️ **重要建议（xiaomusic 用户）**  
> 为保证 HMusic v2.3.0 功能完整与稳定，建议将 xiaomusic 服务端升级到 **v0.4.23 或更高版本**。

## 📱 下载安装

从 [Releases](https://github.com/hpcll/HMusic/releases) 下载最新版本：

| 平台 | 文件 | 说明 |
|------|------|------|
| 🤖 Android 通用版 | `HMusic-v2.3.0-android-universal.apk` | 推荐，兼容所有设备 |
| 🤖 Android arm64 | `HMusic-v2.3.0-android-arm64-v8a.apk` | 现代手机，体积更小 |
| 🤖 Android arm32 | `HMusic-v2.3.0-android-armeabi-v7a.apk` | 老旧设备 |
| 🍎 iOS | `HMusic-v2.3.0-ios-unsigned.ipa` | 需自签名安装 |

## 🎯 两种模式

| | 📱 直连模式 | 🖥️ xiaomusic 模式 |
|---|---|---|
| **适合人群** | 普通用户，开箱即用 | 有 NAS/服务器的用户 |
| **需要** | 小米账号 | 部署 [xiaomusic](https://github.com/hanxi/xiaomusic) |
| **功能** | 音乐搜索、播放、音量控制 | 完整功能（本地音乐库、播放列表、进度控制） |

## ⚡ 快速开始

### 直连模式（推荐新手）

1. 打开应用 → 选择 **直连模式**
2. 登录小米账号 → 选择音箱设备
3. 搜索音乐 → 播放！

> ⚠️ **移动数据用户**：需配置音频代理，详见 [代理部署指南](cloudflare-worker/README.md)

### xiaomusic 模式

1. 先部署 [xiaomusic 服务端](https://github.com/hanxi/xiaomusic)
2. 建议升级到 **v0.4.23+**（与 HMusic v2.3.0 联动更完整）
3. 可参考官方文档站：[https://xdocs.hanxi.cc/](https://xdocs.hanxi.cc/)
4. 打开应用 → 选择 **xiaomusic 模式**
5. 输入服务器地址和认证信息

## 📚 文档

- [常见问题 FAQ](docs/FAQ.md)
- [代理部署指南](cloudflare-worker/README.md)
- [更新日志](CHANGELOG.md)
- [开发者文档](ARCHITECTURE.md)

---

## 🙏 致谢

感谢 [xiaomusic](https://github.com/hanxi/xiaomusic) 项目及其开发者 [@hanxi](https://github.com/hanxi)，HMusic 的 xiaomusic 模式基于该项目实现，直连模式的小米 IoT API 也参考了相关实现。

---

## 💬 交流群

欢迎加入 HMusic 用户交流群，一起讨论使用问题和功能建议～

<p align="center">
  <img src="docs/donate/群聊.JPG" alt="微信群二维码" width="250" />
</p>

<p align="center">
  <sub>⚠️ 群二维码为动态有效期，失效请提 <a href="https://github.com/hpcll/HMusic/issues">Issue</a></sub>
</p>

---

## ☕ 请作者喝杯咖啡

如果 HMusic 对你有帮助，欢迎请作者喝杯咖啡～ 你的支持是我持续开发的动力！

<p align="center">
  <img src="docs/donate/wechat.jpg" alt="微信赞赏码" width="250" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/donate/alipay.jpg" alt="支付宝收款码" width="250" />
</p>

<p align="center">
  <b>微信赞赏</b>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <b>支付宝</b>
</p>

---

## 📜 许可证

[AGPL-3.0](LICENSE) - 开源免费，商业使用需授权
