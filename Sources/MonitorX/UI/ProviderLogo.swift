import SwiftUI
import AppKit

/// Bundled provider glyphs, shared by the live cards and image exports.
struct ProviderLogo: View {
    enum Provider: String, CaseIterable { case codex, claude }
    let provider: Provider

    private static let images: [Provider: NSImage] = Dictionary(uniqueKeysWithValues: Provider.allCases.map { provider in
        let url = Bundle.main.url(forResource: provider.rawValue, withExtension: "pdf", subdirectory: "BrandIcons")
            ?? Bundle.module.url(forResource: provider.rawValue, withExtension: "pdf", subdirectory: "BrandIcons")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = true
        return (provider, image)
    })

    var body: some View {
        Image(nsImage: Self.images[provider]!)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(provider == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color.primary)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}
