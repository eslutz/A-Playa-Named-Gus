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

extension ToolbarItemPlacement {
    static var seerrSecondaryAction: ToolbarItemPlacement {
        #if os(tvOS)
            .automatic
        #else
            .secondaryAction
        #endif
    }
}
