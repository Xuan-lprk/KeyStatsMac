# KeyStatsMac 技术文档

本目录保存深入技术资料、设计和历史实施记录。当前源码、[`PROJECT.md`](../PROJECT.md) 与 [`AGENTS.md`](../AGENTS.md) 优先于历史文档；标记为 Historical 或 Superseded 的内容可能包含旧 identifier、旧路径和已经删除的架构，不应直接作为当前操作指令。

## 状态说明

- **Current**：当前仍可作为实现或运维参考。
- **Implemented**：方案已落地，文档主要用于解释设计背景。
- **Deferred**：代码或设计仍保留，但当前不是开发重点。
- **Historical**：历史记录；使用前必须核对当前源码。
- **Superseded**：已被后续实现替代，不应按原步骤执行。

## 当前入口

- [当前开发交接结论](../PROJECT.md#2026-10-26开发交接快照菜单视觉未通过) — **Handoff / 暂停**：当前菜单视觉未通过，用户授权提交并推送供其他 AI 分析；不代表定稿或发布，不自行继续试验。
- [机械特写与数据阵列](../PROJECT.md#2026-10-26菜单机械特写与五列数据阵列视觉未通过已暂停) — **Implemented / 视觉未通过**：384pt 宽，静态机械局部、五列键位和全宽鼠标短行；不在 Popover 创建 SceneKit／Metal。
- [PROJECT.md](../PROJECT.md) — **Current**：产品状态、upstream differences 和阶段性决策。
- [AGENTS.md](../AGENTS.md) — **Current**：AI Agent 的架构上下文、范围和安全规则。
- [正式 Growth Keyboard](../PROJECT.md#正式-growth-keyboard已接线仍在工作区) — **Implemented / 收尾中**：Mac / 机械 3D、77 键、正式累计数据链、两模型共享 Replay、固定模型试打与按需渲染。
- [启动与发布边界](../PROJECT.md#标识符签名与发布边界) — **Current**：普通 Debug 的 Helper/cdhash/LaunchAgent/旧权限迁移副作用、自有仓库更新地址、未配置签名时的手动 Releases 入口及未完成的发布验收。
- [Debug GUI 验收参数及验证范围](../PROJECT.md#debug-gui-验收启动参数) — **Implemented / 待真机验收**：仅 Debug 的显式参数；不是只读/离线沙盒，不替代启动批准。
- [当前键盘状态](../PROJECT.md#当前交付状态) — **Implemented / 收尾中**：新机械模型及 Usage 配色已认可并接入统一窗口；旧失败造型保留为历史，不加入本轮提交。
- [Keyboard 窗口布局整理](../PROJECT.md#2026-10-25keyboard-窗口布局整理) — **Implemented / 待用户视觉确认**：顶部模型与模式切换，累计数据层级，底部回放时间轴和键位详情卡片；复用现有模型与数据链。
- [菜单默认全部展示](../PROJECT.md#2026-10-26菜单默认全部展示待视觉验收) — **Implemented / 视觉未验收**：取消明细／键位／趋势折叠，保留图表控件与成长键盘入口；225 项测试、Debug 构建和同源隔离原生检查通过。
- [十秒速览菜单候选](../PROJECT.md#2026-10-25十秒速览菜单候选) — **Implemented / 视觉未验收**：历史折叠候选，用户因额外点击而否定，已由默认全部展示版替代。
- [日常速览候选](../PROJECT.md#2026-10-25日常速览候选视觉待重新讨论) — **Implemented / 视觉未验收**：双主指标、点击明细展开与 Top 5。用户认为与旧版过于相似，后续先确认新的整页构图；对话草图尚未集成。
- [菜单栏统计面板原生样式](../PROJECT.md#2026-10-25菜单栏统计面板原生样式) — **Implemented / 待用户视觉确认**：系统材质、今日统计层级、两排历史控件；正式截图、图表切换及 Keyboard 入口已检查，深浅色与弹窗生命周期另有同源隔离记录，屏幕边缘位置/外部关闭仍待用户确认。
- [交接提交范围](../PROJECT.md#当前待提交工作区与建议分组) — **Handoff**：35 个正式文件、4 份主文档，保留启动策略审查边界；未跟踪原型和本地构建产物排除，当前提交状态以 Git 为准。
- [自有更新签名配置](../PROJECT.md#自有更新签名配置) — **Pending**：生成公钥、私钥保护与现有 CI Secret 的配置说明；公钥已由用户提供并接入，尚未配置 CI 私钥或启用 App 内更新。
- [同步协议 v1](../contracts/sync/v1/README.md) — **Current / Deferred**：跨平台 E2EE 同步契约。
- [Sync Worker](../services/sync-worker/README.md) — **Current / Deferred**：Cloudflare Worker、迁移和验证入口。

## macOS 架构与历史审查

当前主项目的输入链路仍为 Helper / listen-only EventTap → XPC → RemoteEventProcessor → StatsManager；没有恢复主 App InputMonitor。正式键盘显示链路为 StatsManager display history → cumulative snapshot → PhysicalKeyMapping → KeyboardUsageProgress → Mac / 机械 3D renderer（保留 2.5D 实现）。两条链路不以 prototype 的 plist reader 相连。

正式 3D 的入口为 `GrowthKeyboardViewController`，数据适配为 `GrowthKeyboardPresentation`，回放为 `GrowthPlaybackDriver`，场景为 `GrowthKeyboard3DScene` / `MechanicalKeyboardScene`，缓存为 `GrowthKeyboard3DRenderer`。布局、字形和 Palette 来自 `EditorialKeyboardRenderer.sceneLayout`，没有正式源码对 Prototypes 的反向依赖。具体文件职责和当前验收缺口集中维护在 PROJECT，不把多个历史实验说明当成主项目实现状态。

- [macOS KPS/CPS 实现审查](reviews/2026-04-06-macos-kps-cps-review.md) — **Historical / Superseded**：基于旧 `InputMonitor` 架构，结论需对照当前 Helper/XPC/`StatsManager` 复核。
- [左右修饰键 Heatmap 计划](superpowers/plans/2026-04-07-left-right-modifier-heatmap.md) — **Implemented / Historical**：当前实现已保留左右修饰键和旧数据兼容。

## Helper / XPC / Release

- [Accessibility Helper Split 设计](superpowers/specs/2026-04-20-accessibility-helper-split-design.md) — **Implemented / Historical**：解释 Helper 拆分动机；identifier 和签名描述属于 upstream 历史状态。
- [Accessibility Helper Split 实施计划](superpowers/plans/2026-04-20-accessibility-helper-split.md) — **Implemented / Historical**：步骤、路径和中间架构不代表当前源码。
- [Helper Xcode 配置说明](superpowers/plans/2026-04-22-helper-xcode-setup.md) — **Superseded / Historical**：保留 synchronized group 和 target 配置背景；旧 identifier 与 ad-hoc Debug 签名说明已失效。
- [Helper 首发发布说明模板](superpowers/plans/2026-04-24-helper-release-notes-template.md) — **Historical**：仅供首次引入 Helper 的发布记录参考。
- [Vendored Helper 实施计划](superpowers/plans/2026-04-28-vendored-helper.md) — **Implemented / Release reference**：当前 release tooling 仍使用 vendored Helper；以文档顶部 implementation note 和 `scripts/` 实现为准。

正式发布前还必须重新验证 Developer ID、notarization、Sparkle feed、vendored Helper 签名和 TCC 升级连续性；不要把历史发布计划当作已完成的 KeyStatsMac 发布流程。

## Windows

- [Windows i18n 设计](superpowers/specs/2026-04-29-windows-i18n-design.md) — **Implemented / Historical**。
- [Windows i18n 实施计划](superpowers/plans/2026-04-29-windows-i18n.md) — **Implemented / Historical**。
- [Windows 项目说明](../KeyStats.Windows/README.md) — **Current / Deferred**。

## E2EE Sync

- [E2EE Sync 设计](superpowers/specs/2026-07-13-e2ee-sync-design.md) — **Implemented / Deferred**：本地实现存在，真实 staging/production 验证仍是发布门槛。
- [E2EE Sync 实施计划](superpowers/plans/2026-07-13-e2ee-sync.md) — **Implemented / Deferred**：记录跨 macOS、Windows、Worker 和契约的交付状态。

## 历史文档维护规则

- 不为匹配当前代码而重写历史方案中的旧 identifier、旧文件名或实验步骤。
- 发现历史文档与当前实现不一致时，优先更新本索引的状态说明，而不是抹去演进记录。
- 新增长期有效的技术文档时，在本索引登记用途和状态，避免与 README、PROJECT 或 AGENTS 重复。
- 当前测试与 Debug build 日志、历史验证、离屏 QA、GUI 与能耗边界分别记录在 [PROJECT 的测试说明](../PROJECT.md#测试与当前验证)。本地日志与生成图不进入源码提交。
