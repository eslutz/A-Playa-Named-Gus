#if os(visionOS)
    import AVFoundation
    import RealityKit
    import UIKit

    enum Stereo3DScreen {
        static let rootName = "GusStereo3DScreen"

        /// Builds the Cinema screen entity for frame-packed SBS/TAB playback.
        ///
        /// The `videoRenderer` must be supplied by a `StereoFrameRenderer`, which feeds it
        /// per-eye `CMTaggedBufferGroup` stereo sample buffers. Because the renderer carries
        /// properly tagged left/right-eye pixel buffers, `VideoMaterial.preferredViewingMode = .stereo`
        /// routes each eye's frame to the corresponding eye — giving true 3D separation on the plane.
        @MainActor
        static func entity(
            videoRenderer: AVSampleBufferVideoRenderer,
            layout: Stereo3DLayout,
            title: String
        ) -> Entity {
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
                materials: [stereoMaterial(videoRenderer: videoRenderer)]
            )
            screen.name = title
            screen.position = SIMD3<Float>(0, 1.6, -3)
            screen.components.set(stereoPlayerComponent(videoRenderer: videoRenderer))
            root.addChild(screen)

            return root
        }

        @MainActor
        private static func stereoMaterial(videoRenderer: AVSampleBufferVideoRenderer) -> RealityKit.Material {
            var material = VideoMaterial(videoRenderer: videoRenderer)
            // .stereo separates the per-eye CMTaggedBufferGroup frames supplied by StereoFrameRenderer.
            material.controller.preferredViewingMode = .stereo
            material.faceCulling = .none
            return material
        }

        @MainActor
        private static func stereoPlayerComponent(videoRenderer: AVSampleBufferVideoRenderer) -> VideoPlayerComponent {
            var component = VideoPlayerComponent(videoRenderer: videoRenderer)
            component.desiredViewingMode = .stereo
            component.desiredImmersiveViewingMode = .portal
            return component
        }
    }
#endif
