import SwiftUI

struct IntelligenceSettingsSection: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        #if !os(tvOS)
            let access = session.intelligenceAccess
            let preferences = session.intelligencePreferences
            if access.supportsSearch || access.supportsCloud || preferences.recommendationsEnabled {
                Section {
                    NavigationLink {
                        Form { intelligenceControls }
                            .navigationTitle("Library Intelligence")
                    } label: {
                        Text("Library Intelligence")
                    }
                    .accessibilityIdentifier("Settings.libraryIntelligence")
                }
            }
        #endif
    }

    private var intelligenceControls: some View {
        let access = session.intelligenceAccess
        let preferences = session.intelligencePreferences
        let needsCloudConsent = access.requiresCloud && preferences.cloudDecision == false
        return Group {
            if access.supportsSearch {
                Section {
                    Toggle("Natural Language Search", isOn: Binding(
                        get: { preferences.naturalSearchEnabled },
                        set: { access.setNaturalSearchEnabled($0) }
                    ))
                    .accessibilityIdentifier("Intelligence.naturalSearch")
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
    }
}

#if os(iOS) || os(tvOS)
    struct ForYouSyncSetting: View {
        @Environment(SessionStore.self) private var session
        #if os(iOS)
            @State private var showingConsent = false
        #endif

        var body: some View {
            let preferences = session.intelligencePreferences
            #if os(tvOS)
                Toggle("Show Synced For You", isOn: Binding(
                    get: { preferences.forYouSyncEnabled },
                    set: { session.setForYouSyncEnabled($0) }
                ))
                .accessibilityIdentifier("Intelligence.forYouSync")
                Text("Enable Sync For You to Apple TV in Gus on your iPhone. Use the same iCloud and Jellyfin accounts on both devices.")
                    .font(.caption).foregroundStyle(.secondary)
            #else
                if session.intelligenceAccess.canOfferForYou || preferences.recommendationsEnabled || preferences.forYouSyncEnabled {
                    Toggle("Sync For You to Apple TV", isOn: Binding(
                        get: { preferences.forYouSyncEnabled },
                        set: { enabled in
                            if enabled {
                                showingConsent = true
                            } else {
                                session.setForYouSyncEnabled(false)
                            }
                        }
                    ))
                    .disabled(session.isVerifyingForYouSyncAccount || (!preferences.recommendationsEnabled && !preferences.forYouSyncEnabled))
                    .accessibilityIdentifier("Intelligence.forYouSync")
                    .forYouSyncConsent(isPresented: $showingConsent)
                    if session.forYouSyncAccountVerificationFailed {
                        Text("Couldn’t verify your iCloud account. Try again.")
                            .foregroundStyle(.secondary)
                    }
                    if preferences.recommendationsEnabled {
                        Text("Gus shares the ranked Jellyfin item IDs through your private iCloud storage. Use the same iCloud and Jellyfin accounts on both devices.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Turn on Show For You in Library Intelligence to share recommendations.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            #endif
        }
    }
#endif
