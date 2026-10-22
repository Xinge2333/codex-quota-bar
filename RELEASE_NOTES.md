# v1.3.0 — 公开测试版 / Public test release

## 中文

新增完整英文界面。菜单 →「语言 / Language」可切换简体中文或 English，立即生效并记住选择。

macOS 菜单栏与可选桌面悬浮额度条，显示 Codex 5 小时／每周剩余额度及重置时间。可分别开关两列显示，三类重置券独立统计。

下载 `CodexQuotaBar-v1.3.0-macos-universal.zip`，解压后阅读「使用说明.txt」或 `INSTALL.en.txt`。ZIP 包含 Apple 芯片及 Intel 二进制。安装与功能说明及截图见 [中文 README](https://github.com/Xinge2333/codex-quota-bar/blob/main/README.md)。

**使用前提及限制：**

- macOS 13+；用户自行安装可信的 Codex CLI，并通过 `codex login` 登录自己的账号。
- CLI 未自动找到时，在菜单选择「选择 Codex CLI…」。
- 这是仅 ad-hoc 签名、未取得 Developer ID 签名和 Apple 公证的测试版。macOS Gatekeeper 可能拦截互联网下载包；不要关闭系统安全保护。
- Apple 芯片本机验证通过；Intel 及 macOS 13 尚未实机验证。账号和 CLI 版本可能不提供所有数据。
- 应用仅查询，不使用重置券、不调用模型生成。数字为剩余比例，时间为北京时间。

附件 `SHA256SUMS` 可校验 ZIP 完整性；它不替代 Apple 签名或公证。

## English

New: English interface and a **语言 / Language** submenu. Switch between Simplified Chinese and English instantly; your choice is remembered after restart.

A macOS menu bar and optional floating desktop display for remaining five-hour and weekly Codex quotas. Columns can be toggled independently; reset credits are counted in separate categories.

Download `CodexQuotaBar-v1.3.0-macos-universal.zip`, extract it, and read `INSTALL.en.txt`. The archive contains both arm64 and x86_64 binaries. See the [English guide and screenshots](https://github.com/Xinge2333/codex-quota-bar/blob/main/README.en.md).

**Requirements and limitations:**

- macOS 13+. Install a trusted Codex CLI separately and run `codex login` with your own account.
- Use **选择 Codex CLI…** (Select Codex CLI…) if automatic discovery fails. Use **语言 / Language → English** to switch the interface.
- This is an ad-hoc-signed, **unnotarized test build**, without a Developer ID signature. Gatekeeper may block an internet download. Do not disable system security protections.
- Apple Silicon was tested on the development machine. Intel hardware and macOS 13 have not been tested. Account and CLI capabilities may differ.
- The app only queries quota; it never redeems reset credits or starts model generation. Values are remaining percentages. All times use UTC+8.

Use the attached `SHA256SUMS` to verify ZIP consistency. A checksum does not replace Apple signing or notarization.
