import SwiftUI

struct IntelligenceSettingsSection: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        let access = session.intelligenceAccess
        let preferences = session.intelligencePreferences
        let needsCloudConsent = access.requiresCloud && preferences.cloudDecision == false
        if access.supportsSearch || access.supportsCloud || preferences.recommendationsEnabled {
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
            } header: {
                Text("Library Intelligence")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("For You uses this account’s favorites and activity to suggest media.")
                    if needsCloudConsent {
                        Text("Turn on Allow Private Cloud Compute to use natural-language search and For You on this device.")
                    } else if access.supportsCloud {
                        Text("When enabled, Gus can send search text, selected catalog details, and taste signals to Apple’s Private Cloud Compute using your daily quota.")
                    }
                }
            }
        }
    }
}
