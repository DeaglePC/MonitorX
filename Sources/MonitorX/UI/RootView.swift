import SwiftUI

/// UI state that must survive the panel being hidden.
@Observable
final class PanelState {
    var isOpen = false
    var tab: Tab = .overview
    /// Set while a dialog of ours (e.g. the save panel) is up, so clicks in it don't close the panel.
    var isPresentingDialog = false
}

struct RootView: View {
    @Environment(Settings.self) private var settings
    @Environment(SystemMonitor.self) private var monitor
    @Environment(PanelState.self) private var state
    @Namespace private var tabNS
    @State private var toast: Toast?

    private struct Toast: Equatable {
        let text: String
        let ok: Bool
        var busy = false
        /// File to reveal in Finder when the toast is clicked.
        var file: URL?
        let id = UUID()
    }

    private var tab: Tab { state.tab }

    var body: some View {
        // While the panel is hidden the whole tree is dropped so SwiftUI does no work on every sample.
        if state.isOpen {
            GeometryReader { geometry in
                content.environment(\.monitoringWidth, geometry.size.width)
            }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        ZStack(alignment: .topTrailing) {
            // Soft tint that follows the current page.
            LinearGradient(colors: [tab.accent.opacity(0.20), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.5), value: tab)

            tab.page(go: select)
            .id(tab)
            // Drag anywhere that isn't a control to move the panel.
            .gesture(WindowDragGesture())
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .overlay(alignment: .bottom) {
                if let toast { toastView(toast) }
            }

            HStack(spacing: 8) {
                shareMenu
                settingsMenu
            }
            .padding(.top, 16).padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, Localizer.shared.locale)
        .environment(\.layoutDirection, Localizer.shared.layoutDirection)
    }

    private func select(_ t: Tab) {
        withAnimation(.snappy(duration: 0.28)) { state.tab = t }
    }

    // MARK: tab bar

    private var tabBar: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Tab.available) { t in
                    Button { select(t) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.symbol).font(.system(size: 15, weight: .semibold))
                            Text(t.title).font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(tab == t ? t.accent : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == t {
                                Capsule().fill(t.accent.opacity(0.18))
                                    .matchedGeometryEffect(id: "sel", in: tabNS)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    // MARK: share

    private var shareMenu: some View {
        Menu {
            Section(L("This Page")) {
                Button { share(all: false, save: false) } label: { Label(L("Copy to Clipboard"), systemImage: "doc.on.doc") }
                Button { share(all: false, save: true) } label: { Label(L("Save as Image…"), systemImage: "square.and.arrow.down") }
                Button { shareText(all: false, save: false) } label: { Label(L("Copy as Text"), systemImage: "doc.plaintext") }
                Button { shareText(all: false, save: true) } label: { Label(L("Save as Text…"), systemImage: "document") }
            }
            Section(L("All Pages")) {
                Button { share(all: true, save: false) } label: { Label(L("Copy to Clipboard"), systemImage: "doc.on.doc") }
                Button { share(all: true, save: true) } label: { Label(L("Save as Image…"), systemImage: "square.and.arrow.down") }
                Button { shareText(all: true, save: false) } label: { Label(L("Copy as Text"), systemImage: "doc.plaintext") }
                Button { shareText(all: true, save: true) } label: { Label(L("Save as Text…"), systemImage: "document") }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .bold))
                .offset(y: -1)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .circle)
        .fixedSize()
        .help(L("Share"))
    }

    /// Shares a fixed text snapshot of the chosen pages.
    private func shareText(all: Bool, save: Bool) {
        let date = Date()
        // Capture the text now, so sampling while the save dialog is open cannot change the export.
        let text = TextSnapshot.report(tabs: all ? Tab.available : [tab], monitor: monitor, settings: settings, date: date)
        guard save else {
            let ok = TextSnapshot.copy(text)
            return show(Toast(text: ok ? L("Text copied to clipboard") : L("Couldn't copy the text"), ok: ok))
        }
        withAnimation(.smooth) { toast = nil }
        state.isPresentingDialog = true
        Snapshot.saveText(text, name: all ? L("All Pages") : tab.title, date: date) { result in
            state.isPresentingDialog = false
            switch result {
            case .saved(let url): show(Toast(text: L("Saved “%@”", url.lastPathComponent), ok: true, file: url))
            case .failed: show(Toast(text: L("Couldn't save the text"), ok: false))
            case .cancelled: break
            }
        }
    }

    /// Renders the current page (or every page as one collage), then copies it or saves it as a PNG.
    private func share(all: Bool, save: Bool) {
        // Rendering takes a moment (seconds for all pages on Intel), so say so first and render on the next pass.
        // No animation: the main thread is busy while rendering, so a transition would freeze half-way.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { toast = Toast(text: L("Creating image…"), ok: true, busy: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { render(all: all, save: save) }
    }

    private func render(all: Bool, save: Bool) {
        let ctx = Snapshot.Context(monitor: monitor, settings: settings)
        guard let image = all ? Snapshot.allPages(ctx) : Snapshot.page(tab, ctx) else {
            return show(Toast(text: L("Couldn't create the image"), ok: false))
        }
        guard save else {
            let ok = Snapshot.copy(image)
            return show(Toast(text: ok ? L("Image copied to clipboard") : L("Couldn't copy the image"), ok: ok))
        }
        withAnimation(.smooth) { toast = nil }
        state.isPresentingDialog = true
        Snapshot.save(image, name: all ? L("All Pages") : tab.title, date: ctx.date) { result in
            state.isPresentingDialog = false
            switch result {
            case .saved(let url): show(Toast(text: L("Saved “%@”", url.lastPathComponent), ok: true, file: url))
            case .failed: show(Toast(text: L("Couldn't save the image"), ok: false))
            case .cancelled: break
            }
        }
    }

    private func show(_ t: Toast) {
        withAnimation(.snappy) { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + (t.file == nil ? 2 : 3.5)) {
            if toast == t { withAnimation(.smooth) { toast = nil } }
        }
    }

    private func toastView(_ t: Toast) -> some View {
        HStack(spacing: 7) {
            if t.busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: t.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(t.ok ? Theme.down : .orange)
            }
            Text(t.text).lineLimit(1).truncationMode(.middle)
            if t.file != nil {
                Text(L("Show in Finder")).foregroundStyle(Theme.cpu)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture {
            if let file = t.file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 84)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: settings

    private var settingsMenu: some View {
        SettingsMenu(hasFans: !monitor.sensors.fans.isEmpty)
    }
}

/// Kept as its own view so the open menu is not rebuilt (and its submenu closed/flickering) on every sampling tick.
private struct SettingsMenu: View {
    @Environment(Settings.self) private var settings
    let hasFans: Bool

    var body: some View {
        @Bindable var s = settings
        @Bindable var loc = Localizer.shared
        return Menu {
            Section(L("Show in Menu Bar")) {
                Picker(selection: $s.menuBarAppearance) {
                    Text(L("Automatic")).tag(MenuBarAppearance.automatic)
                    Text(L("Icon Only")).tag(MenuBarAppearance.compact)
                    Text(L("Live Metrics")).tag(MenuBarAppearance.detailed)
                } label: { Text(L("Menu Bar Appearance")) }
                Toggle(L("CPU"), isOn: $s.showCPU)
                Toggle(L("Memory"), isOn: $s.showMemory)
                Toggle(L("Network Speed"), isOn: $s.showNetwork)
                Toggle(L("Disk Activity"), isOn: $s.showDisk)
                if !Edition.isAppStore { Toggle(L("Codex Usage"), isOn: $s.showCodexInMenuBar) }
                if !Edition.isAppStore { Toggle(L("Claude Usage"), isOn: $s.showClaudeInMenuBar) }
                if Edition.hasSensors {
                    Toggle(L("CPU Temperature"), isOn: $s.showTemperature)
                    if hasFans || s.showFan {   // fanless Macs have nothing to show
                        Toggle(L("Fan Speed"), isOn: $s.showFan)
                    }
                }
            }
            Section {
                Picker(selection: $s.menuBarClickBehavior) {
                    Text(L("Quick Panel")).tag(MenuBarClickBehavior.quickPanel)
                    Text(L("Main Window")).tag(MenuBarClickBehavior.mainWindow)
                } label: { Text(L("Menu Bar Click Behavior")) }
                if !Edition.isAppStore { Toggle(L("Show Codex Usage"), isOn: $s.showCodexUsage) }
                if !Edition.isAppStore { Toggle(L("Show Claude Usage"), isOn: $s.showClaudeUsage) }
                Picker(selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                } label: {
                    Label(L("Language"), systemImage: "globe")
                }
                .pickerStyle(.menu)
                Toggle(L("Launch at Login"), isOn: Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
            }
            Button(L("Quit MonitorX")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .circle)
        .fixedSize()
    }
}

extension Tab {
    /// The page shown for this tab (also used to render share images).
    @MainActor @ViewBuilder
    func page(go: @escaping (Tab) -> Void) -> some View {
        switch self {
        case .overview: OverviewView(go: go)
        case .cpu: CPUView()
        case .memory: MemoryView()
        case .network: NetworkView()
        case .disk: DiskView()
        case .sensors: SensorsView()
        case .hardware: HardwareView()
        }
    }
}
