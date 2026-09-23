// Generates Unlatch's app icon programmatically: a macOS "squircle" body with
// a background gradient and the SF Symbol `lock.open.fill` as the glyph,
// matching the motif in Sources/Unlatch/Views/IdleStepView.swift.
//
// This exists so a placeholder icon can ship now and a hand-designed one can
// replace it later without re-deriving the geometry. Everything that a
// redesign would touch -- the squircle proportions, the gradient angle, the
// glyph size, and each variant's colours -- is a named constant below.
//
// Usage:
//   swift Scripts/generate-icon.swift preview <variantName>... -o <outputDir>
//       Renders a light/dark contact sheet per named variant (or all
//       variants if none are named) at 1024, 128, 32 and 16 px, for judging
//       small-size legibility before committing to one.
//
//   swift Scripts/generate-icon.swift export <variantName> <resourcesDir>
//       Renders the chosen variant's 1024x1024 source PNG to
//       <resourcesDir>/AppIcon.png and the full iconutil-ready PNG set to
//       <resourcesDir>/AppIcon.iconset/.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Icon geometry

/// Everything a future redesign would need to change lives here. Swap these
/// constants (or replace the drawing functions below wholesale) and every
/// consumer -- preview and export -- picks it up.
enum IconMetrics {
    /// Full icon canvas, per Apple's macOS icon template.
    static let canvasSize: CGFloat = 1024
    /// The squircle body sits centered on the canvas, inset for the grid
    /// margin and drop shadow that macOS icons reserve.
    static let bodySize: CGFloat = 824
    static var inset: CGFloat { (canvasSize - bodySize) / 2 }

    /// Superellipse exponent for the squircle outline. 5 matches the
    /// continuous corner curve macOS uses for app icons; 2 would be a plain
    /// ellipse and very large values approach a rounded rectangle.
    static let superellipseExponent: CGFloat = 5.0

    /// Background gradient angle in degrees (NSGradient convention: 0 points
    /// along +x, counterclockwise). -45 gives a top-left-to-bottom-right
    /// diagonal, the common macOS app icon treatment.
    static let gradientAngle: CGFloat = -45

    /// Drop shadow cast by the squircle body onto the canvas beneath it.
    /// Below `shadowMinPixelSize`, the blur radius scaled to the canvas
    /// rounds down to only a couple of pixels, which no longer reads as a
    /// soft falloff -- it collapses into a thin dark outline traced right
    /// along the squircle's edge (most visible on a light backdrop). So the
    /// shadow is omitted entirely below that size rather than scaled down.
    /// 256px is the smallest iconset raster (icon_128x128@2x) that still
    /// renders it cleanly; the corresponding 1x asset (icon_128x128, 128px)
    /// intentionally goes without.
    static let shadowOpacity: CGFloat = 0.35
    static let shadowBlurFraction: CGFloat = 0.028
    static let shadowYOffsetFraction: CGFloat = 0.010
    static let shadowMinPixelSize = 256

    /// Glyph point size as a fraction of the body size, and its weight/scale.
    /// A heavier weight and the `.large` symbol scale keep the glyph's
    /// strokes from disappearing once the icon is downsized to 16-32pt.
    static let glyphSizeFraction: CGFloat = 0.46
    static let glyphWeight: NSFont.Weight = .semibold
    static let glyphScale: NSImage.SymbolScale = .large
    static let symbolName = "lock.open.fill"
}

/// One named colour treatment. Colours are the only thing that differs
/// between variants; geometry is shared.
struct IconVariant {
    let name: String
    let summary: String
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let glyphColor: NSColor
}

let variants: [IconVariant] = [
    IconVariant(
        name: "indigo",
        summary: "Deep blue to indigo gradient, white glyph",
        backgroundTop: NSColor(srgbRed: 0.20, green: 0.42, blue: 0.98, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.29, green: 0.16, blue: 0.72, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "unlocked-green",
        summary: "Warm green \"unlocked\" gradient, white glyph",
        backgroundTop: NSColor(srgbRed: 0.36, green: 0.78, blue: 0.47, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.09, green: 0.53, blue: 0.42, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "utility-light",
        summary: "Near-white background, indigo glyph, Apple-utility style",
        backgroundTop: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.87, green: 0.88, blue: 0.91, alpha: 1),
        glyphColor: NSColor(srgbRed: 0.29, green: 0.16, blue: 0.72, alpha: 1)
    ),
]

// MARK: - Drawing

private func sign(_ value: CGFloat) -> CGFloat {
    value < 0 ? -1 : (value > 0 ? 1 : 0)
}

/// A superellipse ("squircle") path, the shape macOS app icons are masked
/// to. `exponent` of 2 is an ellipse; higher values square the corners off.
func squirclePath(in rect: NSRect, exponent: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let cx = rect.midX
    let cy = rect.midY
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let x = cx + a * sign(cosT) * pow(abs(cosT), 2 / exponent)
        let y = cy + b * sign(sinT) * pow(abs(sinT), 2 / exponent)
        let point = NSPoint(x: x, y: y)
        if i == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }
    path.close()
    return path
}

