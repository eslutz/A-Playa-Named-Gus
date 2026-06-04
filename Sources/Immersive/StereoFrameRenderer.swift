#if os(visionOS)
    import AVFoundation
    import CoreMedia
    import CoreVideo
    import RealityKit

    /// Weak proxy to break the CADisplayLink → StereoFrameRenderer retain cycle.
    private final class DisplayLinkProxy: NSObject {
        weak var owner: StereoFrameRenderer?

        @objc func step(_ link: CADisplayLink) {
            guard let owner else { return }
            MainActor.assumeIsolated { owner.processFrame(link) }
        }
    }

    /// Captures frames from an AVPlayer, splits the packed frame per the stereo layout, and feeds
    /// per-eye `CMTaggedBufferGroup` stereo sample buffers to an `AVSampleBufferVideoRenderer`.
    ///
    /// **Usage:** pass `renderer.videoRenderer` to `VideoMaterial(videoRenderer:)` with
    /// `controller.preferredViewingMode = .stereo` on a RealityKit screen entity. Because the
    /// renderer supplies properly tagged left/right-eye pixel buffers, the `.stereo` viewing mode
    /// produces true per-eye separation — unlike a plain `AVPlayer`-backed `VideoMaterial` where
    /// the packed frame is shown identically to both eyes.
    ///
    /// The original `AVPlayer` drives audio, transport controls, and Now Playing unchanged; this
    /// class only taps the video output.
    @MainActor
    final class StereoFrameRenderer {
        let videoRenderer = AVSampleBufferVideoRenderer()

        private let player: AVPlayer
        private let layout: Stereo3DLayout
        private var playerItemOutput: AVPlayerItemVideoOutput?
        private var displayLink: CADisplayLink?
        private var seekObserver: NSObjectProtocol?
        /// Cached format description reused across frames to avoid per-frame allocation.
        private var cachedFormatDescription: CMFormatDescription?

        init(player: AVPlayer, layout: Stereo3DLayout) {
            self.player = player
            self.layout = layout
            setupOutput()
            startDisplayLink()
            observeSeek()
        }

        /// Stop the display link, remove the video output, and release all resources.
        /// Call this when the Cinema ImmersiveSpace closes or playback ends.
        func invalidate() {
            displayLink?.invalidate()
            displayLink = nil
            if let output = playerItemOutput {
                player.currentItem?.remove(output)
            }
            playerItemOutput = nil
            if let observer = seekObserver {
                NotificationCenter.default.removeObserver(observer)
                seekObserver = nil
            }
        }

        // MARK: - Setup

        private func setupOutput() {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as NSNumber,
            ])
            player.currentItem?.add(output)
            playerItemOutput = output
        }

        private func startDisplayLink() {
            let proxy = DisplayLinkProxy()
            proxy.owner = self
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func observeSeek() {
            seekObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.timeJumpedNotification,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSeek() }
            }
        }

        private func handleSeek() {
            videoRenderer.flush()
            cachedFormatDescription = nil
        }

        // MARK: - Per-frame processing

        fileprivate func processFrame(_ link: CADisplayLink) {
            guard let output = playerItemOutput else { return }

            let itemTime = output.itemTime(forHostTime: link.targetTimestamp)
            guard itemTime.isValid, output.hasNewPixelBuffer(forItemTime: itemTime) else { return }

            var displayTime = CMTime.invalid
            guard let packed = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else { return }
            let pts = displayTime.isValid ? displayTime : itemTime

            guard let (leftBuffer, rightBuffer) = split(packed) else { return }

            let leftTagged = CMTaggedBuffer(tags: [CMTag.stereoView(.leftEye)], pixelBuffer: leftBuffer)
            let rightTagged = CMTaggedBuffer(tags: [CMTag.stereoView(.rightEye)], pixelBuffer: rightBuffer)
            let taggedBuffers = [leftTagged, rightTagged]

            // Reuse the format description across frames; re-create if dimensions changed.
            if cachedFormatDescription.map({ !$0.matchesTaggedBufferGroup(taggedBuffers) }) ?? true {
                cachedFormatDescription = CMFormatDescription(taggedBuffers: taggedBuffers)
            }
            guard let formatDesc = cachedFormatDescription else { return }

            guard let sampleBuffer = try? CMSampleBuffer(
                taggedBuffers: taggedBuffers,
                presentationTimeStamp: pts,
                duration: .invalid,
                formatDescription: formatDesc
            ) else { return }

            videoRenderer.enqueue(sampleBuffer)
        }

        // MARK: - Frame splitting

        /// Splits the packed source into (leftEye, rightEye) pixel buffers according to `layout`.
        private func split(_ source: CVPixelBuffer) -> (CVPixelBuffer, CVPixelBuffer)? {
            let w = CVPixelBufferGetWidth(source)
            let h = CVPixelBufferGetHeight(source)
            switch layout {
            case .sideBySide:
                guard let left = crop(source, x: 0, y: 0, width: w / 2, height: h),
                      let right = crop(source, x: w / 2, y: 0, width: w / 2, height: h)
                else { return nil }
                return (left, right)
            case .topAndBottom:
                guard let top = crop(source, x: 0, y: 0, width: w, height: h / 2),
                      let bottom = crop(source, x: 0, y: h / 2, width: w, height: h / 2)
                else { return nil }
                return (top, bottom)
            default:
                return nil
            }
        }

        /// Copies a rectangular region from `source` (BGRA, 4 bytes/pixel) into a new pixel buffer.
        /// For half-SBS the resulting buffer is anamorphically squeezed; the stereo presentation
        /// path stretches it to fill the screen plane, recovering the correct display aspect ratio.
        private func crop(_ source: CVPixelBuffer, x: Int, y: Int, width: Int, height: Int) -> CVPixelBuffer? {
            CVPixelBufferLockBaseAddress(source, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
            guard let srcBase = CVPixelBufferGetBaseAddress(source) else { return nil }

            let srcStride = CVPixelBufferGetBytesPerRow(source)
            let bytesPerPixel = 4 // kCVPixelFormatType_32BGRA

            var dst: CVPixelBuffer?
            guard CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32BGRA, nil, &dst
            ) == kCVReturnSuccess, let dst else { return nil }

            CVPixelBufferLockBaseAddress(dst, [])
            defer { CVPixelBufferUnlockBaseAddress(dst, []) }
            guard let dstBase = CVPixelBufferGetBaseAddress(dst) else { return nil }

            let dstStride = CVPixelBufferGetBytesPerRow(dst)
            for row in 0..<height {
                memcpy(
                    dstBase.advanced(by: row * dstStride),
                    srcBase.advanced(by: (y + row) * srcStride + x * bytesPerPixel),
                    width * bytesPerPixel
                )
            }
            return dst
        }
    }
#endif
