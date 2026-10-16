import SwiftUI

struct ProfileAvatar: View {
    let data: Data?
    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64).clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var image: Image? {
        guard let data else { return nil }
        #if os(macOS)
            return NSImage(data: data).map { Image(nsImage: $0) }
        #else
            return UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }
}
