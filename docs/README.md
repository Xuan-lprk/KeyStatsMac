# KeyStatsMac 技术文档

本目录保存深入技术资料、设计和历史实施记录。当前源码、[`PROJECT.md`](../PROJECT.md) 与 [`AGENTS.md`](../AGENTS.md) 优先于历史文档；标记为 Historical 或 Superseded 的内容可能包含旧 identifier、旧路径和已经删除的架构，不应直接作为当前操作指令。

## 状态说明

- **Current**：当前仍可作为实现或运维参考。
- **Implemented**：方案已落地，文档主要用于解释设计背景。
- **Deferred**：代码或设计仍保留，但当前不是开发重点。
- **Historical**：历史记录；使用前必须核对当前源码。
- **Superseded**：已被后续实现替代，不应按原步骤执行。

## 当前入口

- [PROJECT.md](../PROJECT.md) — **Current**：产品状态、upstream differences 和阶段性决策。
- [AGENTS.md](../AGENTS.md) — **Current**：AI Agent 的架构上下文、范围和安全规则。
- [同步协议 v1](../contracts/sync/v1/README.md) — **Current / Deferred**：跨平台 E2EE 同步契约。
- [Sync Worker](../services/sync-worker/README.md) — **Current / Deferred**：Cloudflare Worker、迁移和验证入口。

## macOS 架构与历史审查

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
