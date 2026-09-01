# KeyStatsMac

KeyStatsMac 是一款隐私优先、低功耗的 macOS 键盘与鼠标交互统计工具。它通过独立 Helper 采集输入事件，并在本地生成按键、点击、移动、滚动、速率、历史和分应用聚合统计。

KeyStatsMac 不是 keylogger：它不记录输入文本、按键顺序、鼠标点击坐标、完整鼠标轨迹或用户内容。

## 当前能力

- 键盘总量、每键累计和组合键统计。
- 鼠标点击、移动距离和滚动距离。
- KPS / CPS、每日历史和长期汇总。
- 分应用聚合统计与键位分布。
- Keyboard Heatmap。
- 基于公开 scroll phase 的 Scroll Session 累计统计。
- 可选的端到端加密多设备同步基础。

## 开发

macOS 主工程要求 macOS 13+，使用 Swift、AppKit 和部分 SwiftUI：

```bash
swift test

xcodebuild \
  -project KeyStats.xcodeproj \
  -scheme KeyStats \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

涉及全局输入采集的真机运行需要为 `KeyStatsHelper` 授予辅助功能权限。构建成功不能替代 Helper、XPC 和 TCC 的真机验证。

## 仓库导航

- [`PROJECT.md`](PROJECT.md)：当前产品状态、与 upstream 的差异和阶段性技术决策。
- [`AGENTS.md`](AGENTS.md)：面向 AI coding agent 的开发约束。
- [`docs/README.md`](docs/README.md)：技术文档索引及状态说明。
- [`KeyStats.Windows/README.md`](KeyStats.Windows/README.md)：仓库中保留的 Windows 版本说明。
- [`contracts/sync/v1/README.md`](contracts/sync/v1/README.md)：多设备同步协议契约。
- [`services/sync-worker/README.md`](services/sync-worker/README.md)：同步 Worker 说明。

## Upstream 与许可

本项目基于 [`debugtheworldbot/keyStats`](https://github.com/debugtheworldbot/keyStats) 继续开发。许可信息见 [`LICENSE`](LICENSE) 和 [`LICENSE-MIT`](LICENSE-MIT)。
