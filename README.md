<div align="center">

<img src="docs/images/hero.png" alt="MonitorX" width="100%">

# MonitorX

**简体中文** · [English](README.en.md)

**谁在吃你的 Mac？一眼就知道。**

macOS 26 菜单栏系统监视器 · Liquid Glass 界面 · 系统占用 + Codex / Claude 额度

</div>

---

## 亮点

- **直接告诉你是谁**：概览页每张卡片底部写出该资源当前占用最高的应用；明细页按应用合并（Chrome 的几十个 Helper 合成一行），点开看每个进程。
- **分类页面**：概览、CPU、内存、网络、磁盘、传感器、硬件，每类一个独立页面。
- **菜单栏常驻**：CPU、内存、网速、磁盘读写可自由勾选，两行紧凑显示，深浅色都清晰。
- **AI 额度**（官网版）：概览页和菜单栏查看 Codex / Claude 剩余额度与重置时间。Codex 自动查询，Claude 一键连接并引导官方登录；详见下方接入说明。
- **热度着色**：条形图平时是主题色，负载变重依次变黄、橙、红。
- **很轻**：面板关闭时约 1% 单核、约 27 MB 内存；进程级采样仅在面板打开时进行。
- **本地系统监控**：系统指标在本机采集；可选 Codex 额度监控由本机官方 Codex 向 OpenAI 查询，不向 MonitorX 开发者上传数据。
- **23 种语言**：English、简体中文、繁體中文、日本語、한국어、Español、Français、Deutsch、Italiano、Português、Русский、Українська、Polski、Nederlands、Svenska、Türkçe、العربية、עברית、हिन्दी、ไทย、Tiếng Việt、Bahasa Indonesia、Bahasa Melayu；默认跟随系统，也可在面板 `···` → 语言 中随时切换，阿拉伯语 / 希伯来语自动从右到左布局。

<div align="center">
<img src="docs/images/menubar.png" alt="菜单栏显示" width="420">
<br><sub>菜单栏：CPU · 内存 · 网速（浅色 / 深色背景）</sub>
</div>

## 截图

<table>
  <tr>
    <td align="center"><img src="docs/images/overview.png" width="260"><br><b>概览</b><br><sub>四张资源卡 + 电池 / 温度 / 风扇</sub></td>
    <td align="center"><img src="docs/images/cpu.png" width="260"><br><b>CPU</b><br><sub>用户/系统/空闲、负载、各核心</sub></td>
    <td align="center"><img src="docs/images/memory.png" width="260"><br><b>内存</b><br><sub>构成、压力、交换空间</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/network.png" width="260"><br><b>网络</b><br><sub>上下行速度与每应用流量排行</sub></td>
    <td align="center"><img src="docs/images/disk.png" width="260"><br><b>磁盘</b><br><sub>各卷容量、读写吞吐</sub></td>
    <td align="center"><img src="docs/images/sensors.png" width="260"><br><b>传感器</b><br><sub>全部温度传感器 + 风扇</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/hardware.png" width="260"><br><b>硬件</b><br><sub>机型、芯片、GPU、电池健康度</sub></td>
    <td align="center"><img src="docs/images/appstore-overview.png" width="260"><br><b>App Store 版 · 概览</b><br><sub>沙盒精简版，无进程排行</sub></td>
    <td align="center"><img src="docs/images/appstore-hardware.png" width="260"><br><b>App Store 版 · 硬件</b><br><sub>序列号 / GPU 改用沙盒安全接口</sub></td>
  </tr>
</table>

> 截图来自真实运行的 App（Intel MacBook Pro，macOS 26.3）。面板背景是 Liquid Glass，会随桌面壁纸透出，截图里看到的是深色底。

<a id="ai-usage"></a>

## AI 额度：Codex / Claude

写代码时，一起查看系统占用和 AI 剩余额度。概览页展示额度窗口、重置时间与更新时间；菜单栏分别显示 Codex / Claude 剩余最少的额度窗口。仅官网直装版提供。

<table>
  <tr>
    <td align="center"><img src="docs/images/ai-usage-dark.png" alt="Codex 与 Claude 额度卡片，深色，演示数据" width="340"><br><b>额度 · 深色</b></td>
    <td align="center"><img src="docs/images/ai-usage-light.png" alt="Codex 与 Claude 额度卡片，浅色，演示数据" width="340"><br><b>额度 · 浅色</b></td>
  </tr>
</table>

