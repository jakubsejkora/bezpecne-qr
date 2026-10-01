// Draws the placeholder app icon (1024×1024, opaque PNG) with CoreGraphics.
// Usage: xcrun swift scripts/make-app-icon.swift ios/BezpecneQR/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
// The final icon will be designed later (Icon Composer); this one exists so builds can be uploaded.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast → no alpha channel, as App Store Connect requires.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1) // top-left origin

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// Background
let background = CGGradient(colorsSpace: space, colors: [color(0x4F8DFF), color(0x1F3A8A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let highlight = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(highlight, startCenter: CGPoint(x: 250, y: 190), startRadius: 0, endCenter: CGPoint(x: 250, y: 190), endRadius: 640, options: [])

// Shield
let shield = CGMutablePath()
shield.move(to: CGPoint(x: 512, y: 150))
shield.addCurve(to: CGPoint(x: 800, y: 262), control1: CGPoint(x: 610, y: 215), control2: CGPoint(x: 705, y: 250))
shield.addLine(to: CGPoint(x: 800, y: 520))
shield.addCurve(to: CGPoint(x: 512, y: 884), control1: CGPoint(x: 800, y: 700), control2: CGPoint(x: 670, y: 820))
shield.addCurve(to: CGPoint(x: 224, y: 520), control1: CGPoint(x: 354, y: 820), control2: CGPoint(x: 224, y: 700))
shield.addLine(to: CGPoint(x: 224, y: 262))
shield.addCurve(to: CGPoint(x: 512, y: 150), control1: CGPoint(x: 319, y: 250), control2: CGPoint(x: 414, y: 215))
shield.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: color(0x0B1B4D, 0.45))
ctx.addPath(shield)
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// QR finder patterns
func roundedRect(_ rect: CGRect, _ radius: CGFloat, _ fill: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}
func finder(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
    roundedRect(CGRect(x: x, y: y, width: s, height: s), s * 0.22, color(0x1F3A8A))
    roundedRect(CGRect(x: x, y: y, width: s, height: s).insetBy(dx: s * 0.19, dy: s * 0.19), s * 0.1, color(0xFFFFFF))
    roundedRect(CGRect(x: x, y: y, width: s, height: s).insetBy(dx: s * 0.34, dy: s * 0.34), s * 0.07, color(0x1F3A8A))
}
finder(332, 296, 150)
finder(542, 296, 150)
finder(332, 506, 150)

// Check mark
ctx.setStrokeColor(color(0x16A34A))
ctx.setLineWidth(48)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 552, y: 590))
ctx.addLine(to: CGPoint(x: 610, y: 648))
ctx.addLine(to: CGPoint(x: 700, y: 530))
ctx.strokePath()

guard CommandLine.arguments.count > 1, let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <output.png>\n".utf8))
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(url.path)")
