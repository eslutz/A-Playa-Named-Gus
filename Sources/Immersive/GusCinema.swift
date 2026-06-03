#if os(visionOS)
    import CoreGraphics
    import RealityKit
    import SwiftUI
    import UIKit

    /// The "Gus Cinema" immersive space — a RealityKit media room.
    ///
    /// Ported from PR #2's `JellyfinCinemaImmersiveView` (same structure: an inward-facing
    /// sphere backdrop with a soft vertical gradient, plus key/fill point lights), re-themed
    /// with a Psych / radio-DJ-lounge palette. The same accent (`pineapple gold`) feeds the
    /// app's `AccentColor`, so the windowed UI and the cinema share a palette.
    struct GusCinema: View {
        static let spaceID = "gus-cinema"

        var body: some View {
            RealityView { content in
                content.add(Self.makeRoom())
            }
        }

        // MARK: - Scene

        /// Inward-facing sphere backdrop + two soft point lights (mirrors PR #2's `makeRoom`).
        private static func makeRoom() -> Entity {
            let room = Entity()

            let backdrop = ModelEntity(
                mesh: .generateSphere(radius: 12),
                materials: [backdropMaterial()]
            )
            // Invert along X so we view the sphere from the inside.
            backdrop.scale = SIMD3<Float>(-1, 1, 1)
            room.addChild(backdrop)

            room.addChild(makeLight(
                color: GusCinemaPalette.keyLightUI,
                intensity: 1200,
                position: SIMD3<Float>(0, 2.5, -5)
            ))
            room.addChild(makeLight(
                color: GusCinemaPalette.fillLightUI,
                intensity: 600,
                position: SIMD3<Float>(-3, 1, -4)
            ))

            return room
        }

        private static func makeLight(color: UIColor, intensity: Float, position: SIMD3<Float>) -> Entity {
            let entity = Entity()
            entity.components.set(PointLightComponent(color: color, intensity: intensity))
            entity.position = position
            return entity
        }

        private static func backdropMaterial() -> RealityKit.Material {
            if let texture = gradientTexture() {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                return material
            }
            return UnlitMaterial(color: GusCinemaPalette.backdropNightUI)
        }

        /// 8×512 vertical gradient (night → plum → night) used as the backdrop texture.
        private static func gradientTexture() -> TextureResource? {
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

            let colors = [
                GusCinemaPalette.backdropNightCG,
                GusCinemaPalette.backdropMidCG,
                GusCinemaPalette.backdropNightCG,
            ] as CFArray
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

    /// Gus / Psych cinema palette: warm pineapple-gold + radio-neon magenta over deep indigo.
    ///
    /// Colors are defined once in the asset catalog (the `Cinema*` colorsets) so the windowed UI
    /// and this RealityKit room share a single source of truth; the literal fallbacks keep the
    /// cinema rendering even if an asset is missing.
    enum GusCinemaPalette {
        private static func color(_ name: String, fallback: UIColor) -> UIColor {
            UIColor(named: name) ?? fallback
        }

        /// backdrop night — deep indigo-black #120E22
        static let backdropNightUI = color("CinemaBackdropNight", fallback: UIColor(red: 0.071, green: 0.055, blue: 0.133, alpha: 1))
        /// backdrop mid — plum #2A1B3D
        static let backdropMidUI = color("CinemaBackdropMid", fallback: UIColor(red: 0.165, green: 0.106, blue: 0.239, alpha: 1))
        /// key light — pineapple gold #F4B740
        static let keyLightUI = color("CinemaKeyLight", fallback: UIColor(red: 0.957, green: 0.718, blue: 0.251, alpha: 1))
        /// fill light — radio-neon magenta #E0529C
        static let fillLightUI = color("CinemaFillLight", fallback: UIColor(red: 0.878, green: 0.322, blue: 0.612, alpha: 1))

        static var backdropNightCG: CGColor {
            backdropNightUI.cgColor
        }

        static var backdropMidCG: CGColor {
            backdropMidUI.cgColor
        }
    }
#endif
