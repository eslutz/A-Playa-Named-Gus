#if os(visionOS)
    import CoreGraphics
    import RealityKit
    import SwiftUI
    import UIKit

    /// The "Gus Cinema" immersive space — a RealityKit media room.
    ///
    /// Ported from PR #2's `JellyfinCinemaImmersiveView` (same structure: an inward-facing
    /// sphere backdrop with a soft vertical gradient, plus key/fill point lights), re-themed
    /// with the Jellyfin navy, purple, and blue palette used by the windowed UI.
    struct GusCinema: View {
        static let spaceID = "gus-cinema"

        @Environment(CinemaModel.self) private var cinema

        var body: some View {
            RealityView { content in
                Self.updateRoom(in: &content, environment: cinema.selectedEnvironment)
                Self.updateStereoScreen(in: &content, playback: cinema.playbackPresentation)
            } update: { content in
                Self.updateRoom(in: &content, environment: cinema.selectedEnvironment)
                Self.updateStereoScreen(in: &content, playback: cinema.playbackPresentation)
            }
        }

        // MARK: - Scene

        private static let roomNamePrefix = "GusCinemaRoom"

        private static func updateRoom(in content: inout RealityViewContent, environment: CinemaEnvironment) {
            let roomName = "\(roomNamePrefix)-\(environment.rawValue)"
            guard content.entities.first(where: { $0.name == roomName }) == nil else {
                return
            }

            content.entities
                .filter { $0.name.hasPrefix(roomNamePrefix) }
                .forEach { content.remove($0) }
            content.add(makeRoom(environment: environment))
        }

        /// Inward-facing sphere backdrop + two soft point lights (mirrors PR #2's `makeRoom`).
        private static func makeRoom(environment: CinemaEnvironment) -> Entity {
            let room = Entity()
            room.name = "\(roomNamePrefix)-\(environment.rawValue)"

            let backdrop = ModelEntity(
                mesh: .generateSphere(radius: 12),
                materials: [backdropMaterial(environment: environment)]
            )
            // Invert along X so we view the sphere from the inside.
            backdrop.scale = SIMD3<Float>(-1, 1, 1)
            room.addChild(backdrop)

            room.addChild(makeLight(
                color: GusCinemaPalette.keyLightUI(for: environment),
                intensity: 1200,
                position: SIMD3<Float>(0, 2.5, -5)
            ))
            room.addChild(makeLight(
                color: GusCinemaPalette.fillLightUI(for: environment),
                intensity: 600,
                position: SIMD3<Float>(-3, 1, -4)
            ))

            return room
        }

        private static func updateStereoScreen(in content: inout RealityViewContent, playback: CinemaPlaybackPresentation?) {
            guard
                let playback,
                playback.isFramePackedStereo,
                let layout = playback.stereoLayout,
                let renderer = playback.stereoRenderer
            else {
                content.entities
                    .filter { $0.name == Stereo3DScreen.rootName }
                    .forEach { content.remove($0) }
                return
            }

            guard content.entities.first(where: { $0.name == Stereo3DScreen.rootName }) == nil else {
                return
            }

            content.add(Stereo3DScreen.entity(
                videoRenderer: renderer.videoRenderer,
                layout: layout,
                title: playback.title
            ))
        }

        private static func makeLight(color: UIColor, intensity: Float, position: SIMD3<Float>) -> Entity {
            let entity = Entity()
            entity.components.set(PointLightComponent(color: color, intensity: intensity))
            entity.position = position
            return entity
        }

        private static func backdropMaterial(environment: CinemaEnvironment) -> RealityKit.Material {
            if let texture = gradientTexture(environment: environment) {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                return material
            }
            return UnlitMaterial(color: GusCinemaPalette.backdropNightUI(for: environment))
        }

        /// 8×512 vertical gradient (navy → black → navy) used as the backdrop texture.
        private static func gradientTexture(environment: CinemaEnvironment) -> TextureResource? {
            let width = 8
            let height = 512
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            let colors = GusCinemaPalette.backdropCGColors(for: environment) as CFArray
            let locations: [CGFloat] = [0.0, 0.5, 1.0]

            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
                return nil
            }

            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: height),
                options: []
            )

            guard let cgImage = context.makeImage() else { return nil }
            return try? TextureResource(image: cgImage, options: .init(semantic: .color))
        }
    }

    /// Gus cinema palette: Jellyfin purple and blue over deep navy.
    ///
    /// Colors are defined once in the asset catalog (the `Cinema*` colorsets) so the windowed UI
    /// and this RealityKit room share a single source of truth; the literal fallbacks keep the
    /// cinema rendering even if an asset is missing.
    enum GusCinemaPalette {
        private static func color(_ name: String, fallback: UIColor) -> UIColor {
            UIColor(named: name) ?? fallback
        }

        static func backdropNightUI(for environment: CinemaEnvironment) -> UIColor {
            switch environment {
            case .gusCinema:
                return color("CinemaBackdropNight", fallback: UIColor(red: 0.0, green: 0.043, blue: 0.145, alpha: 1))
            case .midnight:
                return UIColor(red: 0.01, green: 0.012, blue: 0.025, alpha: 1)
            case .ocean:
                return UIColor(red: 0.0, green: 0.08, blue: 0.12, alpha: 1)
            case .pineapple:
                return UIColor(red: 0.08, green: 0.045, blue: 0.0, alpha: 1)
            }
        }

        static func backdropCGColors(for environment: CinemaEnvironment) -> [CGColor] {
            switch environment {
            case .gusCinema:
                return [
                    backdropNightUI(for: environment).cgColor,
                    color("CinemaBackdropMid", fallback: UIColor(red: 0.063, green: 0.063, blue: 0.063, alpha: 1)).cgColor,
                    backdropNightUI(for: environment).cgColor,
                ]
            case .midnight:
                return [
                    UIColor(red: 0.01, green: 0.012, blue: 0.025, alpha: 1).cgColor,
                    UIColor(red: 0.025, green: 0.035, blue: 0.08, alpha: 1).cgColor,
                    UIColor.black.cgColor,
                ]
            case .ocean:
                return [
                    UIColor(red: 0.0, green: 0.08, blue: 0.12, alpha: 1).cgColor,
                    UIColor(red: 0.0, green: 0.22, blue: 0.28, alpha: 1).cgColor,
                    UIColor(red: 0.0, green: 0.04, blue: 0.08, alpha: 1).cgColor,
                ]
            case .pineapple:
                return [
                    UIColor(red: 0.08, green: 0.045, blue: 0.0, alpha: 1).cgColor,
                    UIColor(red: 0.34, green: 0.17, blue: 0.04, alpha: 1).cgColor,
                    UIColor(red: 0.04, green: 0.02, blue: 0.0, alpha: 1).cgColor,
                ]
            }
        }

        static func keyLightUI(for environment: CinemaEnvironment) -> UIColor {
            switch environment {
            case .gusCinema:
                return color("CinemaKeyLight", fallback: UIColor(red: 0.675, green: 0.361, blue: 0.765, alpha: 1))
            case .midnight:
                return UIColor(red: 0.58, green: 0.68, blue: 1.0, alpha: 1)
            case .ocean:
                return UIColor(red: 0.0, green: 0.76, blue: 0.84, alpha: 1)
            case .pineapple:
                return UIColor(red: 1.0, green: 0.62, blue: 0.14, alpha: 1)
            }
        }

        static func fillLightUI(for environment: CinemaEnvironment) -> UIColor {
            switch environment {
            case .gusCinema:
                return color("CinemaFillLight", fallback: UIColor(red: 0.0, green: 0.643, blue: 0.863, alpha: 1))
            case .midnight:
                return UIColor(red: 0.36, green: 0.28, blue: 0.76, alpha: 1)
            case .ocean:
                return UIColor(red: 0.16, green: 0.9, blue: 0.58, alpha: 1)
            case .pineapple:
                return UIColor(red: 0.68, green: 0.36, blue: 0.76, alpha: 1)
            }
        }
    }
#endif
