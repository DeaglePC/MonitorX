import SwiftUI
import AppKit

/// Renders pages into share images and puts them on the clipboard or saves them as PNG files.
///
/// Pages are rendered offscreen with `ImageRenderer` in snapshot mode (`\.isSnapshot`): full height instead of
/// scrolling, flat cards instead of Liquid Glass, no interactive controls and no serial number.
@MainActor
enum Snapshot {
    static let scale: CGFloat = 2

    struct Context {
        let monitor: SystemMonitor
        let settings: Settings
        let scheme: ColorScheme
        let date = Date()

        @MainActor init(monitor: SystemMonitor, settings: Settings) {
            self.monitor = monitor
            self.settings = settings
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            scheme = dark ? .dark : .light
        }
    }

    /// One page, with a small branded footer.
    static func page(_ tab: Tab, _ ctx: Context) -> CGImage? {
        let view = VStack(spacing: 0) {
            PageShot(tab: tab, ctx: ctx, rounded: false)
            Footer(ctx: ctx).padding(.bottom, 16)
        }
        .background(PageBackground(tab: tab, scheme: ctx.scheme))
        return render(view, ctx)
    }

    /// Every page, packed into balanced columns under a title bar.
    static func allPages(_ ctx: Context) -> CGImage? {
        // Render each page once to learn its height, then balance the columns: tallest page first into the
        // shortest column, then restore tab order inside each column and order columns by their first tab.
        let shots: [(index: Int, image: CGImage)] = Tab.available.enumerated().compactMap { i, tab in
            render(PageShot(tab: tab, ctx: ctx, rounded: true), ctx).map { (i, $0) }
        }
        guard !shots.isEmpty else { return nil }
        let columnCount = shots.count >= 5 ? 3 : min(2, shots.count)
        var columns = Array(repeating: [(index: Int, image: CGImage)](), count: columnCount)
        var heights = Array(repeating: 0, count: columnCount)
        for shot in shots.sorted(by: { $0.image.height > $1.image.height }) {
            let c = heights.indices.min { heights[$0] < heights[$1] }!
            columns[c].append(shot)
            heights[c] += shot.image.height
        }
        let ordered = columns
            .map { $0.sorted { $0.index < $1.index } }
            .sorted { ($0.first?.index ?? .max) < ($1.first?.index ?? .max) }
            .map { $0.map(\.image) }
        return render(Collage(columns: ordered, ctx: ctx), ctx)
    }

    // MARK: rendering

    private static func render(_ view: some View, _ ctx: Context) -> CGImage? {
        let content = view
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, ctx.scheme)
            .environment(\.locale, Localizer.shared.locale)
            .environment(\.layoutDirection, Localizer.shared.layoutDirection)
            .environment(ctx.monitor)
            .environment(ctx.settings)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.cgImage
    }

    // MARK: output

    /// `ImageRenderer` produces 16 bits per channel with alpha; the share images are opaque, so flattening to
    /// 8-bit sRGB without alpha looks identical and makes the PNG roughly 3× smaller.
    private static func flattened(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    private static func png(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: flattened(image) ?? image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)   // 144 dpi
        return rep.representation(using: .png, properties: [:])
    }

    static func copy(_ image: CGImage) -> Bool {
        guard let png = png(image) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        // TIFF (for apps that only read that) is uncompressed and large, so it's produced only on demand.
        item.setDataProvider(tiffProvider, forTypes: [.tiff])
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([item])
    }

    enum SaveResult { case saved(URL), cancelled, failed }

    private static let saveDirKey = "shareSaveDirectory"

    /// Asks where to save (standard save dialog, starting in the last folder used, else the Desktop) and writes a PNG.
    static func save(_ image: CGImage, name: String, date: Date, done: @escaping (SaveResult) -> Void) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = f.string(from: date)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "MonitorX \(name) \(stamp).png"
        panel.directoryURL = UserDefaults.standard.url(forKey: saveDirKey)
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        // The monitor panel floats at pop-up-menu level; the dialog must sit above it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return done(.cancelled) }
            UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: saveDirKey)
            guard let data = png(image), (try? data.write(to: url, options: .atomic)) != nil else { return done(.failed) }
            done(.saved(url))
        }
    }

    private static let tiffProvider = TIFFProvider()

    private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .tiff, let png = item.data(forType: .png) else { return }
            item.setData(NSBitmapImageRep(data: png)?.tiffRepresentation ?? Data(), forType: .tiff)
        }
    }
}

// MARK: - Views

/// A page at panel width and its natural height.
private struct PageShot: View {
    let tab: Tab
    let ctx: Snapshot.Context
    let rounded: Bool

    var body: some View {
        tab.page(go: { _ in })
            .frame(width: PanelController.size.width)
            .background(rounded ? PageBackground(tab: tab, scheme: ctx.scheme) : nil)
            .clipShape(.rect(cornerRadius: rounded ? 26 : 0, style: .continuous))
            .overlay {
                if rounded {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.primary.opacity(ctx.scheme == .dark ? 0.12 : 0.07), lineWidth: 1)
                }
            }
    }
}

/// The panel's look: a neutral base with the page's accent washing in from the top.
private struct PageBackground: View {
    let tab: Tab
    let scheme: ColorScheme

    var body: some View {
        ZStack {
            scheme == .dark ? Color(white: 0.11) : Color(white: 0.955)
            LinearGradient(colors: [tab.accent.opacity(scheme == .dark ? 0.24 : 0.16), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

private struct BrandIcon: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "gauge.with.dots.needle.67percent")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: Tab.overview.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: size * 0.3, style: .continuous))
    }
}

private struct Footer: View {
    let ctx: Snapshot.Context

    var body: some View {
        HStack(spacing: 6) {
            BrandIcon(size: 15)
            Text("MonitorX").fontWeight(.semibold)
            Text("·")
            Text(ctx.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale)))
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

private struct Collage: View {
    static let gap: CGFloat = 20
    let columns: [[CGImage]]
    let ctx: Snapshot.Context

    var body: some View {
        let hw = ctx.monitor.hardware
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                BrandIcon(size: 46)
                    .shadow(color: Theme.cpu.opacity(0.35), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hw.modelName).font(.system(size: 26, weight: .bold, design: .rounded))
                    Text([hw.shortChip, Fmt.bytes(hw.memory), hw.osVersion].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("MonitorX").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(ctx.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale)))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)

            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(columns.indices, id: \.self) { c in
                    VStack(spacing: Self.gap) {
                        ForEach(columns[c].indices, id: \.self) { i in
                            let img = columns[c][i]
                            Image(decorative: img, scale: Snapshot.scale)
                                .shadow(color: .black.opacity(ctx.scheme == .dark ? 0.35 : 0.10), radius: 14, y: 6)
                        }
                    }
                    .frame(width: PanelController.size.width)
                }
            }
        }
        .padding(32)
        .background {
            LinearGradient(colors: ctx.scheme == .dark
                           ? [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.10, green: 0.07, blue: 0.13)]
                           : [Color(red: 0.90, green: 0.93, blue: 1.00), Color(red: 0.98, green: 0.92, blue: 0.96)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
