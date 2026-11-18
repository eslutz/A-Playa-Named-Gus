import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Read an imported image under its security scope and normalize it to a bounded JPEG.
enum CollectionArtwork {
    static func jpeg(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024 else { throw GusError.server(String(localized: "Choose an image smaller than 20 MB.")) }
        return try jpeg(from: Data(contentsOf: url), maxPixelSize: 4096)
    }

    /// Normalize the selected photo and discard source metadata before upload.
    static func jpeg(from data: Data, maxPixelSize: Int) throws -> Data {
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw GusError.server(String(localized: "Choose an image smaller than 20 MB.")) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { throw GusError.server(String(localized: "This image could not be opened.")) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw GusError.server(String(localized: "This image could not be encoded.")) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw GusError.server(String(localized: "This image could not be encoded.")) }
        return output as Data
    }
}