> 上面两张图使用真实 App 的界面代码渲染，额度数值为演示数据，不是账号实测。可运行 `Scripts/render_usage_screenshots.sh` 重新生成 README 和落地页的额度截图。

| | 接入步骤 | 更新方式 |
| --- | --- | --- |
| Codex | 安装官方 Codex CLI，使用 ChatGPT 账号登录；打开 MonitorX 即可查看 | 每 5 分钟自动查询，也可手动刷新 |
| Claude | 点击「连接 Claude Code」；按卡片提示完成 Pro / Max 账号登录，在自动打开的 Claude Code 中发送一条消息 | 首次收到回复后显示，随后随官方状态栏回调更新 |

Claude 网页或桌面聊天不会更新这个连接，API 计费登录也不提供这里的订阅额度。软件自动检查安装与登录状态，保留原有状态栏配置，断开时恢复。浏览器授权仍需本人完成一次。

额度显示最近读数：菜单栏 `*` 表示读数过期或刷新失败，`–` 表示尚无数据。Codex 只读查询不发起模型任务；MonitorX 不会为获取 Claude 额度自动发送消息，也不读取或导出登录凭证。

## 安装

**下载安装包**（`dist/` 里的 `.dmg`，或 [落地页](website/README.md) 上的下载按钮）：

1. 打开 dmg，把 MonitorX 拖进「应用程序」。
2. 首次运行若提示无法验证开发者（未公证的包），执行一次：
   ```bash
   xattr -cr /Applications/MonitorX.app
   ```
   或右键 → 打开。
3. 启动后自动显示主窗口；点击黄色最小化按钮或关闭窗口后，应用继续在菜单栏运行。

**从源码构建**（只需要 Command Line Tools，不需要 Xcode，要求 macOS 26 SDK）：

```bash
Scripts/build.sh          # 生成 build/MonitorX.app（x86_64 + arm64 通用，ad-hoc 签名）
open build/MonitorX.app
```

普通启动即显示主窗口，无需 `--show`（旧参数仍可使用）。再次从 Finder 或 Launchpad 打开应用，可恢复主窗口，即使菜单栏图标被遮挡。

## 使用

- **主窗口**：启动时显示，黄色最小化按钮或关闭按钮收起到菜单栏。窗口显示时保留 Dock 入口。
- **左键**点击菜单栏图标或数字：主窗口显示时将其置前；收起后展开快捷面板，`Esc` 或点击别处关闭。
- **右键**点击：打开主窗口 / 退出菜单。
- **刘海屏**：菜单栏外观默认「自动」，在刘海屏优先显示窄幅额度（未启用额度时使用图标），在其他屏幕显示实时指标；可在设置中切换「仅图标」或「实时指标」。macOS 管理图标位置，窄图标减少占用但不能保证拥挤时始终可见。
- 面板右上角 `···`：选择菜单栏显示哪些指标、开机启动、退出。「显示 Codex 额度」和「显示 Claude 额度」分别控制概览页卡片，与上方的菜单栏额度开关独立；关闭卡片也会从图片和文字分享中隐藏相应额度，不会断开 Claude 连接。
- **Claude 额度**（直装版）：在概览页点击「连接 Claude Code」，自动配置官方 `statusLine` 桥接并打开终端中的 Claude Code。软件自动检查安装和登录状态：未安装时打开官方安装指南，未登录时提供「登录 Claude」入口，完成官方登录后自动打开对话。启动目录独立，避免项目配置覆盖桥接。保留已有命令及设置，断开时恢复原状态栏；不需要额外运行时，也不会读取登录凭证。首次在 Pro/Max Claude Code 中收到回复后，自动显示 5 小时/7 天剩余额度及重置时间，菜单栏显示最低剩余比例；网页或桌面聊天不会触发此桥接。超过 15 分钟未收到更新或额度窗口已重置时标为旧读数（菜单栏 `*`）；没有收到数据时显示 `–`。其他项目的 Claude 设置若覆盖了 `statusLine`，需移除该覆盖后再使用。额度文件仅保存额度及更新时间，图片/文字分享也支持。
- **菜单栏 Codex 额度**（直装版）：默认显示 `CODEX` 和剩余百分比，可在「菜单栏显示项」中单独关闭。存在多个 Codex 额度窗口时显示剩余最少的那个，悬停可查看各额度窗口及重置时间。刘海屏自动模式仅显示已启用的 Codex / Claude 窄幅额度；显式选择「仅图标」时只在悬停提示中显示额度。刷新失败时旧值带 `*`，暂无数据时显示 `–`。
- **Codex 额度**（直装版）：概览页显示本机 Codex 的账号额度、重置时间和更新时间，每 5 分钟自动刷新，也可手动刷新。在设置中可关闭。需要安装官方 Codex CLI 并使用 ChatGPT 登录；通过官方 `codex app-server` 的 `account/rateLimits/read` 只读接口获取，不读取或导出登录凭证，也不发起模型任务。优先展示接口返回的所有额度桶，缺失的额度窗口不作推算；刷新失败时保留旧读数并显示错误与原更新时间。App Store 沙盒版不提供此项。
- **分享**：右上角分享按钮支持「当前页」或「全部页面」的图片复制/保存，以及文字版复制/导出为 UTF-8 `.txt` 文件。文字版含导出时间、当前指标和前 8 名应用/进程（遵循当前分组设置），不包含设备序列号。保存期间仍持续采样，文件内容固定为点击导出时的读数。
- 概览页点击任意卡片进入对应明细页。
- 明细页底部的占用排行：默认按应用合并，点击行展开各进程；右上角可切换「应用 / 进程」。
- 硬件页的序列号点击即可复制。