/// Fills `color` clipped to `image`'s alpha channel -- the standard trick
/// for tinting a template/monochrome image.
func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
    let tinted = NSImage(size: image.size)
    tinted.lockFocus()
    color.set()
    let imageRect = NSRect(origin: .zero, size: image.size)
    imageRect.fill()
    image.draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1.0)
    tinted.unlockFocus()
    return tinted
}

/// Renders one variant at an exact pixel size, redrawing geometry and the
/// glyph at that scale rather than resampling a master image, so every size
/// -- including 16 px -- is crisp.
func renderIcon(_ variant: IconVariant, pixelSize: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixelSize)
    let scale = size / IconMetrics.canvasSize

    guard let rep = NSBitmapImageRep(
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
    ) else { fatalError("Could not allocate bitmap for \(variant.name) at \(pixelSize)px") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context for \(variant.name) at \(pixelSize)px")
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let cgContext = context.cgContext
    cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let bodyRect = NSRect(
        x: IconMetrics.inset * scale,
        y: IconMetrics.inset * scale,
        width: IconMetrics.bodySize * scale,
        height: IconMetrics.bodySize * scale
    )
    let squircle = squirclePath(in: bodyRect, exponent: IconMetrics.superellipseExponent)

    // Drop shadow: fill the squircle once with a shadow set, then fill it
    // again with the real gradient on top. Only the shadow outside the
    // shape's own silhouette remains visible. Skipped below
    // shadowMinPixelSize, where the blur no longer resolves as a soft edge
    // and instead shows up as a ring of grey halo pixels.
    if pixelSize >= IconMetrics.shadowMinPixelSize {
        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: -IconMetrics.canvasSize * IconMetrics.shadowYOffsetFraction * scale),
            blur: IconMetrics.canvasSize * IconMetrics.shadowBlurFraction * scale,
            color: NSColor.black.withAlphaComponent(IconMetrics.shadowOpacity).cgColor
        )
        NSColor.black.setFill()
        squircle.fill()
        cgContext.restoreGState()
    }

    // Background gradient, clipped to the squircle.
    cgContext.saveGState()
    squircle.addClip()
    let gradient = NSGradient(starting: variant.backgroundTop, ending: variant.backgroundBottom)
    gradient?.draw(in: bodyRect, angle: IconMetrics.gradientAngle)
    cgContext.restoreGState()

    // Glyph, centred on the body.
    let glyphPointSize = IconMetrics.bodySize * scale * IconMetrics.glyphSizeFraction
    let configuration = NSImage.SymbolConfiguration(
        pointSize: glyphPointSize,
        weight: IconMetrics.glyphWeight,
        scale: IconMetrics.glyphScale
    )
    guard
        let symbolBase = NSImage(systemSymbolName: IconMetrics.symbolName, accessibilityDescription: nil),
        let symbol = symbolBase.withSymbolConfiguration(configuration)
    else { fatalError("SF Symbol \(IconMetrics.symbolName) is unavailable on this system") }
    let glyph = tintedImage(symbol, color: variant.glyphColor)
    let glyphOrigin = NSPoint(
        x: bodyRect.midX - glyph.size.width / 2,
        y: bodyRect.midY - glyph.size.height / 2
    )
    glyph.draw(at: glyphOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

    return rep
}

func pngData(_ rep: NSBitmapImageRep) -> Data {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return data
}

// MARK: - Contact sheet (preview mode)

/// Sizes judged in the preview sheet: the master size plus the three sizes
/// where legibility is most at risk.
let previewSizes = [1024, 128, 32, 16]

