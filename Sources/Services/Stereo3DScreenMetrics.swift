/// Normalized texture region for one eye in a frame-packed stereo source.
struct Stereo3DEyeRegion: Equatable {
    let uMin: Double
    let uMax: Double
    let vMin: Double
    let vMax: Double
}

/// Sampling and squeeze-correction metadata for frame-packed SBS/TAB playback.
struct Stereo3DSamplingPlan: Equatable {
    let leftEye: Stereo3DEyeRegion
    let rightEye: Stereo3DEyeRegion
    let aspectCorrection: SIMD2<Double>
}

enum Stereo3DScreenMetrics {
    static let defaultAspectRatio = 16.0 / 9.0

    static func samplingPlan(for layout: Stereo3DLayout) -> Stereo3DSamplingPlan? {
        switch layout {
        case let .sideBySide(half):
            Stereo3DSamplingPlan(
                leftEye: Stereo3DEyeRegion(uMin: 0, uMax: 0.5, vMin: 0, vMax: 1),
                rightEye: Stereo3DEyeRegion(uMin: 0.5, uMax: 1, vMin: 0, vMax: 1),
                aspectCorrection: half ? SIMD2<Double>(x: 2, y: 1) : SIMD2<Double>(x: 1, y: 1)
            )
        case let .topAndBottom(half):
            Stereo3DSamplingPlan(
                leftEye: Stereo3DEyeRegion(uMin: 0, uMax: 1, vMin: 0, vMax: 0.5),
                rightEye: Stereo3DEyeRegion(uMin: 0, uMax: 1, vMin: 0.5, vMax: 1),
                aspectCorrection: half ? SIMD2<Double>(x: 1, y: 2) : SIMD2<Double>(x: 1, y: 1)
            )
        case .mvHEVC, .multiviewCoding, .none:
            nil
        }
    }

    static func screenSize(for layout: Stereo3DLayout, width: Float = 4.0) -> SIMD2<Float>? {
        guard samplingPlan(for: layout) != nil else { return nil }
        return SIMD2<Float>(x: width, y: width / Float(defaultAspectRatio))
    }
}
