import JellyfinAPI

/// Container repairs shared by streaming negotiation and offline downloads.
/// HEVC decoding support alone does not make an `hev1` MP4 native-player compatible.
enum AVPlayerContainerCompatibility {
    static let nativeHEVCTag = "hvc1"
    private static let hevcTagRequiringRemux = "hev1"

    static func requiresHEVCRemux(codecTag: String?) -> Bool {
        codecTag?.lowercased() == hevcTagRequiringRemux
    }

    /// Keep this restriction on the container, so Jellyfin can copy HEVC video
    /// into HLS/fMP4 with an hvc1 sample entry instead of encoding it again.
    static var mp4Profile: ContainerProfile {
        ContainerProfile(
            conditions: [
                ProfileCondition(condition: .notEquals, isRequired: false, property: .videoCodecTag, value: hevcTagRequiringRemux),
            ],
            container: "mp4,m4v,mov",
            type: .video
        )
    }
}
