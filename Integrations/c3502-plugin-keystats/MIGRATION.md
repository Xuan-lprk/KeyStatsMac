# 从 KeyStats 原生采集到 c3502 插件

本文说明这次接入如何完成、为什么这样划分，以及目前完成到哪里。操作入口见 [README](README.md)。

## 完成度结论

当前是**已通过真实键鼠验证的本机客户端插件**。它可以独立于正式 KeyStats App 启动采集，将聚合结果交给同一 c3502 client 内的其他插件，并在关闭时回收采集进程。

它不是已经发布的 npm 包或通用安装器：`package.json` 保持 private，原生构建仍需要当前 KeyStats 仓库中的共享源码，开发工具链链接到用户自己的 c3502 checkout。插件目录不能单独复制后就认为原生构建可用。正式分发、长期运行和功耗仍待后续验收。

## 原来的链路与这次新增的链路

原有正式 App 继续运行：

```text
macOS → KeyStatsHelper → XPC → RemoteEventProcessor → StatsManager → UI / 存储
```

新增独立插件使用：

```text
macOS
  → KeyStatsC3502Collector
      EventTapController → PayloadBuilder → Aggregates
  → stdout NDJSON（5 秒聚合快照）
  → TypeScript MessageReader / Schema
  → c3502 client 通知 keystats:input:snapshot
  → 其他本机插件
```

这次迁移的是“采集能力的复用与执行边界”，不是移动或重写正式 Helper。现有 XPC 只接受被授权的主 App 身份，不能为了 Node 接入而放宽签名／UID 检查。新插件使用自己的子进程与系统权限，不冒充主 App，不占用现有 Mach service，也不安装第二份 LaunchAgent。

## 1. 复用采集代码

[build-native.sh](build-native.sh) 直接编译以下原文件，没有复制出另一套监听实现：

| KeyStats 原文件 | 在插件中的用途 |
| --- | --- |
| `KeyStatsHelper/EventTapController.swift` | listen-only CGEventTap、移动采样、tap 恢复与停止 |
| `KeyStatsHelper/PayloadBuilder.swift` | 原生进程内部的受限事件转换 |
| `KeyStatsHelper/HelperPayloadFields.swift` | 字段与既有错误码 |
| `KeyStatsHelper/ButtonRoleClassifier.swift` | 原 payload 构建所需鼠标角色逻辑 |
| `KeyStatsHelper/SystemMediaKey.swift` | 媒体键识别，排除重复／释放事件 |

插件不编译 Helper 的 XPC listener、安装路径管理、LaunchAgent 或主 App 的 StatsManager。已有 Helper 的身份、协议和签名资产保持原样。项目根目录的许可证适用于这份源码复用，见 [LICENSE](../../LICENSE)；此接入不另行重新许可这些文件。

## 2. 在原生进程内聚合，再跨进程

新增 [Aggregates.swift](native/Aggregates.swift) 实现原有 `EventPayloadSink`。它在原生内存里把输入转换为总量，再丢弃当前 payload：

- 普通按键按 keyDown 计数，忽略 auto-repeat；媒体键沿用原解析。
- 左／右／中／其他鼠标按钮分别累计。
- 移动只保留上一采样点，用于求距离；异常大跳跃不累计。
- 滚轮累计 delta 向量长度。

只跨进程发送固定白名单字段：协议版本、消息类型、按键总量、四类点击总量和两种距离。没有输入文字、键位、修饰键组合、事件时间、PID 或坐标。快照是当前采集会话从零开始的累计值，不是可相加的增量。

这里刻意没有重建 StatsManager：不实现每键历史、单独修饰键统计、校准米数或跨日持久化，因此数值语义不等同于完整 App。

## 3. 用最小本机协议连接 Swift 与 Node

选择父子进程的 stdout NDJSON，不开网络端口，也不依赖 c3502 尚未完成的远程 provider：

- 原生程序先报告状态，确认权限与 EventTap 可用后发送基线。
- 每 5 秒发送一份聚合快照。
- Node 逐行验证严格 Schema，拒绝多余字段、非法数值及过大的缓冲。
- 下游变慢时最多保留一份最新快照，不排队保存逐事件数据。
- 传输是会话内的尽力交付，无持久队列、确认、重试或断线恢复。遇错停止，由宿主显式重新启用。

