import SwiftUI

extension View {
    /// Presents the offline-download store's error message as an alert, clearing it on
    /// dismiss. Shared by every surface that can start or manage downloads.
    func downloadErrorAlert(_ downloads: OfflineDownloadStore) -> some View {
        alert(
            "Download Failed",
            isPresented: Binding(
                get: { downloads.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        downloads.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                downloads.clearError()
            }
        } message: {
            Text(downloads.errorMessage ?? "")
        }
    }
}
