import SwiftUI

struct IntelligenceSettingsSection: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        #if os(tvOS)
            Section {
                Toggle("Show Synced For You", isOn: forYouSyncChoice)
                    .accessibilityIdentifier("Intelligence.forYouSync")
            } header: {
                Text("Library Intelligence")
            } footer: {
                Text("Enable Sync For You to Apple TV in Gus on your iPhone. Use the same iCloud and Jellyfin accounts on both devices.")
            }
        #else
            localIntelligenceSettings
        #endif
    }

    @ViewBuilder
    private var localIntelligenceSettings: some View {
        let access = session.intelligenceAccess
        let preferences = session.intelligencePreferences
        let needsCloudConsent = access.requiresCloud && preferences.cloudDecision == false
        #if os(iOS)
            let showsForYouSync = access.canOfferForYou || preferences.recommendationsEnabled || preferences.forYouSyncEnabled
        #else
            let showsForYouSync = false
        #endif
        if access.supportsSearch || access.supportsCloud || preferences.recommendationsEnabled || showsForYouSync {
            Section {
                if access.supportsSearch {
                    Toggle("Natural Language Search", isOn: Binding(
                        get: { preferences.naturalSearchEnabled },
                        set: { access.setNaturalSearchEnabled($0) }
                    ))
                    .accessibilityIdentifier("Intelligence.naturalSearch")
                }
                if access.supportsCloud {
                    Toggle("Allow Private Cloud Compute", isOn: Binding(
                        get: { preferences.cloudEnabled },
                        set: { access.setCloudEnabled($0) }
                    ))
                    .accessibilityIdentifier("Intelligence.privateCloud")
                }
                if access.supportsSearch || preferences.recommendationsEnabled {
                    Toggle("Show For You", isOn: Binding(
                        get: { preferences.recommendationsEnabled },
                        set: { access.setForYouEnabled($0) }
                    ))
                    .disabled((!access.canOfferForYou || needsCloudConsent) && !preferences.recommendationsEnabled)
                    .accessibilityIdentifier("Intelligence.forYou")
                }
                #if os(iOS)
                    if showsForYouSync {
                        Toggle("Sync For You to Apple TV", isOn: forYouSyncChoice)
                            .disabled(session.isVerifyingForYouSyncAccount || (!preferences.recommendationsEnabled && !preferences.forYouSyncEnabled))
                            .accessibilityIdentifier("Intelligence.forYouSync")
                    }
                #endif
            } header: {
                Text("Library Intelligence")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("For You uses this account’s favorites and activity to suggest media.")
                    #if os(iOS)
                        if showsForYouSync {
                            Text("Gus shares the ranked Jellyfin item IDs through your private iCloud storage. Use the same iCloud and Jellyfin accounts on both devices.")
                            if session.forYouSyncAccountVerificationFailed {
                                Text("Couldn’t verify your iCloud account. Try again.")
                            }
                        }
                    #endif
                    if needsCloudConsent {
                        Text("Turn on Allow Private Cloud Compute to use natural-language search and For You on this device.")
                    } else if access.supportsCloud {
                        Text("When enabled, Gus can send search text, selected catalog details, and taste signals to Apple’s Private Cloud Compute using your daily quota.")
                    }
                }
            }
        }
    }

    #if os(iOS) || os(tvOS)
        private var forYouSyncChoice: Binding<Bool> {
            Binding(
                get: { session.intelligencePreferences.forYouSyncEnabled },
                set: { session.setForYouSyncEnabled($0) }
            )
        }
    #endif
}
