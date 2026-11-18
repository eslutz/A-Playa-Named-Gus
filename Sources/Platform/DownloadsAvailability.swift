import SwiftUI

enum DownloadsAvailability {
    static var isSupported: Bool {
        #if os(tvOS)
            return false
        #else
            return true
        #endif
    }

    static var selectAllPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .automatic
        #endif
    }

    #if os(watchOS)
        static let accountStorageLimitBytes: Int64 = 2 * 1024 * 1024 * 1024
    #endif
}

extension View {
    @ViewBuilder
    func gusDownloadSelectionMode(_ selecting: Bool) -> some View {
        #if os(iOS) || os(visionOS)
            environment(\.editMode, .constant(selecting ? .active : .inactive))
                .navigationBarBackButtonHidden(selecting)
        #else
            self
        #endif
    }

    @ViewBuilder
    func gusDownloadSwipeDelete(action: @escaping () -> Void) -> some View {
        #if os(tvOS)
            self
        #else
            swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: action) {
                    Label("Delete", systemImage: "trash")
                }
            }
        #endif
    }
}
