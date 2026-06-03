import OSLog

extension Logger {
    /// The single subsystem identifier for all Gus logging.
    static let subsystem = "dev.ericslutz.gus"

    /// Logging categories, defined in one place so Console/`log` filtering is consistent.
    enum Category: String {
        case appModel = "AppModel"
        case session = "Session"
        case home = "Home"
        case library = "Library"
        case playback = "Playback"
        case stream = "Stream"
        case keychain = "Keychain"
        case serverStore = "ServerStore"
    }

    /// Builds a `Logger` on the Gus subsystem for the given category.
    init(category: Category) {
        self.init(subsystem: Logger.subsystem, category: category.rawValue)
    }
}
