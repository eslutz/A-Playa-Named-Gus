import JellyfinAPI

/// Stereoscopic layout as reported by Jellyfin or inferred from stream metadata.
enum Stereo3DLayout: Equatable {
    case sideBySide(half: Bool)
    case topAndBottom(half: Bool)
    case mvHEVC
    case multiviewCoding
    case none

    var requiresDirectPlay: Bool {
        switch self {
        case .sideBySide, .topAndBottom, .mvHEVC:
            return true
        case .multiviewCoding, .none:
            return false
        }
    }
}

enum Stereo3DPresentation: Equatable {
    case native2D
    case nativeSpatial
    case immersiveFramePacked(Stereo3DLayout)
    case unsupported3D(Stereo3DLayout)

    var resolutionStereoLayout: Stereo3DLayout {
        switch self {
        case .nativeSpatial:
            .mvHEVC
        case let .immersiveFramePacked(layout):
            layout
        case .native2D, .unsupported3D:
            .none
        }
    }

    var showsSpatialBadge: Bool {
        self == .nativeSpatial
    }

    var framePackedLayout: Stereo3DLayout? {
        switch self {
        case let .immersiveFramePacked(layout):
            layout
        case .native2D, .nativeSpatial, .unsupported3D:
            nil
        }
    }

    var usesImmersiveFramePackedRenderer: Bool {
        framePackedLayout != nil
    }
}

enum Stereo3DViewingMode: Equatable, CaseIterable {
    case automatic
    case twoD
    case spatial
}

enum Media3DDetector {
    enum PlaybackPlatform: Equatable {
        case visionOS
        case other
    }

    static var currentPlatform: PlaybackPlatform {
        #if os(visionOS)
            .visionOS
        #else
            .other
        #endif
    }

    static func layout(for item: BaseItemDto) -> Stereo3DLayout {
        if let format = item.video3DFormat {
            return layout(for: format)
        }

        if let format = item.mediaSources?.compactMap(\.video3DFormat).first {
            return layout(for: format)
        }

        return looksLikeMVHEVC(item) ? .mvHEVC : .none
    }

    static func presentation(
        for item: BaseItemDto,
        on platform: PlaybackPlatform = currentPlatform,
        viewingMode: Stereo3DViewingMode = .automatic
    ) -> Stereo3DPresentation {
        guard platform == .visionOS else { return .native2D }

        let layout = layout(for: item)
        switch viewingMode {
        case .automatic:
            break
        case .twoD:
            return .native2D
        case .spatial:
            return layout == .multiviewCoding ? .unsupported3D(layout) : .nativeSpatial
        }

        switch layout {
        case .mvHEVC:
            return .nativeSpatial
        case .sideBySide, .topAndBottom:
            return .immersiveFramePacked(layout)
        case .multiviewCoding:
            return .unsupported3D(layout)
        case .none:
            return .native2D
        }
    }

    private static func layout(for format: Video3DFormat) -> Stereo3DLayout {
        switch format {
        case .halfSideBySide:
            .sideBySide(half: true)
        case .fullSideBySide:
            .sideBySide(half: false)
        case .halfTopAndBottom:
            .topAndBottom(half: true)
        case .fullTopAndBottom:
            .topAndBottom(half: false)
        case .mvc:
            .multiviewCoding
        }
    }

    /// Jellyfin does not currently flag Apple spatial video. This is intentionally
    /// conservative: require HEVC plus an explicit multiview/spatial hint surfaced by
    /// server metadata, otherwise leave Feature 5's manual Spatial override to the user.
    private static func looksLikeMVHEVC(_ item: BaseItemDto) -> Bool {
        mediaStreams(for: item).contains { stream in
            guard stream.type == .video, isHEVC(stream.codec) else { return false }
            return stream.hintFields.contains { field in
                let normalized = field.lowercased()
                return normalized.contains("mv-hevc")
                    || normalized.contains("mvhevc")
                    || normalized.contains("multiview")
                    || normalized.contains("spatial video")
            }
        }
    }

    private static func mediaStreams(for item: BaseItemDto) -> [MediaStream] {
        var streams = item.mediaStreams ?? []
        for source in item.mediaSources ?? [] {
            streams.append(contentsOf: source.mediaStreams ?? [])
        }
        return streams
    }

    private static func isHEVC(_ codec: String?) -> Bool {
        guard let codec else { return false }
        let normalized = codec.lowercased()
        return normalized == "hevc" || normalized == "h265" || normalized == "h.265"
    }
}

private extension MediaStream {
    var hintFields: [String] {
        [
            codecTag,
            profile,
            title,
            displayTitle,
            comment,
            videoDoViTitle,
        ].compactMap { $0 }
    }
}
