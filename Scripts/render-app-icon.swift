#!/usr/bin/env swift

import AppKit
import Foundation

enum RenderError: Error, LocalizedError {
    case usage
    case unreadableSource(URL)
    case bitmapCreationFailed
    case pngEncodingFailed
    case transparencyLost

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: render-app-icon.swift <source.svg> <destination.png>"
        case let .unreadableSource(url):
            "Could not load SVG source at \(url.path)."
        case .bitmapCreationFailed:
            "Could not create the 1024 × 1024 icon bitmap."
        case .pngEncodingFailed:
            "Could not encode the rendered app icon as PNG."
        case .transparencyLost:
            "The rendered icon lost its transparent canvas padding."
        }
    }
}

func renderAppIcon() throws {
    guard CommandLine.arguments.count == 3 else {
        throw RenderError.usage
    }

    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let sourceImage = NSImage(contentsOf: sourceURL) else {
        throw RenderError.unreadableSource(sourceURL)
    }

    let pixelSize = 1_024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw RenderError.bitmapCreationFailed
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw RenderError.bitmapCreationFailed
    }
    NSGraphicsContext.current = graphicsContext
    graphicsContext.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)
    sourceImage.draw(
        in: canvas,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    graphicsContext.flushGraphics()

    guard (bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01 else {
        throw RenderError.transparencyLost
    }
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw RenderError.pngEncodingFailed
    }
    try png.write(to: destinationURL, options: .atomic)
}

do {
    try renderAppIcon()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
