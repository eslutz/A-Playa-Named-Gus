import SwiftUI

/// Shared iPhone treatments from the reviewed Sketch component page.
/// Native controls retain their platform materials, accessibility, and interaction.
extension View {
    func gusIPhoneCanvas() -> some View {
        modifier(IPhoneCanvasModifier())
    }
}

private struct IPhoneCanvasModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
            if widthClass == .compact {
                content
                    .background(Color(uiColor: .systemBackground))
            } else {
                content
            }
        #else
            content
        #endif
    }
}

#if os(iOS)
    struct GusOnboardingHeader: View {
        var body: some View {
            HStack(alignment: .top) {
                Text("Gus").font(.title.bold())
                Spacer(minLength: 20)
                Image("GusWelcomeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 154, height: 154)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 154, alignment: .top)
        }
    }

    struct GusOnboardingField<Content: View>: View {
        let title: LocalizedStringKey
        @ViewBuilder var content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.subheadline)
                content()
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(minHeight: 50)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
#endif

extension View {
    func gusIPhoneOnly() -> some View {
        modifier(IPhoneOnlyModifier())
    }

    func gusPhonePagePadding() -> some View {
        modifier(IPhonePagePaddingModifier())
    }

    func gusPhoneRailWidth(backdrop: Bool, fallback: CGFloat) -> some View {
        modifier(IPhoneRailWidthModifier(backdrop: backdrop, fallback: fallback))
    }

    func gusPhoneHeroCopy() -> some View {
        modifier(IPhoneHeroCopyModifier())
    }

    func gusPhoneProminentForeground() -> some View {
        modifier(IPhoneProminentForegroundModifier())
    }

    func gusPhoneActionTint() -> some View {
        modifier(IPhoneActionTintModifier())
    }
}

private struct IPhoneOnlyModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            if widthClass == .compact {
                content
            }
        #endif
    }
}

private struct IPhonePagePaddingModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            content.padding(.horizontal, widthClass == .compact ? 24 : 16).padding(.vertical, 16)
        #else
            content.padding()
        #endif
    }
}

private struct IPhoneRailWidthModifier: ViewModifier {
    let backdrop: Bool
    let fallback: CGFloat
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            content.frame(width: widthClass == .compact ? (backdrop ? 260 : 160) : fallback)
        #else
            content.frame(width: fallback)
        #endif
    }
}

private struct IPhoneHeroCopyModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            if widthClass == .compact {
                content
            } else {
                content.padding(12).background(.black, in: RoundedRectangle(cornerRadius: 8))
            }
        #else
            content.padding(12).background(.black, in: RoundedRectangle(cornerRadius: 8))
        #endif
    }
}

private struct IPhoneProminentForegroundModifier: ViewModifier {
    @Environment(\.gusThemeForeground) private var foreground
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            content.foregroundStyle(foreground)
        #else
            content.foregroundStyle(Color.gusProminentActionForeground)
        #endif
    }
}

private struct IPhoneActionTintModifier: ViewModifier {
    @Environment(\.gusThemeFill) private var fill
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            content.tint(fill)
        #else
            content.tint(.accentColor)
        #endif
    }
}

#if os(iOS)
    import MediaPlayer

    /// System volume ownership stays with MediaPlayer, including route restrictions.
    struct GusSystemVolumeControl: UIViewRepresentable {
        func makeUIView(context: Context) -> MPVolumeView {
            MPVolumeView(frame: .zero)
        }

        func updateUIView(_ uiView: MPVolumeView, context: Context) {}
    }
#endif

struct AudioTransportGlyph: View {
    let isPlaying: Bool
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 56
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    var body: some View {
        #if os(iOS)
            if widthClass == .compact {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title)
            } else {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: size))
            }
        #else
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: size))
        #endif
    }
}

/// Compact-phone styling leaves the existing wider-platform treatments intact.
extension View {
    func gusPhoneRailHeading() -> some View {
        modifier(IPhoneRailHeadingModifier())
    }

    func gusPhoneActionLabelHeight() -> some View {
        modifier(IPhoneActionLabelHeightModifier())
    }

    func gusPhoneHeroAccessoryStyle() -> some View {
        modifier(IPhoneHeroAccessoryModifier())
    }

    func gusPhoneAudioTransportColor() -> some View {
        modifier(IPhoneAudioTransportColorModifier())
    }

    func gusPhonePlainButtonStyle() -> some View {
        modifier(IPhonePlainButtonModifier())
    }
}

private struct IPhoneRailHeadingModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            content.font(widthClass == .compact ? .title3.bold() : .title2.bold())
        #else
            content.font(.title2.bold())
        #endif
    }
}

private struct IPhoneActionLabelHeightModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            content.frame(minHeight: widthClass == .compact ? 24 : 44)
        #else
            content.frame(minHeight: 44)
        #endif
    }
}

private struct IPhoneHeroAccessoryModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            if widthClass == .compact {
                content.tint(.white).buttonBorderShape(.circle)
            } else {
                content.buttonBorderShape(.capsule)
            }
        #else
            content.buttonBorderShape(.capsule)
        #endif
    }
}

private struct IPhoneAudioTransportColorModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            if widthClass == .compact {
                content.foregroundStyle(.tint)
            } else {
                content
            }
        #else
            content
        #endif
    }
}

private struct IPhonePlainButtonModifier: ViewModifier {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
            if widthClass == .compact {
                content.buttonStyle(.plain)
            } else {
                content
            }
        #else
            content
        #endif
    }
}
