#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Render a Mystral app icon at the given size and write it to outputURL.
// Design: rounded-rect macOS-style tile with a vibrant cyan→indigo gradient,
// a centered three-blade fan glyph, and a subtle inner highlight.

func renderIcon(size: CGFloat) -> NSImage {
    let pixelSize = NSSize(width: size, height: size)
    let image = NSImage(size: pixelSize, flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        let cornerRadius = size * 0.225
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Background gradient.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bgColors = [
            CGColor(red: 0.10, green: 0.78, blue: 0.95, alpha: 1.0), // cyan
            CGColor(red: 0.32, green: 0.30, blue: 0.92, alpha: 1.0), // indigo
            CGColor(red: 0.10, green: 0.10, blue: 0.32, alpha: 1.0)  // deep
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.55, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: locations) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: rect.height),
                end: CGPoint(x: rect.width, y: 0),
                options: []
            )
        }

        // Glow ring behind the fan.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let glowRadius = size * 0.36
        if let glow = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawRadialGradient(
                glow,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: glowRadius,
                options: []
            )
        }

        // Three-blade fan.
        let bladeRadius = size * 0.32
        let hubRadius = size * 0.06
        let bladeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)

        for i in 0..<3 {
            let angle = (CGFloat(i) * 2 * .pi / 3) - (.pi / 2)

            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: angle)

            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: 0, y: hubRadius * 0.4))
            blade.addCurve(
                to: CGPoint(x: bladeRadius * 0.85, y: bladeRadius * 0.55),
                control1: CGPoint(x: bladeRadius * 0.20, y: hubRadius * 0.4),
                control2: CGPoint(x: bladeRadius * 0.55, y: bladeRadius * 0.10)
            )
            blade.addCurve(
                to: CGPoint(x: bladeRadius * 0.20, y: -hubRadius * 0.1),
                control1: CGPoint(x: bladeRadius * 0.95, y: bladeRadius * 0.20),
                control2: CGPoint(x: bladeRadius * 0.65, y: -hubRadius * 0.7)
            )
            blade.addLine(to: CGPoint(x: 0, y: hubRadius * 0.4))
            blade.closeSubpath()

            ctx.setFillColor(bladeColor)
            ctx.addPath(blade)
            ctx.fillPath()

            ctx.restoreGState()
        }

        // Hub.
        ctx.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.32, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(
            x: center.x - hubRadius,
            y: center.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        ))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
        ctx.fillEllipse(in: CGRect(
            x: center.x - hubRadius * 0.4,
            y: center.y - hubRadius * 0.4,
            width: hubRadius * 0.8,
            height: hubRadius * 0.8
        ))

        ctx.restoreGState()

        // Inner highlight stroke for depth.
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        ctx.setLineWidth(size * 0.012)
        ctx.strokePath()

        return true
    }
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: generate-icon.swift <output-dir>")
    exit(1)
}
let outputDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in sizes {
    let img = renderIcon(size: CGFloat(pixels))
    let dest = outputDir.appendingPathComponent(name)
    try writePNG(img, to: dest)
    print("wrote \(name) (\(pixels)x\(pixels))")
}
print("done.")
