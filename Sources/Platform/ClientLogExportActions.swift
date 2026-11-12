import SwiftUI

struct ClientLogExportActions: View {
    let url: URL

    var body: some View {
        #if os(tvOS)
            Text("Export saved on this Apple TV. On a paired Mac, use Xcode’s Devices and Simulators to download Gus’s app container. Find Gus-client-logs.json in Library/Application Support/A Playa Named Gus. This requires a development-installed app; TestFlight may not allow container download.")
        #else
            ShareLink(item: url) {
                Label("Share Client Logs", systemImage: "square.and.arrow.up")
            }
        #endif
    }
}
