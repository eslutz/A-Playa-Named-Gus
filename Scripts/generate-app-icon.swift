#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let assets = root.appending(path: "Resources/Assets.xcassets")

private let navy = CGColor(red: 0.0, green: 0.043, blue: 0.145, alpha: 1)
private let black = CGColor(red: 0.063, green: 0.063, blue: 0.063, alpha: 1)
private let purple = CGColor(red: 0.675, green: 0.361, blue: 0.765, alpha: 1)
private let blue = CGColor(red: 0.0, green: 0.643, blue: 0.863, alpha: 1)
private let line = CGColor(red: 1, green: 1, blue: 1, alpha: 0.45)

private enum IconLayer {
    case flattened
    case background
    case middle
    case front
}

private struct Output {
    let relativePath: String
    let width: Int
    let height: Int
    let layer: IconLayer
}

private let outputs: [Output] = [
    Output(relativePath: "AppIcon.appiconset/icon-ios-1024.png", width: 1024, height: 1024, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-16.png", width: 16, height: 16, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-32.png", width: 32, height: 32, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-64.png", width: 64, height: 64, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-128.png", width: 128, height: 128, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-256.png", width: 256, height: 256, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-512.png", width: 512, height: 512, layer: .flattened),
    Output(relativePath: "AppIcon.appiconset/mac-1024.png", width: 1024, height: 1024, layer: .flattened),

    Output(relativePath: "AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/back.png", width: 1024, height: 1024, layer: .background),
    Output(relativePath: "AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/middle.png", width: 1024, height: 1024, layer: .middle),
    Output(relativePath: "AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/front.png", width: 1024, height: 1024, layer: .front),

    Output(relativePath: "AppIcon.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back-400.png", width: 400, height: 240, layer: .background),
    Output(relativePath: "AppIcon.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back-800.png", width: 800, height: 480, layer: .background),
    Output(relativePath: "AppIcon.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front-400.png", width: 400, height: 240, layer: .flattened),
    Output(relativePath: "AppIcon.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front-800.png", width: 800, height: 480, layer: .flattened),
    Output(relativePath: "AppIcon.brandassets/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/store-back-1280.png", width: 1280, height: 768, layer: .background),
    Output(relativePath: "AppIcon.brandassets/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/store-front-1280.png", width: 1280, height: 768, layer: .flattened),
    Output(relativePath: "AppIcon.brandassets/Top Shelf Image.imageset/topshelf-1920.png", width: 1920, height: 720, layer: .flattened),
    Output(relativePath: "AppIcon.brandassets/Top Shelf Image.imageset/topshelf-3840.png", width: 3840, height: 1440, layer: .flattened),
    Output(relativePath: "AppIcon.brandassets/Top Shelf Image Wide.imageset/topshelfwide-2320.png", width: 2320, height: 720, layer: .flattened),
    Output(relativePath: "AppIcon.brandassets/Top Shelf Image Wide.imageset/topshelfwide-4640.png", width: 4640, height: 1440, layer: .flattened),
]

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
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [navy, black, navy] as CFArray, locations: [0.0, 0.55, 1.0])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
}

private func drawIcon(in context: CGContext, canvas: CGSize, layer: IconLayer) {
    let size = min(canvas.width, canvas.height) * (canvas.width == canvas.height ? 0.74 : 0.7)
    let origin = CGPoint(x: (canvas.width - size) / 2, y: (canvas.height - size) / 2 - size * 0.02)
    let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))

    switch layer {
    case .flattened:
        drawBody(in: context, rect: rect)
        drawCrown(in: context, rect: rect)
    case .background:
        break
    case .middle:
        drawBody(in: context, rect: rect)
    case .front:
        drawCrown(in: context, rect: rect)
    }
}

private func drawBody(in context: CGContext, rect: CGRect) {
    let body = CGRect(
        x: rect.minX + rect.width * 0.27,
        y: rect.minY + rect.height * 0.14,
        width: rect.width * 0.46,
        height: rect.height * 0.62
    )

    let path = CGMutablePath()
    path.addEllipse(in: body)

    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [purple, blue] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    context.setStrokeColor(line)
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
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    context.setLineWidth(max(2, rect.width * 0.02))
    context.strokePath()
}

private func drawCrown(in context: CGContext, rect: CGRect) {
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
    context.setFillColor(blue)
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
    try data.write(to: url, options: .atomic)
}

for output in outputs {
    let transparent = output.layer == .middle || output.layer == .front
    let context = makeContext(width: output.width, height: output.height, transparent: transparent)
    drawIcon(in: context, canvas: CGSize(width: output.width, height: output.height), layer: output.layer)
    try writePNG(context: context, to: assets.appending(path: output.relativePath))
}

print("Generated \(outputs.count) Jellyfin-themed icon assets.")
