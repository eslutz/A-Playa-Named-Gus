#!/usr/bin/env swift

// Retired legacy icon generator.
//
// The current app icon source of truth is the Gus brand mark SVG at:
//   ../Gus.website/assets/gus-mark.svg
//
// Do not regenerate icons from the legacy pineapple drawing below. It is kept only as
// historical source context until the current SVG rasterization workflow is automated.

import AppKit
import CoreGraphics
import Darwin
import Foundation

let retirementMessage = """
Scripts/generate-app-icon.swift is retired and intentionally does not generate assets.
Use ../Gus.website/assets/gus-mark.svg as the app-icon source of truth, then rasterize it into Resources/Assets.xcassets and Resources/Watch/Assets.xcassets.
"""

FileHandle.standardError.write(Data(retirementMessage.utf8))
exit(EXIT_FAILURE)

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let assets = root.appending(path: "Resources/Assets.xcassets")
private let watchAssets = root.appending(path: "Resources/Watch/Assets.xcassets")

// MARK: - Winter Chill palette (Documentation/ROADMAP.md, M1 role table)

private let tealDeep = CGColor(red: 0x0B / 255.0, green: 0x2E / 255.0, blue: 0x33 / 255.0, alpha: 1) // #0B2E33
private let tealNight = CGColor(red: 0x06 / 255.0, green: 0x1A / 255.0, blue: 0x1E / 255.0, alpha: 1) // #061A1E
private let ice = CGColor(red: 0xB8 / 255.0, green: 0xE3 / 255.0, blue: 0xE9 / 255.0, alpha: 1) // #B8E3E9
private let tealMid = CGColor(red: 0x4F / 255.0, green: 0x7C / 255.0, blue: 0x82 / 255.0, alpha: 1) // #4F7C82
private let mist = CGColor(red: 0x93 / 255.0, green: 0xB1 / 255.0, blue: 0xB5 / 255.0, alpha: 1) // #93B1B5
private let mistLattice = CGColor(red: 0x93 / 255.0, green: 0xB1 / 255.0, blue: 0xB5 / 255.0, alpha: 0.6)
private let iceOutline = CGColor(red: 0xB8 / 255.0, green: 0xE3 / 255.0, blue: 0xE9 / 255.0, alpha: 0.4)

// Tinted-appearance icons must be grayscale; the system applies the user's tint.
private let tintBodyHigh = CGColor(gray: 0.95, alpha: 1)
private let tintBodyLow = CGColor(gray: 0.55, alpha: 1)
private let tintLattice = CGColor(gray: 1.0, alpha: 0.5)
private let tintCrown = CGColor(gray: 0.78, alpha: 1)
private let tintOutline = CGColor(gray: 1.0, alpha: 0.35)

// MARK: - Output table

private enum IconLayer {
    case flattened
    case background
    case middle
    case front
}

/// Icon appearance per the iOS 18+ appearance variants. `dark` and `tinted` render on a
/// transparent canvas (the system supplies the backdrop); `color` paints the teal field.
private enum IconStyle {
    case color
    case dark
    case tinted
}

private struct Output {
    let baseURL: URL
    let relativePath: String
    let width: Int
    let height: Int
    let layer: IconLayer
    var style: IconStyle = .color
}

private let outputs: [Output] = [
    // iOS universal: default + dark + tinted appearances.
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/icon-ios-1024.png", width: 1024, height: 1024, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/icon-ios-dark-1024.png", width: 1024, height: 1024, layer: .flattened, style: .dark),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/icon-ios-tinted-1024.png", width: 1024, height: 1024, layer: .flattened, style: .tinted),

    // macOS sizes.
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-16.png", width: 16, height: 16, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-32.png", width: 32, height: 32, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-64.png", width: 64, height: 64, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-128.png", width: 128, height: 128, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-256.png", width: 256, height: 256, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-512.png", width: 512, height: 512, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.appiconset/mac-1024.png", width: 1024, height: 1024, layer: .flattened),

    // visionOS layered stack.
    Output(baseURL: assets, relativePath: "AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/back.png", width: 1024, height: 1024, layer: .background),
    Output(baseURL: assets, relativePath: "AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/middle.png", width: 1024, height: 1024, layer: .middle),
    Output(baseURL: assets, relativePath: "AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/front.png", width: 1024, height: 1024, layer: .front),

    // tvOS layered App Icon + Top Shelf.
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back-400.png", width: 400, height: 240, layer: .background),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back-800.png", width: 800, height: 480, layer: .background),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front-400.png", width: 400, height: 240, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front-800.png", width: 800, height: 480, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/store-back-1280.png", width: 1280, height: 768, layer: .background),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/store-front-1280.png", width: 1280, height: 768, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/Top Shelf Image.imageset/topshelf-1920.png", width: 1920, height: 720, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/Top Shelf Image.imageset/topshelf-3840.png", width: 3840, height: 1440, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/Top Shelf Image Wide.imageset/topshelfwide-2320.png", width: 2320, height: 720, layer: .flattened),
    Output(baseURL: assets, relativePath: "AppIcon.brandassets/Top Shelf Image Wide.imageset/topshelfwide-4640.png", width: 4640, height: 1440, layer: .flattened),

    // watchOS universal (the system applies the circular mask).
    Output(baseURL: watchAssets, relativePath: "AppIcon.appiconset/icon-watch-1024.png", width: 1024, height: 1024, layer: .flattened),
]

