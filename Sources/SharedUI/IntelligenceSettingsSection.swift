import SwiftUI

struct IntelligenceSettingsSection: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        #if !os(tvOS)
            let access = session.intelligenceAccess
            let preferences = session.intelligencePreferences
            if access.supportsSearch || access.supportsCloud || preferences.recommendationsEnabled {
                Section {
                    let label = Label("Library Intelligence", systemImage: "sparkles")
                    #if os(watchOS)
                        let link = NavigationLink { LibraryIntelligenceSettingsView() } label: { label }
                    #else
                        let link = NavigationLink(value: GusRoute.screen(.libraryIntelligence)) { label }
                    #endif
                    link.accessibilityIdentifier("Settings.libraryIntelligence")
                }
            }
        #endif
    }
}

#if !os(tvOS)
    struct LibraryIntelligenceSettingsView: View {
        @Environment(SessionStore.self) private var session

        var body: some View {
            let access = session.intelligenceAccess
            let preferences = session.intelligencePreferences
            let needsCloudConsent = access.requiresCloud && preferences.cloudDecision == false
            Form {
                if access.supportsSearch {
                    Section {
                        Toggle("Natural Language Search", isOn: Binding(
                            get: { preferences.naturalSearchEnabled },
                            set: { access.setNaturalSearchEnabled($0) }
                        ))
                        .accessibilityIdentifier("Intelligence.naturalSearch")
                    } footer: {
                        Text("Search in your own words with help from Apple’s models.")
                    }
                }
                if access.supportsCloud {
                    Section {
                        Toggle("Allow Private Cloud Compute", isOn: Binding(
                            get: { preferences.cloudEnabled },
                            set: { access.setCloudEnabled($0) }
                        ))
                        .accessibilityIdentifier("Intelligence.privateCloud")
                    } footer: {
                        if needsCloudConsent {
                            Text("Turn on Allow Private Cloud Compute to use natural-language search and For You on this device.")
                        } else {
                            Text("When enabled, Gus can send search text, selected catalog details, and taste signals to Apple’s Private Cloud Compute using your daily quota.")
                        }
                    }
                }
                if access.supportsSearch || preferences.recommendationsEnabled {
                    Section {
                        Toggle("Show For You", isOn: Binding(
                            get: { preferences.recommendationsEnabled },
                            set: { access.setForYouEnabled($0) }
                        ))
                        .disabled((!access.canOfferForYou || needsCloudConsent) && !preferences.recommendationsEnabled)
                        .accessibilityIdentifier("Intelligence.forYou")
                    } footer: {
                        Text("For You uses this account’s favorites and activity to suggest media.")
                    }
                }
            }
            .navigationTitle("Library Intelligence")
        }
    }
#endif

#if os(iOS) || os(tvOS)
    struct ForYouSyncSetting: View {
        @Environment(SessionStore.self) private var session
        #if os(iOS)
            @State private var showingConsent = false
        #endif

        var body: some View {
            let preferences = session.intelligencePreferences
            #if os(tvOS)
                SyncSettingRow(title: "Show Synced For You", isOn: Binding(
                    get: { preferences.forYouSyncEnabled },
                    set: { session.setForYouSyncEnabled($0) }
                ), identifier: "Intelligence.forYouSync") {
                    Text("Enable Sync For You to Apple TV in Gus on your iPhone. Use the same iCloud and Jellyfin accounts on both devices.")
                        .font(.caption)
                }
            #else
                if session.intelligenceAccess.canOfferForYou || preferences.recommendationsEnabled || preferences.forYouSyncEnabled {
                    SyncSettingRow(
                        title: "Sync For You to Apple TV",
                        isOn: Binding(
                            get: { preferences.forYouSyncEnabled },
                            set: { enabled in
                                if enabled {
                                    showingConsent = true
                                } else {
                                    session.setForYouSyncEnabled(false)
                                }
                            }
                        ),
                        identifier: "Intelligence.forYouSync",
                        isDisabled: session.isVerifyingForYouSyncAccount || (!preferences.recommendationsEnabled && !preferences.forYouSyncEnabled)
                    ) {
                        if session.forYouSyncAccountVerificationFailed {
                            Text("Couldn’t verify your iCloud account. Try again.")
                        }
                        if preferences.recommendationsEnabled {
                            Text("Gus shares the ranked Jellyfin item IDs through your private iCloud storage. Use the same iCloud and Jellyfin accounts on both devices.")
                                .font(.caption)
                        } else {
                            Text("Turn on Show For You in Library Intelligence to share recommendations.")
                                .font(.caption)
                        }
                    }
                    .forYouSyncConsent(isPresented: $showingConsent)
                }
            #endif
        }
    }
#endif

#if !os(watchOS)
    struct SyncSettingRow<Details: View>: View {
        let title: LocalizedStringKey
        @Binding var isOn: Bool
        let identifier: String
        var isDisabled = false
        @ViewBuilder let details: Details

        var body: some View {
            #if os(tvOS)
                // A native toggle owns the entire remote-focusable form row.
                Toggle(isOn: $isOn) {
                    VStack(alignment: .leading) {
                        Text(title)
                        details.foregroundStyle(.secondary).lineLimit(nil)
                    }
                }
                .disabled(isDisabled)
                .accessibilityIdentifier(identifier)
            #else
                VStack(alignment: .leading) {
                    Toggle(title, isOn: $isOn)
                        .disabled(isDisabled)
                        .accessibilityIdentifier(identifier)
                    details.foregroundStyle(.secondary).lineLimit(nil)
                }
                .accessibilityElement(children: .contain)
            #endif
        }
    }
#endif
