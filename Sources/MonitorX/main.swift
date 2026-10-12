import AppKit

#if !APPSTORE
if CommandLine.arguments.contains("--claude-statusline") {
    ClaudeUsageBridge.run()
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
