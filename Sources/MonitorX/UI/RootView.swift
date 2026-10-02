import SwiftUI

/// UI state that must survive the panel being hidden.
@Observable
final class PanelState {
    var isOpen = false
    var tab: Tab = .overview
}

struct RootView: View {
    @Environment(Settings.self) private var settings
    @Environment(PanelState.self) private var state
    @Namespace private var tabNS

    private var tab: Tab { state.tab }

    var body: some View {
        // While the panel is hidden the whole tree is dropped so SwiftUI does no work on every sample.
        if state.isOpen {
            content
        } else {
            Color.clear.frame(width: PanelController.size.width, height: PanelController.size.height)
        }
    }

    private var content: some View {
        ZStack(alignment: .topTrailing) {
            // Soft tint that follows the current page.
            LinearGradient(colors: [tab.accent.opacity(0.20), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.5), value: tab)

            Group {
                switch tab {
                case .overview: OverviewView(go: select)
                case .cpu: CPUView()
                case .memory: MemoryView()
                case .network: NetworkView()
                case .disk: DiskView()
                case .sensors: SensorsView()
                case .hardware: HardwareView()
                }
            }
            .id(tab)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }

            settingsMenu
                .padding(.top, 16).padding(.trailing, 16)
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
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

    // MARK: settings

    private var settingsMenu: some View {
        @Bindable var s = settings
        @Bindable var loc = Localizer.shared
        return Menu {
            Section(L("Show in Menu Bar")) {
                Toggle(L("CPU"), isOn: $s.showCPU)
                Toggle(L("Memory"), isOn: $s.showMemory)
                Toggle(L("Network Speed"), isOn: $s.showNetwork)
                Toggle(L("Disk Activity"), isOn: $s.showDisk)
            }
            Section {
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
