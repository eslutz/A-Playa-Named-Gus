import SwiftUI

/// Toolbar symbols remain native, with their full spoken names retained.
/// Other platforms keep the original Label presentation.
/// Set the accessible name on the enclosing Button or Menu as well: native
/// tvOS toolbar containers do not always promote a child image label.
struct GusToolbarLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tvSystemImage: String?

    init(_ title: LocalizedStringKey, systemImage: String, tvSystemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tvSystemImage = tvSystemImage
    }

    var body: some View {
        #if os(tvOS)
            Image(systemName: tvSystemImage ?? systemImage).accessibilityLabel(Text(title))
        #else
            Label(title, systemImage: systemImage)
        #endif
    }
}

extension View {
    @ViewBuilder func gusTVNativeControls() -> some View {
        #if os(tvOS)
            if #available(tvOS 27.0, *) {
                self
            } else {
                buttonStyle(.bordered).tint(nil)
            }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVToolbarIcon() -> some View {
        #if os(tvOS)
            labelStyle(.iconOnly).gusTVNativeControls()
        #else
            self
        #endif
    }

    /// Keep TV presentation and focus divergence outside the shared feature views.
    @ViewBuilder func gusTVFocus(id: String, section: String, ids: [String], initial: Bool = false, item: MediaItem? = nil, entry: NextUpEntry? = nil, context: String? = nil) -> some View {
        #if os(tvOS)
            modifier(TVFocusModifier(id: id, section: section, ids: ids, initial: initial, item: item, entry: entry, context: context ?? section))
        #else
            self
        #endif
    }

    /// Each navigation stack and independent presentation owns its native defaults.
    @ViewBuilder func gusTVFocusScope() -> some View {
        #if os(tvOS)
            modifier(TVFocusScopeModifier())
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVBrowsingBackdrop() -> some View {
        #if os(tvOS)
            gusTVCanvas()
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVCanvas() -> some View {
        #if os(tvOS)
            modifier(TVOpaqueCanvas())
        #else
            self
        #endif
    }

    /// Read-only rails still need native focus targets so the remote can scroll to them.
    @ViewBuilder func gusTVFocusableInfo() -> some View {
        #if os(tvOS)
            accessibilityElement(children: .combine)
                .hoverEffect(.highlight)
                .focusable()
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVDetailCanvas() -> some View {
        #if os(tvOS)
            gusTVCanvas()
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVPagePadding() -> some View {
        #if os(tvOS)
            padding(.horizontal, 64).padding(.vertical, 32)
        #else
            gusPhonePagePadding()
        #endif
    }

    @ViewBuilder func gusTVRailPadding() -> some View {
        #if os(tvOS)
            padding(.vertical, 32).padding(.horizontal, 24)
        #else
            padding(.vertical, 4)
        #endif
    }

    @ViewBuilder func gusTVDetailTitle() -> some View {
        #if os(tvOS)
            toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVContentHeading(_ title: String) -> some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 32) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                self
            }
        #else
            self
        #endif
    }

    /// Inset labels within native artwork cards without adding a bezel around the image.
    @ViewBuilder func gusTVCardCaption() -> some View {
        #if os(tvOS)
            padding(.horizontal, 16).padding(.bottom, 16)
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVPosterTitle() -> some View {
        #if os(tvOS)
            lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        #else
            lineLimit(1)
        #endif
    }

    /// All platforms anchor progress to the artwork, never to variable-height captions.
    func gusTVArtworkStatus(item: MediaItem?, progressID: String = "") -> some View {
        overlay(alignment: .bottom) {
            if let progress = item?.playbackProgress, progress > 0, progress < 1 {
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(12)
                    .accessibilityLabel("Playback progress")
                    .accessibilityIdentifier(progressID)
            }
        }
    }

    @ViewBuilder func gusTVBrowseViewport() -> some View {
        #if os(tvOS)
            ignoresSafeArea(.container, edges: .horizontal)
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVRailViewport() -> some View {
        #if os(tvOS)
            scrollClipDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
        #else
            self
        #endif
    }

    @ViewBuilder func gusDetailActionLabel() -> some View {
        #if os(tvOS)
            labelStyle(TVDetailActionLabelStyle())
                .frame(maxWidth: .infinity, minHeight: DetailActionMetrics.minimumLabelHeight)
        #else
            labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, minHeight: DetailActionMetrics.minimumLabelHeight)
        #endif
    }

    /// Share focus order across the primary action, common icons, overflow and synopsis.
    func gusTVDetailActionFocus(id: String, item: MediaItem, initial: Bool = false) -> some View {
        gusTVFocus(id: id, section: "detail:" + ItemRef(item: item).id, ids: TVDetailActionOrder.ids, initial: initial, item: item)
    }
}

#if os(tvOS)
    private struct TVFocusNamespaceKey: EnvironmentKey {
        static var defaultValue: Namespace.ID? {
            nil
        }
    }

    private extension EnvironmentValues {
        var gusTVFocusNamespace: Namespace.ID? {
            get { self[TVFocusNamespaceKey.self] }
            set { self[TVFocusNamespaceKey.self] = newValue }
        }
    }

    private struct TVFocusScopeModifier: ViewModifier {
        @Namespace private var namespace

        func body(content: Content) -> some View {
            content
                .focusScope(namespace)
                .environment(\.gusTVFocusNamespace, namespace)
        }
    }

    private struct TVDetailActionLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 10) {
                configuration.icon.font(.title3).frame(height: 48)
                configuration.title.font(.caption2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 112)
        }
    }

