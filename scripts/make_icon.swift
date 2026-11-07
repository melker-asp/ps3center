// Renders the PS3 Center app icon (1024 px master) in the app's splash style and writes every
// size an AppIcon.appiconset for macOS needs. Usage: `make icon` (or swift scripts/make_icon.swift <dir>).
import AppKit
import CoreText

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Big Sur / Tahoe icon grid: an 824 pt squircle centred on a 1024 canvas.
func squircle(in rect: CGRect) -> CGPath {
    // Superellipse (n = 5) approximates Apple's continuous-corner icon shape.
    let path = CGMutablePath()
    let n: CGFloat = 5, steps = 720
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    // Drop shadow under the tile, as macOS icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0.03, 0.09, 0.36))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // The splash gradient: PlayStation blue, lighter at the top left (CG's y axis points up).
    let gradient = CGGradient(colorsSpace: space,
                              colors: [rgb(0.19, 0.45, 0.85), rgb(0.11, 0.27, 0.62), rgb(0.03, 0.09, 0.36)] as CFArray,
                              locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Angled light planes, the same shapes as SplashBackground (top-left origin flipped).
    func plane(_ points: [(CGFloat, CGFloat)], alpha: CGFloat) {
        let p = CGMutablePath()
        for (i, pt) in points.enumerated() {
            let point = CGPoint(x: body.minX + pt.0 * body.width, y: body.maxY - pt.1 * body.height)
            i == 0 ? p.move(to: point) : p.addLine(to: point)
        }
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(rgb(1, 1, 1, alpha))
        ctx.fillPath()
    }
    plane([(0.18, 0), (0.30, 0), (0, 1), (0, 0.72)], alpha: 0.09)
    plane([(0.32, 0), (1, 0), (1, 0.19)], alpha: 0.12)
    plane([(1, 0.52), (1, 1), (0.13, 1)], alpha: 0.08)

    // A thin highlight along the top edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.18))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // "PS3" in heavy SF Pro Rounded, centred, with a soft shadow.
    let base = NSFont.systemFont(ofSize: 330, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 330) } ?? base
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -6,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "PS3", attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0, 0.02, 0.15, 0.45))
    ctx.textPosition = CGPoint(x: 512 - bounds.midX, y: 548 - bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // A short accent bar under the letters, the app's lighter PlayStation blue.
    let bar = CGRect(x: 512 - 120, y: 345, width: 240, height: 26)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.setFillColor(rgb(0.33, 0.63, 1.00))
    ctx.fillPath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

// macOS idiom sizes: (point size, scale).
let entries: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in entries {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(size: pixels).write(to: outDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(entries.count) icons to \(outDir.path)")
