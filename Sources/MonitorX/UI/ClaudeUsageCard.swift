import SwiftUI

struct ClaudeUsageCard: View {
    let usage: ClaudeUsageMonitor
    @Environment(\.isSnapshot) private var isSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label { Text(L("Claude Usage")) } icon: { ProviderLogo(provider: .claude) }
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !isSnapshot {
                    Button {
                        #if APPSTORE
                        usage.refresh()
                        #else
                        usage.queryOAuth(force: true, allowKeychainPrompt: true)
                        #endif
                    } label: {
                        #if !APPSTORE
                        if usage.isRefreshing { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "arrow.clockwise").foregroundStyle(Color.primary) }
                        #else
                        Image(systemName: "arrow.clockwise").foregroundStyle(Color.primary)
                        #endif
                    }
                    .buttonStyle(.plain).help(L("Refresh")).accessibilityLabel(L("Refresh"))
                    #if APPSTORE
                    .disabled(!usage.isConnected)
                    #else
                    .disabled(!usage.usesOAuth || usage.isRefreshing)
                    #endif
                    connectionMenu
                }
            }
            if !isSnapshot && !usage.isConnected {
                #if APPSTORE
                Button(L("Connect quota file")) { usage.connect() }.font(.caption)
                #else
                Button(L("Connect Claude")) { usage.connect() }.font(.caption)
                #endif
            }
            if usage.connectionFailed {
                #if APPSTORE
                Text(L("Couldn't read quota file. Select a valid quota snapshot again.")).font(.caption).foregroundStyle(.orange)
                #else
                Text(usage.errorMessage ?? L("Couldn't configure Claude Code")).font(.caption).foregroundStyle(.orange)
                #endif
            }
            if usage.windows.isEmpty {
                setupMessage
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            } else {
                if usage.isStale {
                    Text(L("Last reading (may be outdated)")).font(.caption).foregroundStyle(.orange)
                }
                ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.duration).foregroundStyle(.secondary)
                            Spacer()
                            Text(L("Remaining: %@", window.remaining.map { Fmt.percent($0 / 100) } ?? "—")).monospacedDigit().fontWeight(.semibold)
                        }.font(.caption)
                        if let remaining = window.remaining {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule().fill(usage.isStale ? Color.gray : (remaining < 10 ? Color.red : Theme.down))
                                        .frame(width: geometry.size.width * remaining / 100)
                                }
                            }.frame(height: 5)
                        }
                        if let reset = window.resetsAt {
                            Text(L("Resets: %@", dateString(reset))).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let date = usage.snapshot?.updatedAt {
                Text(L("Updated: %@", dateString(date))).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
    @ViewBuilder private var setupMessage: some View {
        #if APPSTORE
        Text(L("Connect a quota snapshot file to view usage."))
        #else
        if usage.usesOAuth {
            Text(usage.isRefreshing ? L("Checking Claude Code…") : L("Couldn't query Claude usage. Try again later."))
        } else if !usage.isConnected {
            Text(L("No quota data available"))
        } else {
        switch usage.setupStatus {
        case .checking: Text(L("Checking Claude Code…"))
        case .missing: Text(L("Claude Code is not installed. Open the official installation guide to get started."))
        case .signedOut: Text(L("Claude Code is not signed in. Sign in with your Claude Pro or Max account."))
        case .unsupported: Text(L("This Claude Code login uses API billing. Sign in with Claude Pro or Max to receive subscription usage."))
        case .unavailable: Text(L("Couldn't check Claude Code login. Open Claude Code to continue setup."))
        case .signedIn: Text(L("Waiting for usage. Send a message in Claude Code; usage will appear automatically after the reply. Web and desktop chats don't update this connection."))
        }
        }
        #endif
    }
    private var connectionMenu: some View {
        Menu {
            #if APPSTORE
            Button(L("Connect quota file")) { usage.connect() }
            if usage.isConnected { Button(L("Disconnect quota file")) { usage.disconnect() } }
            #else
            if usage.usesOAuth {
                Label(L("Direct account query enabled"), systemImage: "checkmark")
                Divider()
                Button(L("Stop direct query")) { usage.disconnect() }
            } else {
                Button(L("Enable direct Claude query")) { usage.connect() }
                if usage.isConnected { Button(L("Disconnect Claude Code")) { usage.disconnect() } }
            }
            #endif
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Color.primary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize().help(L("Quota settings")).accessibilityLabel(L("Quota settings"))
    }

    private func dateString(_ seconds: Double) -> String {
        Date(timeIntervalSince1970: seconds).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))
    }
}
