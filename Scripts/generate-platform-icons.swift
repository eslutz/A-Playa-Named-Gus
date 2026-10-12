#!/usr/bin/env swift
// Rasterize the approved editable SVGs into tvOS/visionOS native depth layers.
// Run from the repository root: swift Scripts/generate-platform-icons.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Resources/Assets.xcassets")
let review = root.appendingPathComponent("Documentation/AppStore/platform-icon-review")
try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
func source(_ name: String) throws -> NSImage {
    let url = root.appendingPathComponent("Resources/AppIcon.icon/Assets/\(name).svg")
    guard let image = NSImage(data: try Data(contentsOf: url)) else { fatalError("Cannot render \(url.path)") }
    return image
}
let g = try source("Gus-G")
let play = try source("Gus-Play")
let info: [String: Any] = ["author": "xcode", "version": 1]
func json(_ value: [String: Any], _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let canonical = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    if let old = try? Data(contentsOf: url),
       let object = try? JSONSerialization.jsonObject(with: old),
       let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
       normalized == canonical { return }
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
enum Layer { case back, middle, front, composite }
func render(_ width: Int, _ height: Int, _ layer: Layer, _ url: URL, vision: Bool = false, mask: Bool = false, shelf: Bool = false) throws {
    let opaque = layer == .back || (layer == .composite && !mask)
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)
    else { fatalError("Bitmap allocation failed") }
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    context.cgContext.clear(bounds)
    if mask {
        let path = vision ? NSBezierPath(ovalIn: bounds) : NSBezierPath(roundedRect: bounds, xRadius: CGFloat(height) * 0.07, yRadius: CGFloat(height) * 0.07)
        path.addClip()
    }
    if layer == .back || layer == .composite {
        let gradient = NSGradient(starting: NSColor(srgbRed: 11/255, green: 46/255, blue: 51/255, alpha: 1), ending: NSColor(srgbRed: 6/255, green: 26/255, blue: 30/255, alpha: 1))!
        gradient.draw(in: bounds, angle: -45)
    }
    // Center the actual asymmetric mark (x 36...231) rather than its SVG canvas.
    // tvOS leaves approximately 15% vertical clearance for focus/parallax cropping.
    let side = CGFloat(height) * (vision ? 0.94 : (shelf ? 0.96 : 1.05))
    let rect = NSRect(x: (CGFloat(width)-side)/2 - side * 5.5/256,
                      y: (CGFloat(height)-side)/2 + side * 5.0/256,
                      width: side, height: side)
    if layer == .middle || layer == .composite { g.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1) }
    // PNG alpha does not reproduce Icon Composer's glass material. Keep the arrow
    // nearly opaque for comparable visual weight, with a subtle G overlap.
    if layer == .front || layer == .composite { play.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.95) }
    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let result = cg.makeImage() else { fatalError("Image creation failed") }
    let bitmap = NSBitmapImageRep(cgImage: result)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: url)
}
let visionRoot = assets.appendingPathComponent("AppIcon.solidimagestack")
for (name, layer) in [("Back", Layer.back), ("Middle", .middle), ("Front", .front)] {
    try render(1024, 1024, layer, visionRoot.appendingPathComponent("\(name).solidimagestacklayer/Content.imageset/\(name.lowercased()).png"), vision: true)
}
let tvRoot = assets.appendingPathComponent("AppIcon.brandassets")
for (stack, sizes) in [("App Icon", [(400,240,"1x"),(800,480,"2x")]), ("App Icon - App Store", [(1280,768,"1x")])] {
    let stackRoot = tvRoot.appendingPathComponent("\(stack).imagestack")
    try json(["info": info, "layers": ["Front", "Middle", "Back"].map { ["filename": "\($0).imagestacklayer"] }], stackRoot.appendingPathComponent("Contents.json"))
    for (name, layer) in [("Back", Layer.back), ("Middle", .middle), ("Front", .front)] {
        let folder = stackRoot.appendingPathComponent("\(name).imagestacklayer")
        try json(["info": info], folder.appendingPathComponent("Contents.json"))
        var images: [[String: String]] = []
        for (width, height, scale) in sizes {
            let filename = "\(stack.contains("Store") ? "store-" : "")\(name.lowercased())-\(width).png"
            try render(width, height, layer, folder.appendingPathComponent("Content.imageset/\(filename)"))
            images.append(["filename": filename, "idiom": "tv", "scale": scale])
        }
        try json(["info": info, "images": images], folder.appendingPathComponent("Content.imageset/Contents.json"))
    }
}
// Keep the catalog's static Top Shelf fallback consistent with the approved identity.
for (folder, prefix, sizes) in [("Top Shelf Image", "topshelf", [(1920,720),(3840,1440)]), ("Top Shelf Image Wide", "topshelfwide", [(2320,720),(4640,1440)])] {
    for (w,h) in sizes { try render(w,h,.composite,tvRoot.appendingPathComponent("\(folder).imageset/\(prefix)-\(w).png"), shelf: true) }
}
try render(640,640,.composite,review.appendingPathComponent("visionOS-preview.png"),vision:true,mask:true)
try render(800,480,.composite,review.appendingPathComponent("tvOS-preview.png"),mask:true)
try render(96,96,.composite,review.appendingPathComponent("visionOS-small.png"),vision:true,mask:true)
try render(200,120,.composite,review.appendingPathComponent("tvOS-small.png"),mask:true)
print("Generated native tvOS/visionOS layer assets, Top Shelf fallbacks, and review composites.")

