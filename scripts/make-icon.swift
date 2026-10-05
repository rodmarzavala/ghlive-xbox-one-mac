#!/usr/bin/env swift
// Renders Resources/AppIcon.icns: a 2x3 fret grid (black row on top, white row below) on a rounded gradient.
// Usage: scripts/make-icon.swift <output.icns>
import AppKit
import Foundation

let canvas: CGFloat = 1024
let cornerRatio: CGFloat = 0.2237  // the macOS icon squircle approximation
let iconSizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func drawIcon(in context: CGContext) {
    let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let inset = canvas * 0.04
    let body = bounds.insetBy(dx: inset, dy: inset)
    let path = CGPath(
        roundedRect: body, cornerWidth: body.width * cornerRatio, cornerHeight: body.width * cornerRatio,
        transform: nil)

    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [
        CGColor(red: 0.36, green: 0.20, blue: 0.80, alpha: 1), CGColor(red: 0.10, green: 0.07, blue: 0.30, alpha: 1),
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: canvas / 2, y: body.maxY), end: CGPoint(x: canvas / 2, y: body.minY), options: [])
    context.restoreGState()

    let fret = canvas * 0.19
    let gap = canvas * 0.055
    let gridWidth = fret * 3 + gap * 2
    let gridHeight = fret * 2 + gap
    let originX = (canvas - gridWidth) / 2
    let originY = (canvas - gridHeight) / 2
    for row in 0..<2 {
        let isBlackRow = row == 1  // CoreGraphics y grows upwards: row 1 is the top row
        for column in 0..<3 {
            let rect = CGRect(
                x: originX + CGFloat(column) * (fret + gap), y: originY + CGFloat(row) * (fret + gap), width: fret,
                height: fret)
            drawFret(in: context, rect: rect, isBlack: isBlackRow, isLit: column == 1)
        }
    }
}

func drawFret(in context: CGContext, rect: CGRect, isBlack: Bool, isLit: Bool) {
    context.saveGState()
    if isLit {
        context.setShadow(
            offset: .zero, blur: canvas * 0.05, color: CGColor(red: 0.45, green: 0.85, blue: 1, alpha: 0.9))
    }
    let fill =
        isBlack
        ? CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1) : CGColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1)
    context.setFillColor(isLit ? CGColor(red: 0.30, green: 0.80, blue: 1, alpha: 1) : fill)
    context.fillEllipse(in: rect)
    context.restoreGState()
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: isBlack ? 0.35 : 0.0))
    context.setLineWidth(canvas * 0.008)
    context.strokeEllipse(in: rect.insetBy(dx: canvas * 0.004, dy: canvas * 0.004))
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.icns>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in iconSizes {
    let suffix = size.scale == 1 ? "" : "@2x"
    let name = "icon_\(size.points)x\(size.points)\(suffix).png"
    try render(pixels: size.points * size.scale).write(to: iconset.appendingPathComponent(name))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