// MARK: - Drawing

private func makeContext(width: Int, height: Int, transparent: Bool) -> CGContext {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    if !transparent {
        drawBackground(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return context
}

private func drawBackground(in context: CGContext, rect: CGRect) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [tealDeep, tealNight, tealDeep] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
}

private func drawIcon(in context: CGContext, canvas: CGSize, layer: IconLayer, style: IconStyle) {
    let size = min(canvas.width, canvas.height) * (canvas.width == canvas.height ? 0.74 : 0.7)
    let origin = CGPoint(x: (canvas.width - size) / 2, y: (canvas.height - size) / 2 - size * 0.02)
    let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))

    switch layer {
    case .flattened:
        drawBody(in: context, rect: rect, style: style)
        drawCrown(in: context, rect: rect, style: style)
    case .background:
        break
    case .middle:
        drawBody(in: context, rect: rect, style: style)
    case .front:
        drawCrown(in: context, rect: rect, style: style)
    }
}

private func drawBody(in context: CGContext, rect: CGRect, style: IconStyle) {
    let body = CGRect(
        x: rect.minX + rect.width * 0.27,
        y: rect.minY + rect.height * 0.14,
        width: rect.width * 0.46,
        height: rect.height * 0.62
    )

    let path = CGMutablePath()
    path.addEllipse(in: body)

    let bodyColors: [CGColor]
    let latticeColor: CGColor
    let outlineColor: CGColor
    switch style {
    case .color, .dark:
        // Ice highlights into teal depth (gradient runs depth → highlight).
        bodyColors = [tealMid, ice]
        latticeColor = mistLattice
        outlineColor = iceOutline
    case .tinted:
        bodyColors = [tintBodyLow, tintBodyHigh]
        latticeColor = tintLattice
        outlineColor = tintOutline
    }

    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: bodyColors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    context.setStrokeColor(latticeColor)
    context.setLineWidth(max(2, rect.width * 0.018))
    for offset in stride(from: -body.height, through: body.width + body.height, by: body.width * 0.18) {
        context.move(to: CGPoint(x: body.minX + offset, y: body.minY))
        context.addLine(to: CGPoint(x: body.minX + offset + body.height, y: body.maxY))
        context.strokePath()

        context.move(to: CGPoint(x: body.minX + offset, y: body.maxY))
        context.addLine(to: CGPoint(x: body.minX + offset + body.height, y: body.minY))
        context.strokePath()
    }
    context.restoreGState()

    context.addPath(path)
    context.setStrokeColor(outlineColor)
    context.setLineWidth(max(2, rect.width * 0.02))
    context.strokePath()
}

private func drawCrown(in context: CGContext, rect: CGRect, style: IconStyle) {
    let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.753)
    let baseY = center.y - rect.height * 0.018
    let baseRootX: CGFloat = 0.09
    let leafSpread = rect.width * 0.48
    let tipHeight = rect.height * 0.3
    let outerTipX = sin(1.0) * leafSpread * 0.5 / rect.width
    let innerTipX = sin(0.5) * leafSpread * 0.5 / rect.width

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: center.x + rect.width * x, y: baseY + tipHeight * y)
    }

    let path = CGMutablePath()
    path.move(to: p(-baseRootX, 0.0))
    path.addQuadCurve(to: p(-outerTipX, 0.82), control: p(-0.17, 0.48))
    path.addQuadCurve(to: p(-0.105, 0.15), control: p(-0.14, 0.5))
    path.addLine(to: p(-innerTipX, 0.92))
    path.addLine(to: p(-0.04, 0.18))
    path.addLine(to: p(0.0, 1.0))
    path.addLine(to: p(0.04, 0.18))
    path.addLine(to: p(innerTipX, 0.92))
    path.addQuadCurve(to: p(0.105, 0.15), control: p(0.14, 0.5))
    path.addQuadCurve(to: p(outerTipX, 0.82), control: p(0.14, 0.5))
    path.addQuadCurve(to: p(baseRootX, 0.0), control: p(0.17, 0.48))
    path.addLine(to: p(baseRootX, -0.006))
    path.addLine(to: p(-baseRootX, -0.006))
    path.closeSubpath()

    context.addPath(path)
    context.setFillColor(style == .tinted ? tintCrown : mist)
    context.fillPath()
}

private func writePNG(context: CGContext, to url: URL) throws {
    guard let cgImage = context.makeImage() else {
        throw NSError(domain: "GusIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not make CGImage"])
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GusIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

for output in outputs {
    // Dark and tinted appearance icons render on transparency per the HIG — the system
    // supplies the backdrop; layered-stack middle/front layers are transparent by design.
    let transparent = output.layer == .middle || output.layer == .front || output.style != .color
    let context = makeContext(width: output.width, height: output.height, transparent: transparent)
    drawIcon(in: context, canvas: CGSize(width: output.width, height: output.height), layer: output.layer, style: output.style)
    try writePNG(context: context, to: output.baseURL.appending(path: output.relativePath))
}

print("Generated \(outputs.count) Winter Chill icon assets.")
