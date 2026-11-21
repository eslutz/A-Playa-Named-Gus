import SwiftUI

/// One host per signed-in browsing window. The session grants a prompt to only one host.
struct IntelligencePromptHost: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @State private var host = UUID()
    @State private var shown: IntelligencePrompt?
    @State private var isPresented = false
    @State private var childPresentation = false
    @State private var anchor = IntelligenceWindowAnchor()
    let blocked: Bool

    private struct Presentation: Equatable {
        let pending: IntelligencePrompt?
        let shown: IntelligencePrompt?
        let active: Bool
        let blocked: Bool
    }

    private struct LocaleCheck: Equatable {
        let active: Bool
        let cloudReady: Bool
        let locale: Locale
    }

    func body(content: Content) -> some View {
        let access = session.intelligenceAccess
        let state = Presentation(pending: access.availablePrompt(for: host), shown: shown, active: phase == .active, blocked: blocked || childPresentation)
        content
            .background { IntelligenceWindowReader(anchor: anchor).frame(width: 0, height: 0) }
            .onPreferenceChange(IntelligencePresentationKey.self) { childPresentation = $0 }
            .task(id: LocaleCheck(active: phase == .active, cloudReady: access.cloudReady, locale: locale)) {
                if phase == .active, access.cloudReady {
                    await access.refreshCloudLocale()
                    for delay in [3, 15] {
                        guard !access.hasCheckedCloudLocale else { return }
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        guard !Task.isCancelled, !access.hasCheckedCloudLocale else { return }
                        await access.refreshCloudLocale()
                    }
                }
            }
            .task(id: state) {
                if let shown = state.shown {
                    if state.pending != shown || !state.active || state.blocked {
                        access.releasePrompt(from: host)
                        isPresented = false
                    }
                    return
                }
                guard state.active, !state.blocked, state.pending != nil else { return }
                // A native alert, inspector sheet or player can belong to a different
                // presentation anchor. Wait only while this window has a pending prompt.
                while !Task.isCancelled {
                    if anchor.canPresent, !session.playbackReports.hasActivePlayback {
                        if let prompt = access.claimPrompt(for: host) {
                            shown = prompt
                            isPresented = true
                        }
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                // A normal swipe/Escape dismissal records the negative choice. A
                // background or account transition already released this host's claim.
                if let shown, phase == .active, !blocked, !childPresentation {
                    access.respond(to: shown, from: host, allow: false)
                }
                access.releasePrompt(from: host)
                shown = nil
            }) {
                if let shown {
                    IntelligencePromptView(prompt: shown) { allow in
                        access.respond(to: shown, from: host, allow: allow)
                        isPresented = false
                    }
                }
            }
            .onDisappear {
                access.releasePrompt(from: host)
                isPresented = false
            }
    }
}

private struct IntelligencePromptView: View {
    let prompt: IntelligencePrompt
    let respond: (Bool) -> Void

    var body: some View {
        #if os(iOS)
            IntelligencePhonePrompt(kind: prompt == .forYou ? .forYou : .cloud, respond: respond)
        #else
            platformSheet
        #endif
    }

    #if !os(iOS)
        private var platformSheet: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(prompt == .forYou ? LocalizedStringKey("Enable For You?") : LocalizedStringKey("Allow Private Cloud Compute?"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if prompt == .forYou {
                    Text("Get recommendations based on your Jellyfin favorites and playback history. You can change this in Gus Settings → Library Intelligence → Show For You.")
                        .accessibilityIdentifier("Intelligence.prompt.message")
                } else {
                    Text("Apple can process submitted searches and, when For You is enabled, selected titles, descriptions, and viewing interests. Requests use your daily quota. You can change this in Gus Settings → Library Intelligence → Allow Private Cloud Compute.")
                        .accessibilityIdentifier("Intelligence.prompt.message")
                }
                Button(prompt == .forYou ? LocalizedStringKey("Enable For You") : LocalizedStringKey("Allow Private Cloud Compute")) { respond(true) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("Intelligence.prompt.allow")
                Button("Not Now", role: .cancel) { respond(false) }
                    .accessibilityIdentifier("Intelligence.prompt.decline")
            }
            .padding()
            #if os(macOS)
                .frame(minWidth: 360, idealWidth: 420)
            #else
                .scrollWhenNeeded()
            #endif
        }
    #endif
}

#if os(iOS)
    private struct IntelligencePhonePrompt: View {
        enum Kind {
            case forYou, cloud, forYouSync

            var title: LocalizedStringKey {
                switch self {
                case .forYou: "Enable For You?"
                case .cloud: "Allow Private Cloud Compute?"
                case .forYouSync: "Sync For You to Apple TV?"
                }
            }