/// Builds one PNG per variant showing every preview size on both a light
/// and a dark backdrop, so small-size legibility and both-appearance
/// contrast can be judged without opening each file.
func buildContactSheet(for variant: IconVariant) -> NSBitmapImageRep {
    let cell: CGFloat = 220
    let padding: CGFloat = 28
    let labelHeight: CGFloat = 22
    let rowLabelWidth: CGFloat = 60
    let titleHeight: CGFloat = 40

    let columns = previewSizes.count
    let rows = 2 // light, dark
    let sheetWidth = rowLabelWidth + padding + CGFloat(columns) * (cell + padding)
    let sheetHeight = titleHeight + CGFloat(rows) * (cell + labelHeight + padding) + padding

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(sheetWidth),
        pixelsHigh: Int(sheetHeight),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Could not allocate contact sheet for \(variant.name)") }
    rep.size = NSSize(width: sheetWidth, height: sheetHeight)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context for contact sheet")
    }
    NSGraphicsContext.current = context

    NSColor(white: 0.80, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

    let title = "\(variant.name) -- \(variant.summary)" as NSString
    title.draw(
        at: NSPoint(x: padding, y: sheetHeight - titleHeight + 10),
        withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black,
        ]
    )

    let backdrops: [(label: String, color: NSColor)] = [
        ("Light", NSColor(white: 0.96, alpha: 1)),
        ("Dark", NSColor(white: 0.10, alpha: 1)),
    ]

    for (rowIndex, backdrop) in backdrops.enumerated() {
        let rowTop = sheetHeight - titleHeight - CGFloat(rowIndex) * (cell + labelHeight + padding) - padding
        let rowBottom = rowTop - cell - labelHeight

        (backdrop.label as NSString).draw(
            at: NSPoint(x: padding, y: rowBottom + (cell + labelHeight) / 2),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
        )

        for (columnIndex, size) in previewSizes.enumerated() {
            let cellX = rowLabelWidth + padding + CGFloat(columnIndex) * (cell + padding)
            let cellRect = NSRect(x: cellX, y: rowBottom + labelHeight, width: cell, height: cell)

            backdrop.color.setFill()
            NSBezierPath(rect: cellRect).fill()

            let icon = renderIcon(variant, pixelSize: size)
            let iconImage = NSImage(size: NSSize(width: size, height: size))
            iconImage.addRepresentation(icon)

            // Every cell displays the icon at the same physical size so
            // sizes are easy to compare side by side. Sizes at or above
            // that display size are downsampled with high-quality
            // interpolation (how they'd actually look at that size). Sizes
            // below it -- the ones legibility is at risk for -- are
            // nearest-neighbour scaled up instead, so the actual pixel
            // grid, and any aliasing, is visible rather than smoothed away
            // by the preview itself.
            let displaySize = cell * 0.82
            let iconRect = NSRect(
                x: cellRect.midX - displaySize / 2,
                y: cellRect.midY - displaySize / 2,
                width: displaySize,
                height: displaySize
            )
            context.cgContext.saveGState()
            context.imageInterpolation = CGFloat(size) >= displaySize ? .high : .none
            iconImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.cgContext.restoreGState()

            let caption = "\(size)px" as NSString
            let captionSize = caption.size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
            caption.draw(
                at: NSPoint(x: cellRect.midX - captionSize.width / 2, y: rowBottom + (labelHeight - captionSize.height) / 2),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: backdrop.label == "Dark" ? NSColor.white : NSColor.black,
                ]
            )
        }
    }

    return rep
}

// MARK: - Export (final iconset)

/// `iconutil`'s expected filenames and the pixel size each one is rendered
/// at, per Apple's iconset convention.
let iconsetSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

func exportVariant(named name: String, to resourcesDir: URL) {
    guard let variant = variants.first(where: { $0.name == name }) else {
        fatalError("Unknown variant \"\(name)\". Known variants: \(variants.map(\.name).joined(separator: ", "))")
    }

    try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

    let masterRep = renderIcon(variant, pixelSize: 1024)
    let masterURL = resourcesDir.appendingPathComponent("AppIcon.png")
    try! pngData(masterRep).write(to: masterURL)
    print("  \(masterURL.path)")

    let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconsetDir)
    try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    for entry in iconsetSizes {
        let rep = renderIcon(variant, pixelSize: entry.pixels)
        let fileURL = iconsetDir.appendingPathComponent("\(entry.name).png")
        try! pngData(rep).write(to: fileURL)
        print("  \(fileURL.path)")
    }
}

// MARK: - CLI

func printUsageAndExit() -> Never {
    print("""
    Usage:
      swift Scripts/generate-icon.swift preview [variantName...] -o <outputDir>
      swift Scripts/generate-icon.swift export <variantName> <resourcesDir>

    Known variants: \(variants.map(\.name).joined(separator: ", "))
    """)
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let mode = arguments.first else { printUsageAndExit() }

switch mode {
case "preview":
    var rest = Array(arguments.dropFirst())
    guard let flagIndex = rest.firstIndex(of: "-o"), rest.indices.contains(flagIndex + 1) else {
        printUsageAndExit()
    }
    let outputDir = URL(fileURLWithPath: rest[flagIndex + 1])
    rest.removeSubrange(flagIndex...(flagIndex + 1))

    let requested = rest.isEmpty ? variants : rest.compactMap { name in variants.first { $0.name == name } }
    guard !requested.isEmpty else { printUsageAndExit() }

    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    for variant in requested {
        let sheet = buildContactSheet(for: variant)
        let sheetURL = outputDir.appendingPathComponent("icon-preview-\(variant.name).png")
        try! pngData(sheet).write(to: sheetURL)
        print("  \(sheetURL.path)")
    }

case "export":
    guard arguments.count == 3 else { printUsageAndExit() }
    let variantName = arguments[1]
    let resourcesDir = URL(fileURLWithPath: arguments[2])
    exportVariant(named: variantName, to: resourcesDir)

default:
    printUsageAndExit()
}
