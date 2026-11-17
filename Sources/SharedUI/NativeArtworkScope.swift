import SwiftUI

extension View {
    /// OS26 keeps the native AsyncImage fallback. Its API does not expose session
    /// injection; OS27 uses the empirically verified lease-owned native transport.
    @ViewBuilder
    func gusArtworkTransport(_ transport: NativeArtworkTransport) -> some View {
        if #available(iOS 27, macOS 27, tvOS 27, visionOS 27, watchOS 27, *) {
            asyncImageURLSession(transport.session)
        } else {
            self
        }
    }
}
