import AppKit

// Shared diagonal <> mark. Coordinates use a bottom-left origin.
func mark(_ rect: NSRect, color: NSColor) {
    color.setStroke()
    for points: [(CGFloat, CGFloat)] in [
        [(0.20, 0.47), (0.20, 0.20), (0.47, 0.20)],
        [(0.53, 0.80), (0.80, 0.80), (0.80, 0.53)]
    ] {
        let path = NSBezierPath()
        path.lineWidth = rect.width * 0.105
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.stroke()
    }
}

func render(size: Int, to path: String, draw: (NSRect) -> Void) {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Icons"
try! FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("PinchDial-icons-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 2 ? "@2x" : ""
        render(size: pixels, to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png").path) { rect in
            let tile = rect.insetBy(dx: rect.width * 0.09, dy: rect.height * 0.09)
            let shape = NSBezierPath(roundedRect: tile, xRadius: rect.width * 0.19, yRadius: rect.height * 0.19)
            NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.30, blue: 0.88, alpha: 1),
                       ending: NSColor(srgbRed: 0.25, green: 0.64, blue: 1, alpha: 1))!.draw(in: shape, angle: 70)
            mark(rect.insetBy(dx: rect.width * 0.19, dy: rect.height * 0.19), color: .white)
        }
    }
}
for scale in [1, 2] {
    render(size: 18 * scale, to: "\(root)/MenuBarIcon\(scale == 2 ? "@2x" : "").png") {
        mark($0, color: .black)
    }
}

// ICNS supports PNG payloads directly for each resolution.
func integer(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var chunks = Data()
for (tag, name) in [("icp4", "16x16"), ("icp5", "32x32"), ("icp6", "32x32@2x"),
                    ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"),
                    ("ic10", "512x512@2x"), ("ic11", "16x16@2x"), ("ic12", "32x32@2x"),
                    ("ic13", "128x128@2x"), ("ic14", "256x256@2x")] {
    let png = try! Data(contentsOf: iconset.appendingPathComponent("icon_\(name).png"))
    chunks.append(Data(tag.utf8))
    chunks.append(integer(png.count + 8))
    chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(integer(chunks.count + 8))
icns.append(chunks)
try! icns.write(to: URL(fileURLWithPath: "\(root)/AppIcon.icns"))
