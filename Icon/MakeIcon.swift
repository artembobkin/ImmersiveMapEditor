// Draws the app's icon, Icon/AppIcon.png (1024 px): one map tile in
// isometric view on a sky, in the tiles' own palette: a crossroads with a
// zebra, warm plaster houses under cool roofs, two trees.
//
//   swift Icon/MakeIcon.swift Icon/AppIcon.png
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func colour(_ hex: UInt32, _ f: Double = 1) -> CGColor {
    CGColor(red: min(1, Double((hex >> 16) & 255) / 255 * f), green: min(1, Double((hex >> 8) & 255) / 255 * f),
            blue: min(1, Double(hex & 255) / 255 * f), alpha: 1)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let g = NSGraphicsContext(bitmapImageRep: rep)!
let c = g.cgContext

// The macOS icon shape: a rounded square on the 824 px grid of a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
c.addPath(shape)
c.setFillColor(colour(0x9CC1E6))
c.fillPath()
c.restoreGState()
c.saveGState()
c.addPath(shape)
c.clip()
let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                     colors: [colour(0xDCEBF8), colour(0x8DB4E2)] as CFArray, locations: [0, 1])!
c.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Isometric: x to the right and back, y to the left and back, z up.
let unit = 330.0
let origin = CGPoint(x: 512, y: 300)
func p(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
    CGPoint(x: origin.x + (x - y) * cos(.pi / 6) * unit, y: origin.y + (x + y) * sin(.pi / 6) * unit + z * unit)
}
func poly(_ pts: [CGPoint], _ fill: CGColor) {
    c.beginPath()
    c.addLines(between: pts)
    c.closePath()
    c.setFillColor(fill)
    c.fillPath()
}
/// A flat rectangle on the tile's top, x0..x1 by y0..y1.
func flat(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ z: Double, _ fill: CGColor) {
    poly([p(x0, y0, z), p(x1, y0, z), p(x1, y1, z), p(x0, y1, z)], fill)
}
/// A box: its two near walls sided as the palette sides them, and its roof.
func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ z0: Double, _ z1: Double,
         wall: UInt32, roof: UInt32) {
    poly([p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1)], colour(wall, 1.03))   // lit
    poly([p(x0, y0, z0), p(x0, y1, z0), p(x0, y1, z1), p(x0, y0, z1)], colour(wall, 0.82))   // shade
    flat(x0, y0, x1, y1, z1, colour(roof))
    // The light rim of the cornice, outlining it from above.
    c.setStrokeColor(colour(0xF6EEDF))
    c.setLineWidth(5)
    c.beginPath()
    c.addLines(between: [p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1)])
    c.closePath()
    c.strokePath()
}

let t = 0.12    // the slab's thickness
// The slab: its sides, then its top.
poly([p(0, 0, -t), p(1, 0, -t), p(1, 0, 0), p(0, 0, 0)], colour(0xC9C4C7, 0.85))
poly([p(0, 0, -t), p(0, 1, -t), p(0, 1, 0), p(0, 0, 0)], colour(0xC9C4C7, 0.7))
flat(0, 0, 1, 1, 0, colour(0xE6E2DC))

// The crossroads: kerbs, asphalt, markings.
let r0 = 0.40, r1 = 0.60, k = 0.025
flat(r0 - k, 0, r1 + k, 1, 0, colour(0xA6A3B1))
flat(0, r0 - k, 1, r1 + k, 0, colour(0xA6A3B1))
flat(r0, 0, r1, 1, 0, colour(0x6E6A7D))
flat(0, r0, 1, r1, 0, colour(0x6E6A7D))
for s in stride(from: 0.03, to: 0.36, by: 0.1) {
    flat(0.495, s, 0.505, s + 0.05, 0, colour(0xECE8E1))
    flat(0.495, 1 - s - 0.05, 0.505, 1 - s, 0, colour(0xECE8E1))
    flat(s, 0.495, s + 0.05, 0.505, 0, colour(0xECE8E1))
    flat(1 - s - 0.05, 0.495, 1 - s, 0.505, 0, colour(0xECE8E1))
}
// A zebra on the near arm.
for i in 0..<5 {
    let x = r0 + 0.02 + Double(i) * 0.04
    flat(x, 0.30, x + 0.022, 0.37, 0, colour(0xECE8E1))
}

// Houses, far first so the near ones stand in front.
box(0.66, 0.66, 0.95, 0.95, 0, 0.62, wall: 0xEFD3A1, roof: 0x9AA2B8)
box(0.05, 0.68, 0.33, 0.95, 0, 0.42, wall: 0xC8735A, roof: 0x7F8AA6)
box(0.68, 0.06, 0.94, 0.32, 0, 0.34, wall: 0xF2DDB8, roof: 0x9AA2B8)
// Trees on the near block, clear of the crossroads.
for (x, y, r) in [(0.08, 0.30, 34.0), (0.22, 0.08, 30.0)] {
    let foot = p(x, y, 0)
    c.setFillColor(colour(0x8A5A3C))
    c.fill(CGRect(x: foot.x - 5, y: foot.y, width: 10, height: r * 0.8))
    c.setFillColor(colour(0x4A9440))
    c.fillEllipse(in: CGRect(x: foot.x - r, y: foot.y + r * 0.45, width: 2 * r, height: 1.85 * r))
    c.setFillColor(colour(0x7BC25A))
    c.fillEllipse(in: CGRect(x: foot.x - r * 0.88, y: foot.y + r * 0.7, width: 1.76 * r, height: 1.6 * r))
}
c.restoreGState()

// A thin light edge round the shape.
c.addPath(shape)
c.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
c.setLineWidth(3)
c.strokePath()

g.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
