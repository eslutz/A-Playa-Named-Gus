#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The default iOS and Watch App Store icons require an opaque canvas. Preserve
/// their artwork and fill rounded transparent corners with Gus's deep teal.
/// Dark appearances and native Mac icons retain their supported transparency.
let paths = [
    "Resources/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png",
    "Resources/Watch/Assets.xcassets/AppIcon.appiconset/icon-watch-1024.png",
]
for path in paths {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: image.width, height: image.height,
              bitsPerComponent: 8, bytesPerRow: image.width * 4,
              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { fatalError("Cannot decode app icon: \(path)") }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(CGColor(colorSpace: space, components: [11 / 255, 46 / 255, 51 / 255, 1])!)
    context.fill(rect)
    context.draw(image, in: rect)
    guard let opaque = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot encode app icon: \(path)") }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save app icon: \(path)") }
    print("Saved opaque app icon: \(path)")
}
