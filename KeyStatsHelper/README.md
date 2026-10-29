# KeyStatsHelper 原生采集包

`KeyStatsHelper/` 可以作为 macOS 13+、Swift 5.9+ 的独立 SwiftPM 包构建和测试，不依赖主 App、PostHog、统计存储或 Node.js。SwiftPM 与正式 Xcode `helper` target 直接编译同一份十个 Swift 源文件，没有复制实现或更改 XPC 协议。

## 构建与测试

在 KeyStatsMac 仓库根目录运行：

```sh
swift build --package-path KeyStatsHelper \
  --scratch-path build/HelperStandalone/SwiftPM --product KeyStatsHelper

swift test --package-path KeyStatsHelper \
  --scratch-path build/HelperStandalone/SwiftPM
```

也可只取本目录，在该目录执行 `swift build` 和 `swift test`；没有外部包依赖。`Tests/` 仅使用合成 CGEvent 检查 payload 与服务契约，不创建 EventTap、不请求辅助功能权限、不连接 XPC、不运行服务入口。

新增 SwiftPM 测试文件时，同时在主工程 `PBXFileSystemSynchronizedBuildFileExceptionSet` 的 helper 排除项中列出具体相对路径；Xcode 的同步目录不会自动把整个 `Tests` 目录当作测试 target。

独立的是**源码构建和测试边界**。SwiftPM 输出的是开发用裸可执行文件，不是可直接替换已安装服务的签名 `.app`，也没有自动安装、LaunchAgent 或授权步骤。不要用 `swift run` 验证正在使用的采集服务，以免与现有 Mach service 冲突。正式 App 打包仍使用 Xcode 的 `helper` target，以及原有 vendored helper、签名和嵌入脚本。

## 职责与依赖

| 层 | 源码 | 职责 |
| --- | --- | --- |
| 进程入口 | `main.swift` | 启动原有 XPC listener 与 run loop |
| 原生采集 | `EventTapController.swift` | listen-only EventTap、移动采样、权限查询和显式权限请求 |
| 事件字段 | `PayloadBuilder.swift`、`HelperPayloadFields.swift` | 受限的内存 payload，不读取输入文本 |
| 输入语义 | `ButtonRoleClassifier.swift`、`SystemMediaKey.swift` | 鼠标逻辑按键和媒体键语义 |
| 本机通信 | `HelperXPCListener.swift`、`HelperProtocols.swift` | 签名及 UID 校验、单活动连接、XPC 转发 |
| 服务身份 | `HelperLocations.swift` | 既有 Bundle ID、Mach service、安装路径和协议版本 |
| 生命周期 | `HelperIdleSupervisor.swift` | 断开后的空闲退出 |

主 App 的 `HelperSupervisor` 继续负责安装／cdhash／LaunchAgent，`HelperXPCClient` 继续负责连接。`RemoteEventProcessor` 与 `StatsManager` 负责键名解释、距离计算和聚合持久化，不属于这个采集包。主 App 与 Helper 仍共享原有协议／字段文件，根 SwiftPM 的 `KeyStatsEventCore` 也继续直接编译现有字段与解码实现。

保持现有身份：

- 主 App：`com.xuanlprk.KeyStatsMac`
- Helper／Mach service／LaunchAgent：`com.xuanlprk.KeyStatsMac.helper`
- XPC interface version：`1`
- 安装位置：`~/Library/Application Support/KeyStatsMac/Helper/KeyStatsHelper.app`

签名校验没有放宽，仍只接受既有主 App identity、有效签名和相同用户 UID。构建本包不会运行安装器，不应据此宣称已验证 TCC 授权连续性或真实 XPC 生命周期。

## c3502 可行性核对（2026-10-28）

检查对象为用户指定的本地仓库 `/Users/quxuan/GitHub/c3502/c3502`，接口源码基线为 `e3fcba6b43c9c4c43b311a3439acea0e368cd2e2`。开始检查时已有的五份文档改动在本轮期间被其他进程提交为 `8ae48c81f66da78f6da43fe5295112b4ceef8ecf`；核对后确认该提交仅改文档，不影响下述接口实现结论。本次对 c3502 仓库保持只读。本节结论来自源码核对，不是 c3502 端到端运行结果。

**可以作为未来聚合统计的插件宿主；当前不能直接替换 Helper 的 XPC 传输。**

| 能力 | 核对结果 | 对接影响 |
| --- | --- | --- |
| 插件声明、Schema 与生命周期 | `packages/c3502-kit/src/`、`packages/c3502-client/src/client-setup-context.ts` 已有契约 | 可声明一个聚合统计客户端插件 |
| 同一实例内的通知 | `packages/c3502-system/src/context/local-event-context-provider.ts` 已有订阅与发送实现 | 可以承载已进入 Node 进程的统计通知；本身不解决 Swift → Node 的边界 |
| 远程通知／请求 | `packages/c3502-system/src/context/remote-event-context-provider.ts` 中通知为空函数、请求返回占位值 | 尚不能据此建立可靠的客户端／服务端通信 |
| 传输注册 | `packages/c3502-system/src/internal/transport-manager.ts` 目前保存注册项 | 尚未把注册项接入消息投递 |
| WebSocket 插件 | `plugins/c3502-plugin-websocket/src/server.ts` 中 `new WebSocketServer()` 未传入配置，缺少可用监听与投递链路 | 不能直接宣称 WebSocket 已可接入 |
| 数据序列化 | `packages/c3502-shared/src/types.ts` 的 `Serializable` 为数据值契约 | Swift 对象、CGEvent 和 XPC handle 需要显式转换，不能直接交给插件 |

本次没有引入 c3502 依赖、运行 Node 服务、建立新端口或增加事件转发。

推荐未来边界：

```text
EventTap → 原有 Helper → XPC → RemoteEventProcessor → StatsManager
                                                     ↓
                                        显式启用的聚合快照适配器
                                                     ↓
                                        c3502 客户端插件／通知
```

先保留原有采集链路，让适配器读取已聚合的总量／距离，避免重复实现键名、去重和持久化。未来若验证本机 Swift → Node 适配，应先用合成的聚合快照完成最小实验，再决定本机传输、校验、消息大小、节流、断开清理和显式启用方式。当前无需开发网络传输或重写 c3502 核心。

**不得直接把 Helper 原始 payload 发送给事件总线。** 键码、修饰键、事件时间和来源 PID 的连续事件可能重建输入使用顺序；移动坐标只允许在原有 XPC 内存链路用于累计距离，不得进入 c3502、日志、数据库或远程传输。新适配器应采用足够粗粒度的聚合快照，不能以逐键快照变相输出顺序。聚合的外发授权也不能由本次可行性评估推定。

若未来希望脱离主 App 独立采集，需要另外设计原生聚合层、安装宿主、鉴权和权限所有权；单独移动目录或启动此 SwiftPM 可执行文件无法完成这些工作。
