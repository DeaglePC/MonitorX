# MonitorX 隐私政策 / Privacy Policy

最后更新 / Last updated: 2026-10-09

## 简体中文

MonitorX 不向开发者收集或上传个人信息，不含统计、广告或崩溃上报。

- **系统监控在本机完成**：CPU、内存、网络、磁盘等系统监控不发起网络请求。
- **可选 Codex 额度监控（直装版）**：开启后，MonitorX 调用本机官方 Codex CLI，由 Codex 使用已有登录状态向 OpenAI 查询账号额度。MonitorX 不读取、保存或导出登录凭证，不向开发者发送数据，也不发起模型任务。可在设置中关闭。额度读数及更新时间只保存在当前进程内存中。
- **数据只在本机**：CPU、内存、网络、磁盘、电池和硬件信息都在你的 Mac 上实时读取并显示，不会离开这台设备。
- **本地设置**：菜单栏显示项、语言、开机启动等偏好设置保存在本机的 macOS 偏好设置中，卸载 App 即可清除。
- **可选 Claude 额度监控（直装版）**：点击连接后，配置本机 Claude Code 官方状态栏命令，只将额度比例、重置时间及更新时间写入本机应用支持目录。通过官方 `claude auth status` 检查登录状态，不记录命令返回的账号信息。登录入口打开终端中的官方登录流程和对话；授权及对话由 Claude Code 处理。不会读取登录凭证或存储对话内容。原状态栏配置会备份，断开后恢复。
- **分享导出**：只有在你主动选择复制或保存时，MonitorX 才会把当前页面的图片或文字放到剪贴板或你选择的位置。导出内容可能包含 Codex 和 Claude 额度信息，不含设备序列号。

如果本政策有变更，会在此页面更新。如有疑问，请在 [GitHub Issues](https://github.com/DeaglePC/MonitorX/issues) 联系我们。

## English

MonitorX does not collect or upload personal information to the developer. It contains no analytics, ads or crash reporting.

- **Local system monitoring**: CPU, memory, network and disk monitoring make no network requests.
- **Optional Codex quota monitoring (direct edition)**: when enabled, MonitorX invokes the official local Codex CLI, which uses its existing sign-in to query account limits from OpenAI. MonitorX does not read, store or export credentials, send data to the developer, or initiate model tasks. You can disable this in settings. Quota readings and their timestamps are kept only in process memory.
- **Your data stays on your Mac**: CPU, memory, network, disk, battery and hardware information is read and displayed locally and never leaves your device.
- **Local settings**: preferences such as menu bar items, language and launch at login are stored in macOS preferences on your Mac and are removed when you delete the app.
- **Optional Claude quota monitoring (direct edition)**: connecting configures the official local Claude Code status line. Only quota percentages, reset times and the update timestamp are stored in the local application support directory. The official `claude auth status` command checks login status without recording returned account information. The sign-in action opens the official login flow and an interactive session in Terminal; Claude Code handles authorization and conversations. MonitorX does not read credentials or store conversation content. The original status-line configuration is backed up and restored on disconnect.
- **Sharing**: only when you choose to copy or save does MonitorX put page images or text on the clipboard or in your selected location. Exports can include Codex and Claude quota information and omit the device serial number.

Any changes to this policy will be posted on this page. Questions: [GitHub Issues](https://github.com/DeaglePC/MonitorX/issues).
