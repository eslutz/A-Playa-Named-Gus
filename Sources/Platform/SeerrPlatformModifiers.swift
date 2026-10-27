import SwiftUI

extension View {
    @ViewBuilder func seerrSetupKeyboardDismissal() -> some View {
        #if os(visionOS)
            self
        #else
            scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder func seerrSetupFieldStyle() -> some View {
        #if os(tvOS)
            self
        #else
            textFieldStyle(.roundedBorder)
        #endif
    }

    @ViewBuilder func seerrHiddenRowSeparator() -> some View {
        #if os(tvOS)
            self
        #else
            listRowSeparator(.hidden)
        #endif
    }

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
