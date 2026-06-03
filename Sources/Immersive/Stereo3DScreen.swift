#if os(visionOS)
    import AVFoundation
    import RealityKit
    import UIKit

    enum Stereo3DScreen {
        static let rootName = "GusStereo3DScreen"

        @MainActor
        static func entity(player: AVPlayer, layout: Stereo3DLayout, title: String) -> Entity {
            let root = Entity()
            root.name = rootName

            guard let size = Stereo3DScreenMetrics.screenSize(for: layout) else { return root }

            let backing = ModelEntity(
                mesh: .generatePlane(width: size.x + 0.12, height: size.y + 0.12, cornerRadius: 0.08),
                materials: [UnlitMaterial(color: .black)]
            )
            backing.name = "GusStereo3DBacking"
            backing.position = SIMD3<Float>(0, 1.6, -3.01)
            root.addChild(backing)

            let screen = ModelEntity(
                mesh: .generatePlane(width: size.x, height: size.y, cornerRadius: 0.06),
                materials: [videoMaterial(player: player)]
            )
            screen.name = title
            screen.position = SIMD3<Float>(0, 1.6, -3)
            screen.components.set(videoPlayerComponent(player: player))
            root.addChild(screen)

            return root
        }

        @MainActor
        private static func videoMaterial(player: AVPlayer) -> RealityKit.Material {
            var material = VideoMaterial(avPlayer: player)
            material.controller.preferredViewingMode = .stereo
            material.faceCulling = .none
            return material
        }

        @MainActor
        private static func videoPlayerComponent(player: AVPlayer) -> VideoPlayerComponent {
            var component = VideoPlayerComponent(avPlayer: player)
            component.desiredViewingMode = .stereo
            component.desiredImmersiveViewingMode = .portal
            if #available(visionOS 26.0, *) {
                component.desiredSpatialVideoMode = .screen
            }
            return component
        }
    }
#endif
