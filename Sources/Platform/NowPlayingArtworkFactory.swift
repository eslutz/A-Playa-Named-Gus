import Foundation
import MediaPlayer

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

enum NowPlayingArtworkFactory {
    static func artwork(from data: Data) -> MPMediaItemArtwork? {
        #if os(macOS)
            guard let image = NSImage(data: data) else { return nil }
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
            guard let image = UIImage(data: data) else { return nil }
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #endif
    }
}
