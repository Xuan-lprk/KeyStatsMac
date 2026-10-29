# KeyStatsMac

KeyStatsMac 是一款隐私优先、低功耗的 macOS 键盘与鼠标交互统计工具。它通过独立 Helper 采集输入事件，并在本地生成按键、点击、移动、滚动、速率、历史和分应用聚合统计。

KeyStatsMac 不是 keylogger：它不记录输入文本、按键顺序、鼠标点击坐标、完整鼠标轨迹或用户内容。

## 当前能力

- 键盘总量、每键累计和组合键统计。
- 鼠标点击、移动距离和滚动距离。
- KPS / CPS、每日历史和长期汇总。
- 菜单栏统计面板：顶部实验性 Input Pulse 用双层波形展示实时 KPS／CPS，并在聚合输入更新时触发有界键帽光点；仅显示期间采样，约 12 秒速率历史只存内存，关闭即清理，不记录键名或输入顺序。下方保留今日总量、最多 15 个常用键、7/30 天趋势及鼠标明细，成长键盘改为轻量文字入口。该候选尚未进行视觉、构建和性能验收。
- 分应用聚合统计与键位分布。
- App Detail 中的 Heatmap / 完整 Key Breakdown。
- 正式 77 键 Growth Keyboard：Mac / 机械 3D 模型，共享 Usage 配色、Today / 历史日期、Day N、时间轴和精确键位次数；Editorial 2.5D 实现保留。
- Keyboard 窗口顶部切换 Mac / 机械和“成长统计 / 试打”，底部集中放日期回放、时间轴与键位详情。试打通过鼠标或窗口内实体按键体验下沉回弹，使用固定高度，虚拟点击不写统计。
- Mac / 机械均支持 Play from Day 1：按每日累计快照回放，等当前图像就绪后再推进日期，到 Today 停止；暂停、切换模型或失焦会停止播放。
- App Detail 中的 Interaction Profile：按当前日期范围比较各 App 的 Keyboard / Pointer / Scroll 相对排名。
- 基于公开 scroll phase 的 Scroll Session 累计统计。
- 独立的亮度、音量、播放等 System Media Key 聚合语义，不将它们猜成普通 F 键。
- Analytics consent 后端：默认关闭，未同意时不初始化 PostHog；正式 Settings 开关和 Privacy Center 尚未实现。
- 可选的端到端加密多设备同步基础。

Growth 使用正式 StatsManager 显示查询，包含未落盘 Today 和既有 Sync 聚合语义。它不读取 Demo 的历史文件。Today 在打开、获得焦点、回到 Today 或手动刷新时更新，不逐键重绘；3D 使用按需静态渲染和最多三张缓存，隐藏、失焦或关闭时取消待执行工作。

当前机械造型与配色已获用户认可；菜单整体视觉未通过。旧全局 Heatmap 分页已移除，per-app Heatmap 保留。上述能力属于开发交接快照，不表示已发布；完整可访问性、Reduce Motion 和能耗仍有待验收。历史失败实验保留本地，不加入本轮正式提交。交接结论与继续开发边界见 [PROJECT](PROJECT.md)。

## 开发

macOS 主工程要求 macOS 13+，使用 Swift、AppKit 和部分 SwiftUI：

```bash
swift test

xcodebuild \
  -project KeyStats.xcodeproj \
  -scheme KeyStats \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/build/Development/DerivedData" \
  build
```

涉及全局输入采集的真机运行需要为 `KeyStatsHelper` 授予辅助功能权限。构建成功不能替代 Helper、XPC 和 TCC 的真机验证。

上述命令只执行 build，不执行 Xcode Run；App 输出路径由所用 DerivedData 决定，不按显示名判断哪份 App 最新。普通 Debug 启动仍会进入 Helper 安装 / cdhash 比较、LaunchAgent 管理和旧权限迁移流程；Sparkle 另受更新签名配置限制。

Debug 只有显式传入 `--debug-gui-acceptance` 才启用 GUI 验收模式；Release 忽略此参数。该模式跳过 Helper 安装替换、LaunchAgent 管理、旧 Accessibility 迁移/reset，且不初始化 Sparkle；仅连接已有 Helper，协议不兼容或无权限时不修复系统状态。**它不是只读或离线沙盒**：已有 Helper 兼容且获授权时仍可采集，正式数据持久化、Analytics consent 和 Sync 行为仍保留。实际启动需单独批准，不应同时运行两份主 App。详见 [PROJECT 的启动与发布边界](PROJECT.md#标识符签名与发布边界)。

更新地址及 GitHub 入口已改到 `Xuan-lprk/KeyStatsMac`。已接入用户提供的更新公钥，自动检查和 App 内更新开关当前均关闭；不会创建 Sparkle，普通模式可手动打开 Releases 页面。密钥配置见 [PROJECT](PROJECT.md#自有更新签名配置)；自有签名、首发更新和 Helper 升级权限连续性仍待验收。当前收尾验证、日志和验收限制见 [PROJECT](PROJECT.md#测试与当前验证)。

## 仓库导航

- [`PROJECT.md`](PROJECT.md)：当前产品状态、与 upstream 的差异和阶段性技术决策。
- [`AGENTS.md`](AGENTS.md)：面向 AI coding agent 的开发约束。
- [`KeyStatsHelper/README.md`](KeyStatsHelper/README.md)：独立原生 Helper 包的构建／测试、正式 XPC 与权限边界，以及 c3502 聚合统计接入可行性。
- [`docs/README.md`](docs/README.md)：技术文档索引及状态说明。
- [`Prototypes/KeyboardAtelier/README.md`](Prototypes/KeyboardAtelier/README.md)：已提交的旧 Porcelain 原型。其他本地实验状态见 PROJECT，不属于本轮提交。
- [`KeyStats.Windows/README.md`](KeyStats.Windows/README.md)：仓库中保留的 Windows 版本说明。
- [`contracts/sync/v1/README.md`](contracts/sync/v1/README.md)：多设备同步协议契约。
- [`services/sync-worker/README.md`](services/sync-worker/README.md)：同步 Worker 说明。

## Upstream 与许可

本项目基于 [`debugtheworldbot/keyStats`](https://github.com/debugtheworldbot/keyStats) 继续开发。许可信息见 [`LICENSE`](LICENSE) 和 [`LICENSE-MIT`](LICENSE-MIT)。
