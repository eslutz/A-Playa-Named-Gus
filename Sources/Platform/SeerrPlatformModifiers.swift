import SwiftUI

extension View {
    @ViewBuilder func seerrFormStyle() -> some View {
        #if os(visionOS)
            formStyle(.automatic)
        #else
            formStyle(.grouped)
        #endif
    }
}