[collector.ts](src/collector.ts) 管理进程启动、就绪超时、协议校验与退出。启动前和启动后发生错误都执行清理；并发 dispose 共用一个清理 Promise，等待子进程结束。温和终止无效时，2 秒后强制终止。

## 4. 按 c3502 插件契约接入

[client.ts](src/client.ts) 使用公开 `c3502/kit` 的 `defineClientPlugin`：

| c3502 契约 | 本次实现 |
| --- | --- |
| `id` / `apply` | `keystats:input`，仅 client |
| `provide` | 静态声明名称、配置 Schema、通知 Schema；不启动进程 |
| `setup` | 只有 enabled=true 时启动采集器 |
| Standard Schema | 用 Zod 同时提供运行校验和类型来源 |
| 通知 | `keystats:input:snapshot`，参数类型从同一 Schema 推导 |
| `AsyncDisposable` | 关闭管道、停止并等待原生子进程 |

当前 c3502 加载器读取模块 namespace，不自动取 default。插件因此同时提供 `id/apply/provide/setup` 命名导出和 default 导出，兼容现有实现；未修改宿主加载器。

实际演示使用公开 `createC3502Client` 和 `pluginManager.addPluginAsync`，先加载 observer，再加载采集插件。observer 从正式本机通知接口接收快照，不绕过总线直接读取 Swift 输出。

## 5. 权限排查：为什么最初全是零

首次尝试中，设备控制／辅助功能检查成功，EventTap 也创建成功，但真实输入计数一直是零。增加只输出布尔值的 `--diagnose` 后发现：

```text
accessibility = true
listenEvents = false
screenLocked = false
sessionOnConsole = true
```

本机 macOS 把旧的辅助功能权限页显示为 Device Control and Data Access，而 Input Monitoring 是另一项独立权限。两者不能当作同一开关。CLI 的权限还与实际启动宿主有关：Codex 后台运行的状态不等于 Terminal 运行的状态。

用户亲自在 Input Monitoring 中开启 Terminal 后，通过 Terminal 启动的同一插件开始收到真实按键、点击、移动和滚动。采集器已补上 `CGPreflightListenEventAccess` 检查：缺少输入监控时明确报告 `inputMonitoringDenied`，不再进入“监控成功但全零”的状态。请求权限是显式选项，不自动轮询、不重置 TCC。

这里记录的是本机实际观察，不保证其他 macOS 版本的权限归属和 UI 名称完全相同。

## 6. 验证证据与范围

2026-10-31 完成：

- 原生合成自检，覆盖排除重复按键、鼠标计数及距离聚合。
- TypeScript 插件测试，覆盖默认关闭、白名单／数值／长度校验、分帧、权限失败、进程启动失败、通知交付、关闭和启动后的失败清理。
- TypeScript 类型检查、ESLint、Vite+ 打包。
- 真实 c3502 client 接收物理键鼠增长，并在 30 秒后停止；进程检查未见采集器残留。
- 接入阶段正式 KeyStats Debug 构建、225 项核心测试通过。

原始验收日志和本机聚合统计保留在被忽略的 `build/C3502/`，上传源码不包含它们。收尾复测使用 `build/C3502Upload/`。根工程回归检查不覆盖系统权限，真实短测也不等于长期功耗验收。

## 尚未完成，也没有宣称完成的部分

- 独立安装、稳定签名／公证、跨机器权限引导、脱离 KeyStats 仓库的原生源码打包。
- Intel 真机及更多 macOS 版本的兼容验收。
- 长时间运行、睡眠唤醒、权限撤销及输入负载下的性能基线。
- 单独修饰键和正式 App 等价统计、历史持久化。
- c3502 跨机器通知、远程请求或 WebSocket 传输。

后续若目标只是让其他本机插件消费统计，下一步是接入一个实际消费场景并做长时间测试；不需要为此改写正式 App、XPC 或统计存储。
