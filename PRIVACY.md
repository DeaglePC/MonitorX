# MonitorX 隐私政策 / Privacy Policy

最后更新 / Last updated: 2026-10-09

## 简体中文

MonitorX 不向开发者收集或上传个人信息，不含统计、广告或崩溃上报。

- **系统监控在本机完成**：CPU、内存、网络、磁盘等系统监控不发起网络请求。
- **可选 Codex 额度监控（直装版）**：默认由本机官方 Codex CLI 查询额度。主动启用「Codex 直接查询」并确认授权后，MonitorX 会读取本机 Codex `auth.json` 中的访问令牌和账号标识，仅发送给 ChatGPT 官方额度端点。令牌仅在请求期间保留于内存，不保存、导出、刷新或向开发者发送；不发起模型任务。可点击「仅使用 CLI」撤销直接读取授权，也可关闭卡片和菜单栏额度来停止查询。额度及更新时间保存在进程内存中。
- **数据只在本机**：CPU、内存、网络、磁盘、电池和硬件信息都在你的 Mac 上实时读取并显示，不会离开这台设备。
- **本地设置**：菜单栏显示项、语言、开机启动及额度授权等偏好设置保存在本机的 macOS 偏好设置中。额度授权可在 App 内撤销；删除 App 不会删除用户选择的源快照文件。
- **可选 Claude 额度监控（直装版）**：确认授权后，只读访问官方 Claude Code 本机 OAuth 凭证文件或 macOS Keychain 项，仅将访问令牌发送到 Anthropic 官方额度端点。令牌只在请求期间存在于内存，不保存、导出、刷新或向开发者发送；不会发起模型任务或读取对话。后台查询不显示 Keychain 授权提示，手动连接/刷新可触发系统授权。额度及更新时间保存在进程内存中；断开撤销访问并清除读数。若此前使用状态栏桥接，断开也会恢复原状态栏配置。第三方使用订阅凭证存在服务条款风险。
- **额度文件授权（App Store 版）**：只读取你通过系统文件选择框明确选择的额度 JSON 文件，拒绝登录凭证和非额度字段。不读取其他 App 的 Keychain，不运行外部 CLI，也不联网查询账号。只读 security-scoped bookmark 保存在本机偏好设置中，供下次启动继续读取；点击断开会删除该授权及内存读数，不删除源文件。界面显示源文件的更新时间，超过 15 分钟或窗口已重置时标记为旧读数。生成快照的脚本由用户自行在终端或 Claude Code 中运行，不由商店版安装或启动。
- **分享导出**：只有在你主动选择复制或保存时，MonitorX 才会把当前页面的图片或文字放到剪贴板或你选择的位置。导出内容可能包含 Codex 和 Claude 额度信息，不含设备序列号。

如果本政策有变更，会在此页面更新。如有疑问，请在 [GitHub Issues](https://github.com/DeaglePC/MonitorX/issues) 联系我们。

## English

MonitorX does not collect or upload personal information to the developer. It contains no analytics, ads or crash reporting.

- **Local system monitoring**: CPU, memory, network and disk monitoring make no network requests.
- **Optional Codex quota monitoring (direct edition)**: by default, the official local Codex CLI queries quota. After you explicitly enable direct queries and confirm consent, MonitorX reads the access token and account identifier from the local Codex `auth.json` and sends them only to the official ChatGPT quota endpoint. The token is held in memory only during the request; it is never saved, exported, renewed or sent to the developer. No model task is initiated. Use CLI only revokes direct credential access; disabling both quota displays stops polling. Readings and timestamps stay in process memory.
- **Your data stays on your Mac**: CPU, memory, network, disk, battery and hardware information is read and displayed locally and never leaves your device.
- **Local settings**: preferences such as menu bar items, language, launch at login and quota grants are stored in macOS preferences on your Mac. Quota access can be revoked in the app. Removing the app does not delete user-selected source snapshots.
- **Optional Claude quota monitoring (direct edition)**: after explicit consent, MonitorX reads official local Claude Code OAuth credentials from its file or macOS Keychain item and sends the access token only to the official Anthropic quota endpoint. Tokens remain in request memory and are never saved, exported, renewed or sent to the developer. No model tasks or conversation reads occur. Background requests never display Keychain prompts; manual connect/refresh can request system authorization. Quota readings and timestamps remain in process memory. Disconnect revokes access and clears readings, restoring any previously installed MonitorX status-line bridge. Third-party subscription credential reuse carries service terms risk.
- **Quota file access (App Store edition)**: only quota JSON files explicitly selected through the system file picker are read. Credential files and non-quota fields are rejected. This edition does not read other apps’ Keychain items, launch external CLIs or query account quotas online. A read-only security-scoped bookmark is saved locally for later launches. Disconnect removes the grant and in-memory readings without deleting the source file. The original capture timestamp remains visible; readings older than 15 minutes or past a reset are marked stale. Snapshot scripts are run manually by the user in Terminal or Claude Code, never installed or launched by the App Store app.
- **Sharing**: only when you choose to copy or save does MonitorX put page images or text on the clipboard or in your selected location. Exports can include Codex and Claude quota information and omit the device serial number.

Any changes to this policy will be posted on this page. Questions: [GitHub Issues](https://github.com/DeaglePC/MonitorX/issues).
