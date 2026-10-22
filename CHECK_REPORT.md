# 安全及通用性检查报告

检查日期：2026-10-22。检查对象：独立发布目录中的 1.2.0 源码和 Universal 2 测试包。安全检查时尚未上传 GitHub，未改动当前正在运行的旧版额度条。后续发布状态以 GitHub 仓库及 Release 为准。

## 结论

在本次源码审查、包内容检查、启发式扫描及协议测试范围内，未发现账号凭据或个人文件泄露。已修复开发诊断导出、环境变量过度继承和安装位置限制。

通用性部分通过：Apple 芯片实机连接通过，Intel 架构已构建，但未实机运行；未在 macOS 13 上实测。当前缺少 Developer ID 签名和 Apple 公证，Gatekeeper 检查拒绝此包，因此暂不符合“别人从互联网下载后按默认安全设置直接双击运行”的正式分发要求。

## 一、安全检查

| 检查项 | 结果与处理 |
| --- | --- |
| Token、API Key、JWT、私钥及签名传输 URL | 源码及发布 ZIP 启发式扫描未命中。未读取用户的 Codex 登录文件来进行扫描。 |
| 本机路径、宠物账号 ID、真实用量及截图 | 不包含在发布包中。源码使用合成测试数据。移除原版 `--verify-menubar` 真实用量导出及截图功能。 |
| ZIP 内容与扩展元数据 | 文件允许列表校验通过：仅 Info.plist、可执行文件、签名资源清单和安装说明，共 5 个文件（新增英文安装说明）。无资源叉、扩展属性、日志或图片。可执行权限保留。 |
| 子进程环境变量 | 改为允许列表；不继承 GitHub Token、API Key 或其他无关变量。相关回归测试通过。 |
| 本应用发出的 RPC | 只允许初始化握手及 `account/rateLimits/read`。不允许任务创建、模型生成或额度重置。离线测试记录已验证握手顺序。 |
| 协议响应 | 缓冲上限为 1 MiB；异常响应、过大响应、断开连接有固定错误提示，不展示原始服务器错误或响应。 |
| 网络与第三方依赖 | 应用无 HTTP 客户端、分析 SDK、上传接口或自动更新模块。二进制依赖为 macOS 系统框架及系统 Swift 库；额度网络访问由本机 Codex CLI 负责。 |
| 签名 | 包内签名结构校验通过，使用 ad-hoc + Hardened Runtime，无放宽保护的 entitlement；不等于可信开发者签名或公证。 |

安全边界：这是源码审查与启发式扫描，不是“绝对无风险”的保证。Codex CLI 使用自己的账号配置、缓存、日志和网络路径，拥有当前用户权限；RPC 允许列表不构成操作系统级只读沙盒。应仅选择可信 CLI 并保护本机配置、代理和账号。

## 二、通用性检查

| 场景 | 结果 |
| --- | --- |
| Apple 芯片 | 实际打包二进制自检通过；本机 macOS 26.6.2、Codex CLI 0.154.0 的真实只读连接通过。只记录接口可用性，不记录真实用量。 |
| Intel | x86_64 编译及通用 Mach-O 结构检查通过；此机器无 Rosetta，运行返回 Bad CPU type，不能宣称已在 Intel 实机测试通过。 |
| macOS 13+ | 两个架构的 Mach-O minimum OS 和 Info.plist 均为 13.0；尚未在 macOS 13 或其他旧版本实机运行。 |
| 常见 CLI 安装位置 | 支持用户目录、npm 全局目录、Homebrew、用户 PATH 和已知桌面应用内置位置。添加「选择 Codex CLI…」入口以处理自定义安装位置。不会自动执行 shell 初始化文件。 |
| npm/nvm 风格启动器 | 使用真实 Node 执行合成协议启动器，通过。CLI 路径含空格、父进程 PATH 没有 Node 时通过。 |
| 用户自己的账号 | 安装包不附带任何登录态。用户须安装 Codex CLI 并以自己的 ChatGPT 账号登录；仅 API Key 登录不保证提供套餐额度。 |
| 未安装 CLI | 离线测试通过，显示安装与选择提示，不崩溃。 |
| 未登录／没有套餐额度 | 离线测试通过，显示固定登录或缺失数据提示，不伪造百分比。 |
| 旧版 CLI 不支持接口 | 离线测试通过，显示升级提示。 |
| 只有一个额度窗口 | 离线测试通过，已提供的窗口仍正常更新，另一个不伪造。 |
| 不返回重置券明细 | 离线测试通过；分类自检通过，缺失或未知明细不推算。三类维持独立计数。 |
| 异常数据、超大响应、断线和超时 | 四项离线测试通过，进程可正常退出并显示不可用状态。 |
| 宠物与桌面聊天窗口依赖 | 不依赖宠物图片或宠物插件。额度条自己启动本机 CLI，聊天窗口无需持续打开。 |
| 运行时依赖 | 已打包应用不需要 Python、Xcode、Homebrew 或本项目目录；需要 macOS 系统库和单独安装的 Codex CLI。 |
| 互联网首次打开 | Gatekeeper 实测为 rejected。当前可用 Developer ID Application 身份数量为 0，尚未完成 Apple 签名和公证。正式分发前需补齐。 |

离线协议矩阵共 10 项通过：success、one_window、no_credits、not_logged_in、unsupported、missing_data、oversized、closed、timeout、missing_cli。另有 Node 启动器专项测试通过。测试使用临时空配置和合成数据，没有使用真实账号或网络。

## 三、当前交付物与发布前余项

- 测试包：`dist/CodexQuotaBar-v1.2.0-macos-universal.zip`，155200 字节。
- SHA-256：`4ba90b6f281cd4722a3328e45315ad8ff6245f1bb1bf11036aaf9c5bca18c863`。
- 源码、构建脚本、安全扫描及离线测试均在此项目中，可重复执行。
- 正式安装包发布前：取得 Developer ID 签名身份，完成签名、公证、附加公证票据后重新打包校验；在 Intel 和 macOS 13 实机补测；在非开发机器按普通下载流程验证首次打开。
- 尚未验证新菜单入口的真实用户交互、多个显示器等完整 GUI 场景，不把编译通过等同于全量 UI 验证。

## 参考依据

- [OpenAI 官方 CLI 安装与登录文档](https://learn.chatgpt.com/docs/codex/cli)：安装 CLI 和使用用户自己的登录。
- [Apple：安全打开 Mac 应用](https://support.apple.com/en-hk/102445)：互联网分发应用的 Developer ID 和公证检查。
- [Apple：软件公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 文档与截图发布补充

作者另行明确要求公开两张界面截图，已放入 docs/images 并嵌入中英文 README。截图中的用量数值是作者提供的界面示例；图片已去除 PNG 文本／EXIF 类元数据。图片不进入应用安装包。文档有意公开的截图不属于此前排除的开发诊断截图。安装包新增 INSTALL.en.txt，重新构建、签名和校验后更新了上方哈希。
