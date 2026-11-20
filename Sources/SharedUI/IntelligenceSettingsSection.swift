import SwiftUI

struct IntelligenceSettingsSection: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        let model = GusIntelligenceModel(session: session)
        @Bindable var preferences = session.intelligencePreferences
        if model.isAvailable || model.cloudSupported || preferences.cloudEnabled || preferences.recommendationsEnabled {
            Section {
                Toggle("Show For You", isOn: $preferences.recommendationsEnabled)
                    .onChange(of: preferences.recommendationsEnabled) { _, enabled in
                        if !enabled {
                            session.libraryIntelligence.clearRecommendations()
                        }
                    }
                if model.cloudSupported || preferences.cloudEnabled {
                    Toggle("Allow Private Cloud Compute", isOn: $preferences.cloudEnabled)
                }
            } header: {
                Text("Library Intelligence")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("For You uses this account’s favorites and activity to suggest media.")
                    if model.cloudSupported || preferences.cloudEnabled {
                        Text("When enabled, Gus can send search text, selected catalog details, and taste signals to Apple’s Private Cloud Compute using your daily quota.")
                    }
                }
            }
        }
    }
}