## 多语言

- 翻译文件在 `Resources/Localization/<语言>.lproj/Localizable.strings`，`Scripts/build.sh` 会把它们拷进 `.app` 并写入 `CFBundleLocalizations`（因此 macOS「系统设置 → 通用 → 语言与地区 → App」里也能单独给 MonitorX 指定语言）。
- `swift run` / 调试构建也会通过 SwiftPM 资源包加载翻译，切换语言无需重启。
- 运行 `Scripts/check_language_switch.sh` 可验证开发版和 `.app` 资源目录下的语言切换、设置保存及界面刷新通知（只需 Command Line Tools）。
- 代码里用 `L("English text")` / `L("Format %@", arg)` 取文案，键就是英文原文；缺翻译时回退为英文。
- 新增或修改文案后运行 `Scripts/check_localizations.py`，检查每种语言是否缺键、多余键、占位符（`%@` / `%1$@`）是否一致。
- 新增语言：复制 `en.lproj` 改名并翻译，再在 `Sources/MonitorX/App/Localization.swift` 的 `AppLanguage` 里加一项。

## 两个版本

| | 官网版（direct） | App Store 版（appstore） |
| --- | --- | --- |
| 构建 | `Scripts/build.sh` → `build/MonitorX.app` | `EDITION=appstore Scripts/build.sh` → `build/appstore/MonitorX.app` |
| 出包 | `Scripts/release.sh`（签名 + 公证 + dmg） | `Scripts/release_appstore.sh`（签名 + pkg，上传 App Store Connect） |
| 沙盒 | 无 | **有**（`Resources/AppStore.entitlements`） |
| CPU / 内存 / 网络 / 磁盘 / 电池 / 硬件信息 | ✅ | ✅ |
| 进程占用排行与明细 | ✅ | ❌ 沙盒禁止读取其他进程 |
| 传感器页（全部温度 + 风扇） | ✅ | ❌ 沙盒禁止访问 AppleSMC |
| Codex / Claude 额度及菜单栏显示 | ✅ | ❌ |
| 图片及文字复制 / 导出 | ✅ | ✅ |

App Store 版用 `-DAPPSTORE` 编译，被裁掉的功能（`ps` / `netstat` / `system_profiler` / SMC）的代码不会进入二进制。
序列号、GPU、显示器信息改用 IOKit 注册表 / Metal / AppKit 读取。
`Scripts/build.sh` 构建的 App Store 版带沙盒签名（ad-hoc），可以在本机直接运行，看到的就是上架后的真实能力。

## 出包

```bash
# 官网版：签名 + 公证 + dmg（没有证书时生成 ad-hoc 包，仅供自用/朋友）
VERSION=1.1.0 \
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" \
NOTARY_PROFILE=notary \
Scripts/release.sh

# App Store 版：签名 + pkg（没有证书时只生成本地沙盒测试版）
BUNDLE_ID=com.yourname.monitorx TEAM_ID=ABCDE12345 VERSION=1.1.0 BUILD_NUMBER=1 \
APP_IDENTITY="Apple Distribution: 你的名字 (TEAMID)" \
INSTALLER_IDENTITY="3rd Party Mac Developer Installer: 你的名字 (TEAMID)" \
PROVISION_PROFILE=~/Downloads/MonitorX.provisionprofile \
Scripts/release_appstore.sh
```

