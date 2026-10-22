# 安全与隐私

## 数据流

应用启动用户本机已经安装的 Codex CLI，使用 stdio JSON-RPC。应用发出的 RPC 方法仅允许 `initialize`、`initialized` 和 `account/rateLimits/read`。不创建任务、不生成内容、不使用重置券。

额度请求由 Codex CLI 使用本机登录访问其服务。应用自身没有 HTTP 客户端、分析 SDK、上传服务器或自动更新模块；这不代表 Codex CLI 本身离线或没有自己的日志、缓存与网络行为。

## 凭据边界

发布包不包含登录文件、Cookie、令牌、账号信息、真实用量截图或开发诊断记录。应用不直接打开或复制 Codex 登录文件。除显示设置、窗口位置和用户选择的 CLI 路径外，应用不将额度响应写入文件。连接检查只输出能力标记及固定错误提示，不输出原始响应。

子进程环境使用允许列表，仅保留用户目录、区域设置、Codex 配置目录、代理及证书配置；不继承 GitHub 令牌、API Key 或其他不相关变量。支持 npm/nvm 启动器所需的 Node 查找路径，不自动执行 shell 初始化文件。

允许列表限制的是本应用发送的请求，不会把 Codex CLI 变成受操作系统强制隔离的只读程序。CLI 本身拥有当前用户权限，并使用自己的配置；仅选择可信官方 CLI，妥善管理本机 Codex 配置和代理。恶意替换 CLI、受控代理或本机恶意软件不在本工具的防护范围内。

## 发布检查

`scripts/audit.py` 对源码及发布包执行凭据格式、本机路径、签名传输 URL 等启发式检查，并要求安装包只包含应用必需文件及安装说明。ZIP 不携带资源叉、扩展属性、截图或日志。启发式扫描不能证明不存在任何未知形式的秘密。

## 分发限制

测试包使用 ad-hoc 签名及 Hardened Runtime，不含放宽安全保护的 entitlement。尚未有 Developer ID 签名、Apple 公证或公证票据；Gatekeeper 可能拒绝互联网下载包。请勿通过关闭系统安全功能来解决。

正式分发须使用发布者的 Developer ID 完成签名、公证并附加公证票据，随后重新打包和校验。参考 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 有意公开的界面截图

仓库 docs/images 中两张截图由作者明确提供并授权公开，用于中英文使用说明。它们包含当时的用量示例，已清理 PNG 文本／EXIF 元数据，不包含账号凭据，也不随应用安装包打包。此前排除的是自动导出的开发诊断截图和运行记录。
