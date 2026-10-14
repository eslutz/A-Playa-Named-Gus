import SwiftUI
import UniformTypeIdentifiers

/// Keep editing affordances off the television while sharing the browsing experience.
enum CollectionPlatform {
    static var canManage: Bool {
        #if os(tvOS) || os(watchOS)
            false
        #else
            true
        #endif
    }
}

extension View {
    @ViewBuilder func collectionArtworkImporter(isPresented: Binding<Bool>, completion: @escaping (Result<URL, Error>) -> Void) -> some View {
        #if os(tvOS)
            self
        #else
            fileImporter(isPresented: isPresented, allowedContentTypes: [.image], onCompletion: completion)
        #endif
    }

    @ViewBuilder func collectionShortcut(_ key: KeyEquivalent) -> some View {
        #if os(macOS)
            keyboardShortcut(key, modifiers: [.command, .shift])
        #else
            self
        #endif
    }
}