    private struct TVFocusedMediaKey: FocusedValueKey { typealias Value = MediaItem }
    private struct TVFocusedEntryKey: FocusedValueKey { typealias Value = NextUpEntry }
    extension FocusedValues {
        var gusTVMedia: MediaItem? {
            get { self[TVFocusedMediaKey.self] }
            set { self[TVFocusedMediaKey.self] = newValue }
        }

        var gusTVEntry: NextUpEntry? {
            get { self[TVFocusedEntryKey.self] }
            set { self[TVFocusedEntryKey.self] = newValue }
        }
    }

    private struct TVFocusModifier: ViewModifier {
        @Environment(RootNavigationState.self) private var root
        @Environment(\.gusTVFocusNamespace) private var namespace
        @FocusState private var focused: Bool
        let id: String
        let section: String
        let ids: [String]
        let initial: Bool
        let item: MediaItem?
        let entry: NextUpEntry?
        let context: String

        func body(content: Content) -> some View {
            nativePreference(observedContent(content))
                .onChange(of: restorationRequest, initial: true) { _, request in
                    guard let request,
                          root.tvFocus.restorationRequest(context: context) == request,
                          prefersFocus else { return }
                    if focused {
                        // An unchanged binding will not emit another onChange.
                        rememberFocusedTarget()
                    } else {
                        // Native focus is verified separately from this request.
                        focused = true
                    }
                }
        }

        private var prefersFocus: Bool {
            root.tvFocus.restoredID(section: section, context: context, ids: ids, initial: initial) == id
        }

        private var restorationRequest: UUID? {
            prefersFocus ? root.tvFocus.restorationRequest(context: context) : nil
        }

        @ViewBuilder private func nativePreference<FocusContent: View>(_ content: FocusContent) -> some View {
            if let namespace {
                content
                    .prefersDefaultFocus(prefersFocus, in: namespace)
            } else {
                content
            }
        }

        private func observedContent(_ content: Content) -> some View {
            content
                .focused($focused)
                .focusedValue(\.gusTVMedia, item)
                .focusedValue(\.gusTVEntry, entry)
                .onChange(of: focused) { _, value in
                    guard value else { return }
                    rememberFocusedTarget()
                }
        }

        private func rememberFocusedTarget() {
            guard let index = ids.firstIndex(of: id) else { return }
            if root.tvFocus.remember(id: id, index: index, section: section, context: context, ids: ids) {
                root.scrollAnchors[section] = id
            }
        }
    }

#endif

#if os(tvOS)
    private struct TVOpaqueCanvas: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            content.background {
                (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()
            }
        }
    }
#endif

@MainActor extension RootNavigationState {
    func restoreTVDetailFocus(item: MediaItem, openerID: String = TVDetailActionOrder.moreID) {
        #if os(tvOS)
            guard let index = TVDetailActionOrder.ids.firstIndex(of: openerID) else { return }
            let context = "detail:" + ItemRef(item: item).id
            tvFocus.requestRestoration(context: context, section: context, bookmark: TVFocusBookmark(id: openerID, index: index))
        #endif
    }
}
