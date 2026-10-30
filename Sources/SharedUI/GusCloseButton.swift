import SwiftUI

/// Viewing sheets dismiss without implying a save or a playback stop.
struct GusCloseButton: View {
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
            Button(action: action) { Image(systemName: "xmark") }
                .accessibilityLabel("Close")
                .gusTVNativeControls()
        #else
            Button("Close", systemImage: "xmark", action: action)
                .labelStyle(.iconOnly)
        #endif
    }
}
