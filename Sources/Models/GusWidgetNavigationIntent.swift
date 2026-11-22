#if os(iOS) || os(macOS) || os(watchOS)
    import AppIntents
    import Foundation

    enum GusWidgetDestination: String, AppEnum {
        case search, downloaded

        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Gus Destination")
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .search: "Search Library",
            .downloaded: "Downloads",
        ]
    }

    /// WidgetKit requires the same OpenIntent in the host and the extension.
    struct GusWidgetNavigationIntent: OpenIntent {
        static let title: LocalizedStringResource = "Open Gus Destination"
        static let supportedModes: IntentModes = .foreground(.immediate)
        static let isDiscoverable = false
        @available(iOS 27, macOS 27, watchOS 27, *)
        static var allowedExecutionTargets: IntentExecutionTargets {
            .main
        }

        @Parameter(title: "Destination")
        var target: GusWidgetDestination

        init() {}
        init(target: GusWidgetDestination) {
            self.target = target
        }

        @MainActor
        func perform() async throws -> some IntentResult {
            #if !GUS_WIDGET_EXTENSION
                #if os(watchOS)
                    WatchShortcutNavigation.shared.open(url: URL(string: "gus://" + target.rawValue)!)
                #else
                    AppNavigationModel.shared.open(target == .downloaded ? .downloaded : .search)
                #endif
            #endif
            return .result()
        }
    }
#endif
