import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the 1024 pt master icon. Run: swift scripts/make-icon.swift
// Then scripts/build-app.sh copies App/AppIcon.icns into the bundle.

let canvas: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("could not create the drawing context")
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// Rounded square canvas, inset the way macOS app icons are.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.addPath(tilePath)
context.clip()

let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.05, green: 0.10, blue: 0.19, alpha: 1),
        CGColor(red: 0.05, green: 0.28, blue: 0.33, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 180, y: 900),
    end: CGPoint(x: 860, y: 140),
    options: []
)

// Soft glow behind the lock.
let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.18, green: 0.85, blue: 0.78, alpha: 0.34),
        CGColor(red: 0.18, green: 0.85, blue: 0.78, alpha: 0),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 512, y: 560),
    startRadius: 10,
    endCenter: CGPoint(x: 512, y: 560),
    endRadius: 330,
    options: []
)

// Top-left sheen.
let sheen = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    sheen,
    start: CGPoint(x: 150, y: 900),
    end: CGPoint(x: 560, y: 480),
    options: []
)

context.restoreGState()

// Lock body.
let bodyRect = CGRect(x: 332, y: 292, width: 360, height: 286)
let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 62, cornerHeight: 62, transform: nil)

context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 42,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
)
context.addPath(bodyPath)
context.setFillColor(CGColor(red: 0.94, green: 0.98, blue: 0.98, alpha: 1))
context.fillPath()
context.restoreGState()

// Shackle.
let shackle = CGMutablePath()
shackle.move(to: CGPoint(x: 392, y: 566))
shackle.addLine(to: CGPoint(x: 392, y: 654))
shackle.addCurve(
    to: CGPoint(x: 632, y: 654),
    control1: CGPoint(x: 392, y: 796),
    control2: CGPoint(x: 632, y: 796)
)
shackle.addLine(to: CGPoint(x: 632, y: 566))

context.addPath(shackle)
context.setStrokeColor(CGColor(red: 0.94, green: 0.98, blue: 0.98, alpha: 1))
context.setLineWidth(58)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

// Keyhole.
let keyhole = CGMutablePath()
keyhole.addEllipse(in: CGRect(x: 482, y: 430, width: 60, height: 60))
keyhole.move(to: CGPoint(x: 498, y: 444))
keyhole.addLine(to: CGPoint(x: 526, y: 444))
keyhole.addLine(to: CGPoint(x: 540, y: 354))
keyhole.addLine(to: CGPoint(x: 484, y: 354))
keyhole.closeSubpath()

context.addPath(keyhole)
context.setFillColor(CGColor(red: 0.05, green: 0.42, blue: 0.45, alpha: 1))
context.fillPath()

// Small teal status dot, bottom right, for a bit of life.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -6),
    blur: 18,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)
)
context.setFillColor(CGColor(red: 0.18, green: 0.85, blue: 0.78, alpha: 1))
context.fillEllipse(in: CGRect(x: 748, y: 172, width: 104, height: 104))
context.restoreGState()

guard let image = context.makeImage() else {
    fatalError("could not render the icon")
}

let output = URL(fileURLWithPath: "App/AppIcon-1024.png")
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("could not create \(output.path)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("could not write \(output.path)")
}
print(output.path)
