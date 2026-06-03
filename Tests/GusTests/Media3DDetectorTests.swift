@testable import Gus
import JellyfinAPI
import Testing

@Suite("Media 3D detector")
struct Media3DDetectorTests {
    @Test("maps Jellyfin Video3DFormat cases to stereo layouts", arguments: [
        (Video3DFormat.halfSideBySide, Stereo3DLayout.sideBySide(half: true)),
        (.fullSideBySide, .sideBySide(half: false)),
        (.halfTopAndBottom, .topAndBottom(half: true)),
        (.fullTopAndBottom, .topAndBottom(half: false)),
        (.mvc, .multiviewCoding),
    ])
    func mapsVideo3DFormat(format: Video3DFormat, expectedLayout: Stereo3DLayout) {
        let item = BaseItemDto(video3DFormat: format)

        #expect(Media3DDetector.layout(for: item) == expectedLayout)
    }

    @Test("detects MV-HEVC only when HEVC streams expose a multiview hint")
    func detectsMVHEVCFromHevcMultiviewHints() {
        let spatialItem = BaseItemDto(mediaStreams: [
            MediaStream(codec: "hevc", codecTag: "hvc1", profile: "Main 10 multiview", type: .video),
        ])
        let ordinaryHEVC = BaseItemDto(mediaStreams: [
            MediaStream(codec: "hevc", codecTag: "hvc1", profile: "Main 10", type: .video),
        ])

        #expect(Media3DDetector.layout(for: spatialItem) == .mvHEVC)
        #expect(Media3DDetector.layout(for: ordinaryHEVC) == .none)
    }

    @Test("chooses the visionOS presentation for each stereo layout", arguments: [
        (Video3DFormat.halfSideBySide, Stereo3DPresentation.immersiveFramePacked(.sideBySide(half: true))),
        (.fullTopAndBottom, .immersiveFramePacked(.topAndBottom(half: false))),
        (.mvc, .unsupported3D(.multiviewCoding)),
    ])
    func choosesVisionOSPresentation(format: Video3DFormat, expectedPresentation: Stereo3DPresentation) {
        let item = BaseItemDto(video3DFormat: format)

        #expect(Media3DDetector.presentation(for: item, on: .visionOS) == expectedPresentation)
    }

    @Test("uses native spatial presentation for MV-HEVC on visionOS")
    func usesNativeSpatialPresentationForMVHEVC() {
        let item = BaseItemDto(mediaStreams: [
            MediaStream(codec: "hevc", title: "Apple Spatial Video", type: .video),
        ])

        #expect(Media3DDetector.presentation(for: item, on: .visionOS) == .nativeSpatial)
    }

    @Test("forces native 2D on non-visionOS platforms")
    func nonVisionOSAlwaysFallsBackTo2D() {
        let item = BaseItemDto(video3DFormat: .halfSideBySide)

        #expect(Media3DDetector.presentation(for: item, on: .other) == .native2D)
    }

    @Test("shows the Spatial badge only for native MV-HEVC playback")
    func spatialBadgeVisibilityFollowsNativeSpatialPresentation() {
        #expect(Stereo3DPresentation.nativeSpatial.showsSpatialBadge)
        #expect(!Stereo3DPresentation.native2D.showsSpatialBadge)
        #expect(!Stereo3DPresentation.immersiveFramePacked(.sideBySide(half: true)).showsSpatialBadge)
        #expect(!Stereo3DPresentation.unsupported3D(.multiviewCoding).showsSpatialBadge)
    }

    @Test("exposes immersive renderer metadata for frame-packed layouts")
    func framePackedPresentationExposesImmersiveRendererMetadata() {
        let layout = Stereo3DLayout.sideBySide(half: true)
        let presentation = Stereo3DPresentation.immersiveFramePacked(layout)

        #expect(presentation.usesImmersiveFramePackedRenderer)
        #expect(presentation.framePackedLayout == layout)
        #expect(!Stereo3DPresentation.nativeSpatial.usesImmersiveFramePackedRenderer)
        #expect(Stereo3DPresentation.nativeSpatial.framePackedLayout == nil)
    }

    @Test("builds per-eye sampling regions for side-by-side and top-and-bottom layouts")
    func buildsFramePackedSamplingRegions() {
        let sideBySide = Stereo3DScreenMetrics.samplingPlan(for: .sideBySide(half: true))
        let topAndBottom = Stereo3DScreenMetrics.samplingPlan(for: .topAndBottom(half: true))

        #expect(sideBySide?.leftEye == Stereo3DEyeRegion(uMin: 0, uMax: 0.5, vMin: 0, vMax: 1))
        #expect(sideBySide?.rightEye == Stereo3DEyeRegion(uMin: 0.5, uMax: 1, vMin: 0, vMax: 1))
        #expect(sideBySide?.aspectCorrection == .init(x: 2, y: 1))

        #expect(topAndBottom?.leftEye == Stereo3DEyeRegion(uMin: 0, uMax: 1, vMin: 0, vMax: 0.5))
        #expect(topAndBottom?.rightEye == Stereo3DEyeRegion(uMin: 0, uMax: 1, vMin: 0.5, vMax: 1))
        #expect(topAndBottom?.aspectCorrection == .init(x: 1, y: 2))

        #expect(Stereo3DScreenMetrics.samplingPlan(for: .mvHEVC) == nil)
    }
}
