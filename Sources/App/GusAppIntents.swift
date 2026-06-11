import AppIntents
import Foundation

/// Siri / Shortcuts: "Play <something>" against the active Jellyfin session.
///
/// The intent resolves the spoken/typed title through the provider's search, then
/// drives the foregrounded app through the shared `ContentLink` deep-link path — the
/// same routing used by URLs, Handoff, Spotlight, and the Top Shelf, so playback lands
/// in the right surface per media type (video player, audio player, book reader).
struct PlayMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Media"
    static let description = IntentDescription(
        "Searches your Jellyfin library and starts playback.",
        categoryName: "Playback"
    )
    /// Playback happens in the app's player surfaces, so the app must come forward.
    static let openAppWhenRun = true

    @Parameter(title: "Title", description: "The movie, show, song, or audiobook to play")
    var title: String

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$title)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let session = AppModel.shared.currentSession else {
            return .result(dialog: IntentDialog(stringLiteral: String(
                localized: "Sign in to a Jellyfin server in A Playa Named Gus first.",
                comment: "Siri/Shortcuts response when no session exists"
            )))
        }

        let page = try await session.mediaProvider.items(query: MediaItemQuery(
            searchTerm: title,
            startIndex: 0,
            limit: 10,
            isRecursive: true
        ))
        let candidates = ContentRatingGate.filter(page.items)

        // Prefer something directly playable; fall back to opening a container's detail.
        let playable = candidates.first { item in
            switch item.type {
            case .movie, .episode, .video, .trailer, .audio, .audioBook, .book, .recording:
                return true
            default:
                return false
            }
        }

        if let playable, let id = playable.id {
            AppNavigationModel.shared.open(.play(id: id))
            return .result(dialog: IntentDialog(stringLiteral: String(
                localized: "Playing \(playable.displayTitle).",
                comment: "Siri/Shortcuts response when playback starts"
            )))
        }

        if let container = candidates.first, let id = container.id {
            AppNavigationModel.shared.open(.item(id: id))
            return .result(dialog: IntentDialog(stringLiteral: String(
                localized: "Opening \(container.displayTitle).",
                comment: "Siri/Shortcuts response when a container opens instead of playing"
            )))
        }

        return .result(dialog: IntentDialog(stringLiteral: String(
            localized: "I couldn't find \"\(title)\" in your library.",
            comment: "Siri/Shortcuts response when search finds nothing"
        )))
    }
}

/// Exposes the intent to Siri/Shortcuts with an invocation phrase. The phrase has no
/// title slot (string parameters can't appear in phrases), so Siri prompts for it.
struct GusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMediaIntent(),
            phrases: ["Play something in \(.applicationName)"],
            shortTitle: "Play Media",
            systemImageName: "play.fill"
        )
    }
}
