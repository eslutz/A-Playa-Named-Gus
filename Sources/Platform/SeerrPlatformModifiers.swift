import SwiftUI

extension View {
    @ViewBuilder func gusSeerrSetupTitle() -> some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation {
                navigationBarTitleDisplayMode(.inline)
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder func gusSeerrSetupHeading() -> some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation {
                frame(maxWidth: .infinity).multilineTextAlignment(.center)
            } else {
                self
            }
        #else
            self
        #endif
    }

    /// Native large buttons add their own vertical insets around the label.
    @ViewBuilder func gusSeerrActionLabelSizing() -> some View {
        #if os(iOS)
            frame(minHeight: DeviceIdentity.usesIPadPresentation ? 26 : 44)
        #else
            frame(minHeight: 44)
        #endif
    }

    @ViewBuilder func seerrSetupKeyboardDismissal() -> some View {
        #if os(visionOS)
            self
        #else
            scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder func seerrSetupFieldStyle() -> some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation {
                textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(minHeight: 50)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                textFieldStyle(.roundedBorder)
            }
        #elseif os(tvOS)
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

/// Keep the established phone and other-platform heading alignment.
@MainActor
extension HorizontalAlignment {
    static var gusSeerrSetupHeading: HorizontalAlignment {
        #if os(iOS)
            DeviceIdentity.usesIPadPresentation ? .center : .leading
        #else
            .leading
        #endif
    }
}
