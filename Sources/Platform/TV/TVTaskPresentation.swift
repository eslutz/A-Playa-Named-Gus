import SwiftUI

extension View {
    @ViewBuilder func gusTVExitTask(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
            onExitCommand(perform: action)
        #else
            self
        #endif
    }

    /// Multi-field TV tasks need the entire viewport for the system keyboard.
    @ViewBuilder func gusTVTask<TaskContent: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> TaskContent) -> some View {
        #if os(tvOS)
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) { content().modifier(TVTaskAppearance()) }
        #else
            sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder func gusTVTask<Item: Identifiable, TaskContent: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> TaskContent) -> some View {
        #if os(tvOS)
            fullScreenCover(item: item, onDismiss: onDismiss) { content($0).modifier(TVTaskAppearance()) }
        #else
            sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(tvOS)
    private struct TVTaskAppearance: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            content.gusTVCanvas().preferredColorScheme(colorScheme)
        }
    }

    struct TVOnboardingLayout<Intro: View, Fields: View>: View {
        @ViewBuilder let intro: Intro
        @ViewBuilder let fields: Fields

        var body: some View {
            HStack(alignment: .center, spacing: 80) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack {
                            Text("Gus").font(.title.bold())
                            Spacer()
                            Image("GusWelcomeIcon").resizable().scaledToFit()
                                .frame(width: 154, height: 154).accessibilityHidden(true)
                        }
                        intro
                    }
                    .padding(.vertical, 48)
                }
                .frame(maxWidth: 500)
                fields.frame(maxWidth: 760, maxHeight: .infinity)
            }
            .padding(64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gusTVCanvas()
        }
    }
#endif

/// Preserve the shared order while bringing TV title actions above the fold.
struct GusTVMediaDetailLayout<Artwork: View, Summary: View, Details: View>: View {
    @ViewBuilder let artwork: Artwork
    @ViewBuilder let summary: Summary
    @ViewBuilder let details: Details

    var body: some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 48) {
                HStack(alignment: .top, spacing: 64) {
                    artwork.frame(width: 400)
                    VStack(alignment: .leading, spacing: 28) { summary }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusSection()
                }
                details
            }
            .padding(48)
        #else
            VStack(alignment: .leading, spacing: 28) {
                artwork
                summary
                details
            }
        #endif
    }
}

extension View {
    @ViewBuilder func gusTVRequestButtonStyle() -> some View {
        #if os(tvOS)
            buttonStyle(.bordered).tint(nil)
        #else
            buttonStyle(.borderedProminent)
        #endif
    }
}
