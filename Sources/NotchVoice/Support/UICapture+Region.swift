//  UICapture+Region.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import AppKit

extension UICapture {
    /// The part of a window inside `screenRect`, with a margin, over a plain backdrop: one pill state
    /// without the rest of its transparent canvas.
    static func write(_ window: NSWindow, within screenRect: CGRect, to url: URL) {
        guard let rendered = render(window), let image = rendered.cgImage else { return }
        let scale = window.backingScaleFactor
        let margin: CGFloat = 24
        // Top-left window points; the margin is clamped where the pill meets the window edge.
        let wanted = CGRect(
            x: screenRect.minX - window.frame.minX - margin, y: window.frame.maxY - screenRect.maxY - margin,
            width: screenRect.width + margin * 2, height: screenRect.height + margin * 2
        )
        let visible = wanted.intersection(CGRect(origin: .zero, size: window.frame.size))
        let pixels = visible.applying(CGAffineTransform(scaleX: scale, y: scale))
        guard !visible.isEmpty, let cropped = image.cropping(to: pixels.integral), let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(wanted.width * scale), pixelsHigh: Int(wanted.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        bitmap.size = wanted.size
        let graphics = context.cgContext
        graphics.scaleBy(x: scale, y: scale)
        graphics.setFillColor(gray: 0.17, alpha: 1)
        graphics.fill(CGRect(origin: .zero, size: wanted.size))
        graphics.draw(cropped, in: CGRect(
            x: visible.minX - wanted.minX, y: wanted.maxY - visible.maxY, width: visible.width, height: visible.height
        ))
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
