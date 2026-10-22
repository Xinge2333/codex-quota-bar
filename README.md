# Codex Quota Bar / 额度条

[English](README.en.md) · 中文

独立 macOS 菜单栏与桌面悬浮额度显示应用。界面使用 Swift + AppKit 系统框架；额度查询依赖单独安装的 Codex CLI。

## 下载

- [下载 macOS 通用测试版 v1.2.0](https://github.com/Xinge2333/codex-quota-bar/releases/download/v1.2.0/CodexQuotaBar-v1.2.0-macos-universal.zip)
- [发行说明与全部附件](https://github.com/Xinge2333/codex-quota-bar/releases/tag/v1.2.0)
- [SHA-256 校验文件](https://github.com/Xinge2333/codex-quota-bar/releases/download/v1.2.0/SHA256SUMS)

也可以直接复制下面这段话给 Codex：

```text
请帮我下载并且配置这个额度条，软件地址：https://github.com/Xinge2333/codex-quota-bar
```

这是**未公证的测试版**，不是零配置安装包。请先阅读下方安装要求。无需编程环境即可运行已打包应用，但需要自己安装和登录 Codex CLI。

## 界面预览

同时显示 5 小时和每周剩余额度：

![同时显示两项额度及菜单](docs/images/menu-both-quotas.png)

仅显示 5 小时剩余额度，可在菜单中随时恢复每周显示：

![独立关闭每周显示](docs/images/menu-five-hour-only.png)

截图由作者提供，数字为截图时的示例，不能代表下载者的实时额度。新版本另外提供 CLI 选择和安装说明入口；应用当前界面为中文。

## 支持范围

- macOS 13+，Universal 2 安装包包含 Apple 芯片和 Intel 两种架构。
- 用户自行安装 Codex CLI，并用自己的 ChatGPT 账号登录。不是无需登录的额度接口。
- CLI 和账号需支持 `account/rateLimits/read`；只使用 API Key 的账号不保证提供套餐额度。
- 不需要宠物，也不需要桌面聊天应用持续运行。已安装的聊天应用可能提供可用的内置 CLI，但不作为唯一安装方式。
- 运行应用不需要 Swift、Python、Homebrew 或 Xcode；从源码构建需要 Xcode Command Line Tools 及 Python 3。

## 安装

先按 [OpenAI 官方 CLI 文档](https://learn.chatgpt.com/docs/codex/cli)安装并运行 `codex login`。再解压安装包，将应用移到「应用程序」。找不到 CLI 时可在菜单中点击「选择 Codex CLI…」，选择 `which codex` 显示的文件。

当前是未公证的测试包，仅使用 ad-hoc 签名。互联网下载可能被 macOS 拦截，尚不适合作为“所有人下载后直接双击”的正式发布版。正式分发需要 Apple Developer ID 签名和公证；不要关闭 Gatekeeper。

下载后在解压目录打开「使用说明.txt」或 `INSTALL.en.txt`。如需验证下载完整性，将 ZIP 和 `SHA256SUMS` 放在同一个目录，在该目录执行：

```sh
shasum -a 256 -c SHA256SUMS
```

校验值只能检查文件是否与本次发布一致，不能替代 Apple 签名或公证。

## 使用说明

1. 点击菜单栏额度图标，查看两个窗口的剩余额度及重置时间。
2. 勾选或取消「显示 5 小时用量」「显示周用量」，分别控制菜单栏的两列。两个都取消后仍保留「额度」入口，可重新勾选。
3. 点击「显示桌面悬浮条／关闭桌面悬浮条」切换悬浮条；拖动悬浮条可调整位置，右键可打开同一菜单。
4. 点击「立即刷新」手动刷新，或等待每 60 秒的自动刷新。橙色状态提示连接中或旧数据，不应当作最新额度。
5. 「使用 24 小时制」切换时间格式；时间区域固定为北京时间。
6. 选择「退出额度条」退出。显示偏好和位置会保留；电脑重启后从「应用程序」重新打开，本版不自动开机启动。

如果 CLI 是通过 npm/nvm/asdf 或其他非默认位置安装的，先执行 `which codex`，再通过「选择 Codex CLI…」选择相应的可信可执行文件。未登录时执行 `codex login`；接口不支持时升级 CLI。

## 显示规则

上排为剩余百分比，下排为额度重置时间或日期，时间均为北京时间。可独立关闭菜单栏的 5 小时或每周显示；两个都关闭时保留「额度」入口。两列间隔 7 pt，左右无额外留白。桌面悬浮条可单独关闭。

重置券按三种互斥类型显示当前可用次数：「5 小时重置次数」「每周重置次数」「完全重置次数」。完全重置只计入完全重置，例如单张完全重置券显示 0、0、1。明细缺失、截断或类别未知时不猜测分类。

## 构建和检查

```sh
bash scripts/build.sh
python3 scripts/integration_tests.py /path/to/MarbleQuotaBar
```

构建输出位于 `dist/`，包括通用 ZIP 和 SHA256SUMS。构建脚本会运行自检、安全扫描和签名结构检查。自检不需要网络或登录。

可在终端运行应用二进制的 `--check-connection`：只输出连接状态及接口能力标记，不打印真实百分比、重置日期、账号或凭据。`MARBLE_CODEX_PATH` 可指定可信 CLI 的绝对路径，`CODEX_HOME` 可选择用户自己的 Codex 配置目录。

安全边界、隐私与未验证范围见 [SECURITY.md](SECURITY.md)。