            var message: LocalizedStringKey {
                switch self {
                case .forYou: "Get recommendations based on your Jellyfin favorites and playback history."
                case .cloud: "Apple can process submitted searches and, when For You is enabled, selected titles, descriptions, and viewing interests. Requests use your daily quota."
                case .forYouSync: "Gus saves the Jellyfin item IDs for your ranked recommendations in your private iCloud storage. Your iPhone and Apple TV must use the same iCloud and Jellyfin accounts."
                }
            }

            var settingsPath: LocalizedStringKey {
                switch self {
                case .forYou: "Gus Settings → Library Intelligence → Show For You."
                case .cloud: "Gus Settings → Library Intelligence → Allow Private Cloud Compute."
                case .forYouSync: "Gus Settings → Library Intelligence → Sync For You to Apple TV."
                }
            }

            var primaryAction: LocalizedStringKey {
                switch self {
                case .forYou: "Enable For You"
                case .cloud: "Allow Private Cloud Compute"
                case .forYouSync: "Enable Sync"
                }
            }

            var symbol: String {
                switch self {
                case .forYou: "sparkles"
                case .cloud: "icloud"
                case .forYouSync: "appletv"
                }
            }
        }

        @Environment(\.dynamicTypeSize) private var dynamicType
        let kind: Kind
        let respond: (Bool) -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: kind.symbol)
                            .font(.title)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(kind.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(kind.message)
                            .accessibilityIdentifier("Intelligence.prompt.message")
                    }

                    Label {
                        Text(kind.settingsPath)
                            .accessibilityIdentifier("Intelligence.prompt.settingsPath")
                    } icon: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.primary)

                    VStack(spacing: 8) {
                        Button {
                            respond(true)
                        } label: {
                            Text(kind.primaryAction)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .gusPhoneProminentForeground()
                        }
                        .buttonStyle(.borderedProminent)
                        .gusPhoneActionTint()
                        .accessibilityIdentifier("Intelligence.prompt.allow")

                        Button(role: .cancel) {
                            respond(false)
                        } label: {
                            Text("Not Now")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .accessibilityIdentifier("Intelligence.prompt.decline")
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .presentationDetents(dynamicType.isAccessibilitySize || kind == .cloud ? [.large] : [.medium, .large])
            .presentationBackground(Color(uiColor: .secondarySystemBackground))
            .presentationDragIndicator(.visible)
        }
    }

    private struct ForYouSyncConsentSheet: View {
        @Environment(SessionStore.self) private var session
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            IntelligencePhonePrompt(kind: .forYouSync) { allow in
                if allow {
                    session.setForYouSyncEnabled(true)
                }
                dismiss()
            }
        }
    }

    extension View {
        func forYouSyncConsent(isPresented: Binding<Bool>) -> some View {
            sheet(isPresented: isPresented) { ForYouSyncConsentSheet() }
                .defersIntelligencePrompt(while: isPresented.wrappedValue)
        }
    }
#endif

private extension View {
    func scrollWhenNeeded() -> some View {
        ViewThatFits(in: .vertical) {
            fixedSize(horizontal: false, vertical: true)
            ScrollView { self }
        }
    }
}

private struct IntelligencePresentationKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Announces work that owns a presentation or is preparing one, including
    /// WatchKit destinations whose window hierarchy isn't available to SwiftUI.
    func defersIntelligencePrompt(while presented: Bool) -> some View {
        preference(key: IntelligencePresentationKey.self, value: presented)
    }
}

@MainActor private final class IntelligenceWindowAnchor {
    #if os(macOS)
        weak var view: NSView?
        var canPresent: Bool {
            guard let window = view?.window else { return false }
            return window.isKeyWindow && window.attachedSheet == nil && NSApp.modalWindow == nil
        }
    #elseif os(iOS) || os(visionOS)
        weak var view: UIView?
        var canPresent: Bool {
            guard let window = view?.window, window.isKeyWindow else { return false }
            // The system search controller can remain active after a search submit.
            var presented = window.rootViewController?.presentedViewController
            while let search = presented as? UISearchController {
                presented = search.presentedViewController
            }
            return presented == nil
        }
    #else
        var canPresent: Bool {
            true
        }
    #endif
}

#if os(macOS)
    private struct IntelligenceWindowReader: NSViewRepresentable {
        let anchor: IntelligenceWindowAnchor
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            anchor.view = view
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
#elseif os(iOS) || os(visionOS)
    private struct IntelligenceWindowReader: UIViewRepresentable {
        let anchor: IntelligenceWindowAnchor
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            anchor.view = view
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {}
    }
#else
    private struct IntelligenceWindowReader: View {
        let anchor: IntelligenceWindowAnchor
        var body: some View {
            EmptyView()
        }
    }
#endif
