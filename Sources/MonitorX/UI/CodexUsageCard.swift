import SwiftUI

struct CodexUsageCard: View {
    let usage: CodexUsageMonitor
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label { Text(L("Codex Usage")) } icon: { ProviderLogo(provider: .codex) }
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !isSnapshot {
                    Button { usage.refresh() } label: {
                        if usage.isRefreshing { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "arrow.clockwise").foregroundStyle(Color.primary) }
                    }
                    .buttonStyle(.plain)
                    .disabled(usage.isRefreshing)
                    .help(L("Refresh"))
                    .accessibilityLabel(L("Refresh"))
                    connectionMenu
                }
            }
            if !isSnapshot {
                #if APPSTORE
                if !usage.isConnected {
                    Button(L("Connect quota file")) { usage.connect() }.font(.caption)
                    Text(L("Connect a quota snapshot file to view usage.")).font(.caption).foregroundStyle(.secondary)
                }
                #else
                if !usage.usesOAuth && usage.buckets.isEmpty {
                    Button(L("Enable direct Codex query")) { usage.connect() }.font(.caption)
                }
                #endif
            }
            if usage.errorKey != nil {
                Text(usage.errorMessage)
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usage.isStale && usage.updatedAt != nil {
                Text(L("Last reading (may be outdated)")).font(.caption).foregroundStyle(.orange)
            }
            ForEach(Array(usage.buckets.enumerated()), id: \.offset) { _, bucket in
                if usage.buckets.count > 1 { Text(bucket.title).font(.caption.bold()) }
                ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.duration).foregroundStyle(.secondary)
                            Spacer()
                            Text(L("Remaining: %@", window.remaining.map { Fmt.percent($0 / 100) } ?? "—"))
                                .fontWeight(.semibold).monospacedDigit()
                        }
                        .font(.caption)
                        if let remaining = window.remaining {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule().fill(remaining < 10 ? Color.red : (remaining < 25 ? Color.orange : Theme.down))
                                        .frame(width: geometry.size.width * remaining / 100)
                                }
                            }
                            .frame(height: 5)
                        }
                        Text(L("Resets: %@", window.resetsAt.map { dateString(Date(timeIntervalSince1970: $0)) } ?? "—"))
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if usage.buckets.flatMap(\.windows).isEmpty && usage.errorKey == nil {
                Text(usage.isRefreshing ? L("Collecting…") : L("No quota data available"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let date = usage.updatedAt {
                Text(L("Updated: %@", dateString(date)))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
                Button(L("Use CLI only")) { usage.disconnect() }
            } else {
                Button(L("Enable direct Codex query")) { usage.connect() }
            }
            #endif
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Color.primary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize().help(L("Quota settings")).accessibilityLabel(L("Quota settings"))
    }

    private func dateString(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))
    }
}
