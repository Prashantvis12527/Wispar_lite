// Draws the WisprLite logo. Usage: swift Assets/make_icon.swift <outdir>
// Writes icon_1024.png (app icon) and menubar.png / menubar@2x.png (template glyph).
import AppKit

func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, CGFloat(size))
    return rep.representation(using: .png, properties: [:])!
}

// Bars: (x center, half height) as fractions of the canvas; they thin out and fade to the right.
let bars: [(x: CGFloat, h: CGFloat, a: CGFloat)] = [
    (0.285, 0.10, 1.00), (0.395, 0.19, 1.00), (0.505, 0.26, 1.00), (0.615, 0.17, 0.72), (0.725, 0.08, 0.40),
]

func appIcon(_ c: CGContext, _ s: CGFloat) {
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    c.addPath(path); c.setFillColor(NSColor(red: 0.3, green: 0.4, blue: 0.9, alpha: 1).cgColor); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(path); c.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 1).cgColor,   // sky
        NSColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 1).cgColor,   // periwinkle
        NSColor(red: 0.24, green: 0.20, blue: 0.70, alpha: 1).cgColor,   // indigo
    ] as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: s * 0.3, y: s * 0.95), end: CGPoint(x: s * 0.7, y: s * 0.05), options: [])
    // soft top glow
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.35, y: s * 0.85), startRadius: 0,
                         endCenter: CGPoint(x: s * 0.35, y: s * 0.85), endRadius: s * 0.55, options: [])
    c.restoreGState()
    // bars
    let w = s * 0.07, cy = s * 0.47
    for b in bars {
        let r = CGRect(x: b.x * s - w / 2, y: cy - b.h * s, width: w, height: b.h * 2 * s)
        c.addPath(CGPath(roundedRect: r, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        c.setFillColor(NSColor.white.withAlphaComponent(b.a).cgColor); c.fillPath()
    }
    // floating specks: the "light" part
    for (x, y, d, a) in [(0.64, 0.72, 0.035, 0.85), (0.73, 0.64, 0.024, 0.6), (0.79, 0.74, 0.016, 0.4)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        c.setFillColor(NSColor.white.withAlphaComponent(a).cgColor)
        c.fillEllipse(in: CGRect(x: x * s - d * s / 2, y: y * s - d * s / 2, width: d * s, height: d * s))
    }
}

func menubar(_ c: CGContext, _ s: CGFloat) {
    let w = s * 0.11, cy = s * 0.5
    for (i, b) in bars.enumerated() {
        let x = s * (0.14 + 0.18 * CGFloat(i)) + w / 2, h = b.h * 1.9 * s
        c.addPath(CGPath(roundedRect: CGRect(x: x - w / 2, y: cy - h, width: w, height: h * 2), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        c.setFillColor(NSColor.black.withAlphaComponent(i == 4 ? 0.5 : 1).cgColor); c.fillPath()
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(size: 1024, draw: appIcon).write(to: out.appendingPathComponent("icon_1024.png"))
try render(size: 18, draw: menubar).write(to: out.appendingPathComponent("menubar.png"))
try render(size: 36, draw: menubar).write(to: out.appendingPathComponent("menubar@2x.png"))
