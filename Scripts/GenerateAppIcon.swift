#!/usr/bin/env swift

import AppKit
import Foundation

// Icon sizes for macOS
let sizes: [(size: Int, scale: Int, filename: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

func generateIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let scale = CGFloat(size) / 512.0

    // Background - dark gradient
    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).cgColor,
            NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!

    // Rounded rectangle background
    let cornerRadius = 100.0 * scale
    let backgroundPath = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: 0, y: 0), options: [])
    context.restoreGState()

    // Subtle border
    context.setStrokeColor(NSColor(white: 0.3, alpha: 0.5).cgColor)
    context.setLineWidth(2 * scale)
    context.addPath(backgroundPath)
    context.strokePath()

    // Draw waveform
    let waveformColor = NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0) // Accent blue
    let waveformGlow = NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 0.6)

    let centerY = CGFloat(size) / 2.0
    let waveHeight = CGFloat(size) * 0.35
    let margin = CGFloat(size) * 0.15
    let waveWidth = CGFloat(size) - margin * 2

    // Create waveform path
    let waveformPath = CGMutablePath()
    let segments = 64

    for i in 0...segments {
        let x = margin + (CGFloat(i) / CGFloat(segments)) * waveWidth
        let t = CGFloat(i) / CGFloat(segments)

        // Create an audio waveform shape - combination of frequencies
        let envelope = sin(t * .pi) // Envelope shape
        let wave1 = sin(t * .pi * 8) * 0.6
        let wave2 = sin(t * .pi * 16) * 0.25
        let wave3 = sin(t * .pi * 4) * 0.15

        let amplitude = envelope * (wave1 + wave2 + wave3)
        let y = centerY + amplitude * waveHeight

        if i == 0 {
            waveformPath.move(to: CGPoint(x: x, y: y))
        } else {
            waveformPath.addLine(to: CGPoint(x: x, y: y))
        }
    }

    // Draw glow
    context.saveGState()
    context.setShadow(offset: .zero, blur: 20 * scale, color: waveformGlow.cgColor)
    context.setStrokeColor(waveformColor.cgColor)
    context.setLineWidth(6 * scale)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(waveformPath)
    context.strokePath()
    context.restoreGState()

    // Draw main waveform
    context.setStrokeColor(waveformColor.cgColor)
    context.setLineWidth(4 * scale)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(waveformPath)
    context.strokePath()

    // Draw highlight on top
    let highlightColor = NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.8)
    context.setStrokeColor(highlightColor.cgColor)
    context.setLineWidth(2 * scale)
    context.addPath(waveformPath)
    context.strokePath()

    // Add small EQ bars at the bottom
    let barCount = 7
    let barWidth = CGFloat(size) * 0.04
    let barSpacing = CGFloat(size) * 0.06
    let totalBarWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    let barStartX = (CGFloat(size) - totalBarWidth) / 2
    let barBaseY = CGFloat(size) * 0.82
    let maxBarHeight = CGFloat(size) * 0.12

    let barHeights: [CGFloat] = [0.4, 0.7, 0.9, 1.0, 0.8, 0.5, 0.3]

    for i in 0..<barCount {
        let x = barStartX + CGFloat(i) * (barWidth + barSpacing)
        let barHeight = maxBarHeight * barHeights[i]
        let barRect = CGRect(x: x, y: barBaseY - barHeight, width: barWidth, height: barHeight)

        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)

        // Bar gradient
        context.saveGState()
        context.addPath(barPath)
        context.clip()

        let barGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.9).cgColor,
                NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 0.6).cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        )!

        context.drawLinearGradient(barGradient, start: CGPoint(x: x, y: barBaseY - barHeight), end: CGPoint(x: x, y: barBaseY), options: [])
        context.restoreGState()
    }

    image.unlockFocus()
    return image
}

func saveIcon(_ image: NSImage, to url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }

    do {
        try pngData.write(to: url)
        print("Saved: \(url.lastPathComponent)")
    } catch {
        print("Failed to save \(url.lastPathComponent): \(error)")
    }
}

// Main
let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

for (size, scale, filename) in sizes {
    let pixelSize = size * scale
    let icon = generateIcon(size: pixelSize)
    let outputURL = outputDir.appendingPathComponent(filename)
    saveIcon(icon, to: outputURL)
}

print("Done! Generated \(sizes.count) icon sizes.")