func embedded(_ url: URL) throws -> String { "data:image/png;base64," + (try Data(contentsOf: url)).base64EncodedString() }
func card(_ title: String, _ prefix: URL, _ suffix: String, _ files: [String], _ circle: Bool) throws -> String {
    let names = ["Back", "Middle", "Front"]
    var images = ""
    for (i,name) in names.enumerated() {
        let url = prefix.appendingPathComponent("\(name).\(suffix)/Content.imageset/\(files[i])")
        images += "<img class='layer l\(i)' src='\(try embedded(url))' alt='\(name == "Back" ? "Teal background" : name == "Middle" ? "Connected G" : "Play arrow")'>"
    }
    return """
    <section><h2>\(title)</h2><div class="stage"><div class="icon \(circle ? "circle" : "tv")">\(images)</div></div>
    <label>Preview width <input type="range" min="48" max="400" value="\(circle ? 300 : 400)" oninput="this.closest('section').querySelector('.icon').style.width=this.value+'px'; this.nextElementSibling.textContent=this.value+'px'"><output>\(circle ? 300 : 400)px</output></label>
    <div class="toggles"><label><input type="checkbox" checked onchange="toggle(this,0)">Background</label><label><input type="checkbox" checked onchange="toggle(this,1)">G</label><label><input type="checkbox" checked onchange="toggle(this,2)">Arrow</label></div>
    <p>\(circle ? "1024 × 1024 native layers; circular mask shown for review." : "400 × 240, 800 × 480, and 1280 × 768 native stacks.")</p></section>
    """
}
let visionCard = try card("visionOS", visionRoot, "solidimagestacklayer", ["back.png","middle.png","front.png"], true)
let tvCard = try card("tvOS", tvRoot.appendingPathComponent("App Icon.imagestack"), "imagestacklayer", ["back-800.png","middle-800.png","front-800.png"], false)
let html = """
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Gus — platform icon review</title>
<style>body{margin:0;background:#111c20;color:#e2edf0;font:16px system-ui}main{max-width:1100px;margin:auto;padding:40px}h1{font-size:32px}p{color:#a6bac2;line-height:1.5}.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}section{padding:24px;background:#1d2b31;border:1px solid #34464e;border-radius:20px}.stage{height:420px;display:grid;place-items:center;background:#273b43;border-radius:12px}.icon{position:relative;overflow:hidden;flex-shrink:0}.circle{width:300px;aspect-ratio:1;border-radius:50%}.tv{width:400px;max-width:100%;aspect-ratio:5/3;border-radius:7% / 12%}.layer{position:absolute;inset:0;width:100%;height:100%}label{display:inline-flex;gap:8px;align-items:center;margin-top:18px}.toggles{display:flex;gap:16px;flex-wrap:wrap}input{accent-color:#b8e3e9}output{min-width:45px;font-variant-numeric:tabular-nums}@media(max-width:850px){.grid{grid-template-columns:1fr}main{padding:20px}}</style>
<main><p>GUS / ICON REVIEW · UNCOMMITTED</p><h1>One mark. Two native layer stacks.</h1><p>Approved connected G and enlarged play arrow, adapted to each platform. Adjust the preview width and toggle layers to inspect the composition.</p><div class="grid">\(visionCard)\(tvCard)</div><p>These composites show the actual PNG assets. Masks are applied only in this preview. System lighting, shadows, focus enlargement, and parallax are not simulated; review those in Xcode or on-device before release.</p></main>
<script>function toggle(el,index){el.closest('section').querySelector('.l'+index).style.visibility=el.checked?'visible':'hidden'}</script></html>
"""
try html.write(to: review.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
