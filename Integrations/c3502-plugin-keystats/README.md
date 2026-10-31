# KeyStats 原生键鼠采集 → c3502 插件

**状态：本机验证版，真实键鼠与 c3502 通知已跑通。** 迁移过程、完成度及权限排查见 [MIGRATION.md](MIGRATION.md)。目前按当前 KeyStats 仓库布局构建，尚非脱离源码树即可安装的分发包。

这个本地客户端插件验证：c3502 能否通过插件读取 macOS 的键盘／鼠标活动。它直接编译复用 KeyStatsHelper 的五份 EventTap／payload 源码，启动独立的 `KeyStatsC3502Collector` 子进程，在原生进程内聚合后，每 5 秒发送累计快照到 c3502 **同一客户端实例**的通知总线。

不依赖正式 KeyStats App，不连接其 XPC、不安装 LaunchAgent、不替换已安装 Helper、不读写正式统计或同步数据。需要为实际启动宿主授予设备控制／辅助功能和 Input Monitoring 权限。CLI 从 Terminal 启动时，本机权限归属 Terminal；Codex 后台启动可能有不同授权结果。许可由系统管理，不会随退出自动撤销。

## 已实现的范围

- 键盘普通 keyDown（排除自动重复）及已识别的媒体键次数。
- 物理左键、右键、中键及其他鼠标按钮次数。
- 采样鼠标移动距离（屏幕 point，非校准米数），及滚轮 delta 的累计长度。
- 启动时一次全零基线，之后每 5 秒的累计快照；重启采集器从零开始。
- 严格 Schema、8 KiB 输入缓冲上限、最多一个等待发送的快照；宿主变慢时合并中间快照，不建立逐事件队列。
- 显式开启与权限失败报告；关闭插件时关闭管道、终止并等待采集器退出，必要时 2 秒后强制终止。没有自动重启或权限轮询。

本轮不实现按键名称／布局映射、单独修饰键计数、持久化、正式 StatsManager 兼容统计、网络传输或 c3502 服务端订阅。此处的计数不应当作正式 App 的完整统计替代品。

## 隐私与通信边界

```text
macOS EventTap (listen-only，复用正式实现)
→ PayloadBuilder（原生内存中）
→ Aggregates（只保留计数与距离；移动坐标只保留上一点）
→ stdout NDJSON（只含聚合字段）
→ TypeScript 严格校验
→ keystats:input:snapshot 本机通知
```

不输出文字、键码、按键顺序、坐标、来源 PID、应用列表或原始事件时间。正式 EventTap 源码仍保持约 30 Hz 移动采样；原始 payload 不进入 JS、日志、数据库或网络。此插件不提供远程 transport；示例也不加载任何网络插件。c3502 自身首次启动可能下载 SQLite 驱动，这属于宿主依赖安装，不是统计上传。示例终端／本地验收日志会显示聚合总量，不能将此扩展为输入序列日志。

## 本地构建

先在用户自己的 c3502 仓库按其规则安装依赖并构建公开包：

```sh
pnpm install --frozen-lockfile
pnpm exec vp run build
```

如果当前 checkout 缺少 now-playing 子模块，锁定安装可能失败；本轮验证使用 `pnpm install --no-frozen-lockfile --lockfile=false` 安装现有工作区依赖，没有改锁文件或 c3502 源码。不要为解决此问题删除或重写用户的子模块。

回到本目录：

```sh
# 链接既有 c3502 的公开包和工具链；路径由你提供，不硬编码进源码。
bash configure-local.sh /path/to/c3502
bash build-native.sh
node_modules/.bin/tsc --noEmit
node_modules/.bin/eslint .
node_modules/.bin/vp test
node_modules/.bin/vp pack
```

源码只通过 `c3502/kit` 和 `c3502/client` 等公开导出使用宿主。configure-local 不更改两边锁文件，不覆盖已有 node_modules。生成的 node_modules 链接、dist、原生二进制和验收数据均被 Git 忽略；换电脑后需重新配置／构建。构建脚本默认使用本机架构和 macOS 13 最低目标，现有编译器可用 `DEVELOPER_DIR` 选择。

## 直接验证真实键鼠

双击本目录 `Probe.command`，或：

```sh
node examples/probe.mjs --request-permission
```

首次没有权限时会请求一次系统提示并退出。此机 macOS 将旧的辅助功能权限页命名为 Device Control and Data Access；Terminal 启动的测试需要开启 Terminal 对应的开关，另在 Input Monitoring（输入监控）中开启 Terminal。只开启设备控制仍可能出现 EventTap 创建成功却读不到输入；采集器现在通过 `CGPreflightListenEventAccess` 独立检查并报错退出。系统要求重启宿主时按提示操作，再重新测试。不要给正式 Helper 换路径或重签名，不要开启不确定的应用条目。无权限时不自动重试。重编译若改变签名身份，可能需要重新授权。

运行期间 Mac 应解锁；30 秒内按几下键、点击和移动鼠标，观察 `C3502 received:` 后的聚合数字是否增长。30 秒后自动停止，也可 Ctrl-C。示例使用真实 `createC3502Client`、插件管理器、Schema 校验和本机通知；producer／observer 的资源由示例明确 await 清理，适配当前宿主的 dispose 行为。验收数据在根目录 `build/C3502/`，不进入正式 App 数据。

## 接入自己的 c3502 client

构建后把本包的 `/client` 加到 client 插件配置，提供：

```json
{
  "enabled": true,
  "binaryPath": "/absolute/path/to/build/C3502/KeyStatsC3502Collector",
  "requestPermission": false
}
```

也可像 `examples/probe.mjs` 那样，通过 `system.pluginManager.addPluginAsync` 加载本包的 `dist/client.mjs`。`enabled` 默认 false；只有显式启用才启动采集。其他客户端插件使用 `context.onClientNotification('keystats:input:snapshot', listener)` 读取快照。事件类型从 `SnapshotSchema` 推导，不维护第二份手写 payload 类型。

遵循 c3502 的 `defineClientPlugin`、`provide`、`setup`、Standard Schema 和 `AsyncDisposable` 生命周期。额外同时提供命名导出和 default 导出，是为了适配当前宿主加载器直接读取模块 namespace 的行为。不要据此宣称远程 provider 或 WebSocket 传输已完成。

## 验收边界

原生 `--diagnose` 只输出权限和会话锁定布尔状态；`--self-test` 只用合成 payload，不创建 EventTap。TypeScript 测试覆盖非法字段／长度、分帧、权限失败、spawn 失败、通知和退出清理。

2026-10-31 已通过真实验证：用户开启 Terminal 的输入监控后，真实 c3502 client 收到键盘、左右点击、移动和滚动的增长快照。先前仅设备控制授权的两轮全零结果不算通过；输入监控独立检查已补齐，防止假成功。30 秒测试自动停止，日志在忽略的 `build/C3502/manual-probe.log`。长期运行、功耗、其他 macOS 版本和打包分发仍未验收。没有 commit、push 或发布步骤。