两个脚本的头部注释里有一次性准备步骤（证书、公证凭据、描述文件）。产物在 `dist/`。

**自动发布（GitHub Actions）**：推送 `v*` 标签即触发 [`.github/workflows/release.yml`](.github/workflows/release.yml)，在 macOS 26 runner 上构建官网版，并把 `.dmg`、`.zip`、`SHA256SUMS.txt` 上传到对应的 GitHub Release（`v1.2.0-beta.1` 这类带 `-` 的标签发布为预发布版）。

```bash
git tag v1.2.0 && git push origin v1.2.0
```

在仓库 Settings → Secrets and variables → Actions 中配置以下密钥后，CI 会签名并公证；未配置时发布 ad-hoc 签名包。

| Secret | 内容 |
| --- | --- |
| `MACOS_CERT_P12` | 「Developer ID Application」证书（含私钥）导出的 .p12，base64 编码 |
| `MACOS_CERT_PASSWORD` | 导出 .p12 时设置的密码 |
| `NOTARY_KEY` | App Store Connect API 密钥文件 `AuthKey_XXXX.p8` 的内容 |
| `NOTARY_KEY_ID` | 该密钥的 Key ID |
| `NOTARY_ISSUER` | App Store Connect 密钥列表上方的 Issuer ID |

## 落地页（Docker 部署）

[`website/`](website/) 是一个纯静态落地页（无构建步骤），用 nginx 提供服务：

```bash
cd website
docker compose up -d --build      # http://localhost:8080，PORT=3000 可改端口
```

下载按钮直接指向 GitHub Releases 的 DMG，页面自动读取最新正式版；无需在服务器存放安装包。可在 `website/.env` 中设置 `PORT=3000` 修改端口。
详见 [website/README.md](website/README.md)。

## 数据来源

| 指标 | 来源 |
| --- | --- |
| CPU 总量 / 各核 | `host_processor_info` |
| 内存构成 / 压力 / 交换 | `host_statistics64`、`sysctl` |
| 网络速率 | `getifaddrs`（仅 `en*` 接口） |
| 磁盘容量 / 吞吐 | `URLResourceValues`、IOKit `IOBlockStorageDriver` |
| 进程 CPU / 内存 / 磁盘 | `proc_pid_rusage`（内存为 Activity Monitor 同口径的 footprint） |
| root 进程（WindowServer 等） | `ps`（内存为 RSS） |
| 进程网络 | `netstat -anv`（按 socket 累计字节差分，忽略回环流量） |
| 温度 / 风扇（传感器页枚举全部 `T*` 键） | AppleSMC（仅官网版） |
| 电池 | IOKit `AppleSmartBattery` |
| 序列号 / GPU / 显示器 | 官网版 `system_profiler`；App Store 版 IOKit 注册表 / Metal / AppKit |
| Codex 额度 | 官方 Codex CLI app-server，`account/rateLimits/read` |
| Claude 额度 | 官方 Claude Code `statusLine` 回调 |

监控界面隐藏时只采样系统级指标；进程级采样仅在主窗口或面板显示时进行（3 秒一次）。额度监控按前述更新方式进行。

## 已知限制

- 需要 macOS 26（使用了 `NSGlassEffectView` 与 `glassEffect`）。
- 默认发布包是 ad-hoc 签名，未公证；正式分发请用 `Scripts/release.sh` 配合 Developer ID。
- root 进程的内存为 RSS，与活动监视器的 footprint 口径略有差别。
- 进程网络流量忽略回环，所以经本机代理转发的流量只会算在代理软件上。
- Apple Silicon 上的温度传感器键名与 Intel 不同，部分机型可能读不到全部传感器（仅在 Intel MacBook Pro 上实测）。
- AI 额度监控需要本机官方 CLI 和相应登录，仅官网直装版提供；Claude 订阅额度需要在 Claude Code 中收到一次回复后更新。

## 目录结构

```
Sources/MonitorX/
  App/        AppDelegate、菜单栏图标、玻璃面板、设置、版本开关（Edition）、多语言（Localization）
  Sampling/   CPU / 内存 / 网络 / 磁盘 / 进程 / 传感器 / 硬件采样，SystemMonitor 汇总
  UI/         SwiftUI 页面与组件
Scripts/      build.sh、release.sh、release_appstore.sh、make_icon.swift、check_localizations.py
Resources/    AppStore.entitlements、Localization/（23 种语言的 Localizable.strings）
website/      落地页 + Dockerfile + nginx 配置
docs/images/  README 截图
```
