#!/usr/bin/env swift
// SPDX-License-Identifier: BUSL-1.1

import AppKit
import Foundation

// Package the selected artwork without redrawing or regenerating its mark.
// Explicit bitmap dimensions avoid Retina-dependent output sizes.
let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = project.appendingPathComponent("Resources/Branding/StudioUpkeepScan-master.png")
guard let master = NSImage(contentsOf: masterURL) else {
    fatalError("Missing MK Studio Upkeep Scan master artwork")
}
let iconSet = project.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func render(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let side = CGFloat(pixels)
    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    let canvas = NSRect(x: 0, y: 0, width: side, height: side)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)

    let tileRect = canvas.insetBy(dx: side * 0.045, dy: side * 0.045)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: side * 0.205, yRadius: side * 0.205)
    tile.addClip()
    NSColor(calibratedRed: 16 / 255, green: 17 / 255, blue: 19 / 255, alpha: 1).setFill()
    tile.fill()
    master.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

for (filename, pixels) in targets {
    try render(pixels: pixels).write(to: iconSet.appendingPathComponent(filename), options: .atomic)
}
try render(pixels: 1024).write(to: project.appendingPathComponent("Resources/AppIcon.png"), options: .atomic)
print("Generated 10 exact-size app-icon renditions and Resources/AppIcon.png from the approved Scan artwork.")
