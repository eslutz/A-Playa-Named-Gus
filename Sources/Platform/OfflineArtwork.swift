import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A file-only artwork surface. Remote URLs are rejected, so offline browsing cannot
/// trigger AsyncImage/provider requests when an image is absent.
struct OfflineArtwork: View {
    let url: URL?
    let systemImage: String
    @State private var image: Image?

    var body: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                GeometryReader { geometry in
                    if let image {
                        image.resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Image(systemName: systemImage).foregroundStyle(.secondary)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url, url.isFileURL, let data = try? Data(contentsOf: url) else { return }
            #if os(macOS)
                if let decoded = NSImage(data: data) {
                    image = Image(nsImage: decoded)
                }
            #else
                if let decoded = UIImage(data: data) {
                    image = Image(uiImage: decoded)
                }
            #endif
        }
    }
}
