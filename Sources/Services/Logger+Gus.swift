import OSLog

extension Logger {
    /// The single subsystem identifier for all A Playa Named Gus logging.
    static let subsystem = "dev.ericslutz.gus"

    /// Logging categories, defined in one place so Console/`log` filtering is consistent.
    enum Category: String {
        case appModel = "AppModel"
        case discovery = "Discovery"
        case session = "Session"
        case home = "Home"
        case library = "Library"
        case search = "Search"
        case item = "Item"
        case playback = "Playback"
        case downloads = "Downloads"
        case quickConnect = "QuickConnect"
        case stream = "Stream"
        case keychain = "Keychain"
        case serverStore = "ServerStore"
        case diagnostics = "Diagnostics"
    }

    /// Builds a `Logger` on the A Playa Named Gus subsystem for the given category.
    init(category: Category) {
        self.init(subsystem: Logger.subsystem, category: category.rawValue)
    }
}
