// Generates Unlatch's app icon programmatically: a macOS "squircle" body with
// a background gradient and the SF Symbol `lock.open.fill` as the glyph,
// matching the motif in Sources/Unlatch/Views/IdleStepView.swift. The
// shipping colour is amber (issue #6); see `shippingVariantName` below.
//
// This exists so a placeholder icon can ship now and a hand-designed one can
// replace it later without re-deriving the geometry. Everything that a
// redesign would touch -- the squircle proportions, the gradient angle, the
// glyph size, and each variant's colours -- is a named constant below.
//
// To regenerate the shipping icon (e.g. after tweaking a constant):
//   swift Scripts/generate-icon.swift export Resources
// This overwrites Resources/AppIcon.png and Resources/AppIcon.iconset/.
// Follow with `iconutil -c icns Resources/AppIcon.iconset -o /tmp/check.icns`
// to sanity-check it converts; Scripts/package-app.sh does that step itself
// at package time, so the .icns is never committed.
//
// To change which colour ships, either point `shippingVariantName` at one
// of the existing entries in `variants` below, or add a new `IconVariant`
// (colours only -- geometry is shared) and point it there. No other code
// changes. `export` also takes an explicit variant name to render something
// other than the shipping one, without touching `shippingVariantName`:
//   swift Scripts/generate-icon.swift export <variantName> <resourcesDir>
//
// To look at variants before picking one:
//   swift Scripts/generate-icon.swift preview [variantName...] -o <outputDir>
//       A light/dark contact sheet per named variant (or every variant if
//       none are named) at 1024, 128, 32 and 16 px, for judging small-size
//       legibility.
//
//   swift Scripts/generate-icon.swift options -o <outputDir>
//       One wide sheet with every variant in `comparisonVariantNames` side
//       by side at 256 and 32 px, on a light row and a dark row, for
//       comparing a whole set of colour options at once.
//
//   swift Scripts/generate-icon.swift sizes <variantName>... -o <outputDir>
//       Standalone `<variant>-<size>.png` files (1024 down to 16px) through
//       the exact export pipeline, e.g. for dropping into an HTML page.

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

    /// Composition B (`.largeGlyphHighlight`): how much bigger the glyph is
    /// relative to the standard fraction above, and the soft top sheen
    /// applied over its upper portion. An earlier exploration round also
    /// tried a document-with-badge composition ("unlock a PDF" rather than
    /// just "unlock"); it was dropped for failing to hold up at 16/32px, so
    /// only this one composition alternative remains.
    static let largeGlyphSizeMultiplier: CGFloat = 1.30
    static let highlightOpacity: CGFloat = 0.30
    static let highlightHeightFraction: CGFloat = 0.55
}

/// The drawing treatments the generator can produce. Colour is the only
/// thing that differs between IconVariant entries sharing a composition;
/// the shapes themselves live in the render functions below.
enum IconComposition {
    /// The default, and what ships: squircle body, background gradient,
    /// centred glyph.
    case squircleGlyph
    /// The standard squircle and glyph, but the glyph is scaled up and
    /// gets a soft inner highlight across its top half. Kept as a second
    /// option because it measurably improves 32px legibility; not used by
    /// the shipping variant.
    case largeGlyphHighlight
}

/// One named colour treatment (optionally on the `largeGlyphHighlight`
/// composition). Colour is what differs between variants; the geometry is
/// shared, so adding a new option -- or recolouring the shipping one -- is
/// one more entry in `variants` below, not a code change.
struct IconVariant {
    let name: String
    let summary: String
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let glyphColor: NSColor
    let composition: IconComposition

    init(
        name: String,
        summary: String,
        backgroundTop: NSColor,
        backgroundBottom: NSColor,
        glyphColor: NSColor,
        composition: IconComposition = .squircleGlyph
    ) {
        self.name = name
        self.summary = summary
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
        self.glyphColor = glyphColor
        self.composition = composition
    }
}

/// The variant `export` uses when no name is given -- the maintainer's
/// pick from the issue #6 exploration round. To ship a different colour,
/// point this at another entry below; to recolour from scratch, add a new
/// `IconVariant` and point this at its `name`. Either way, no other code
/// changes.
let shippingVariantName = "amber"

let variants: [IconVariant] = [
    // Colour options from the issue #6 exploration round. `shippingVariantName`
    // above picks amber; the rest stay here so a future recolour, or a
    // side-by-side look via `options`/`preview`, is free.
    IconVariant(
        name: "amber",
        summary: "Warm orange to amber gradient, white glyph -- ships",
        backgroundTop: NSColor(srgbRed: 0.98, green: 0.60, blue: 0.16, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.95, green: 0.76, blue: 0.10, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "graphite",
        summary: "Dark charcoal to near-black, silver glyph (Terminal/Activity Monitor feel)",
        backgroundTop: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.23, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1),
        glyphColor: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1)
    ),
    IconVariant(
        name: "teal",
        summary: "Teal to cyan gradient, white glyph",
        backgroundTop: NSColor(srgbRed: 0.02, green: 0.55, blue: 0.56, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.16, green: 0.80, blue: 0.87, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "coral",
        summary: "Coral/soft red gradient (a PDF nod, not Adobe's red), white glyph",
        backgroundTop: NSColor(srgbRed: 0.98, green: 0.46, blue: 0.42, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.86, green: 0.24, blue: 0.34, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "plum",
        summary: "Purple to magenta gradient, white glyph",
        backgroundTop: NSColor(srgbRed: 0.46, green: 0.22, blue: 0.58, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.75, green: 0.20, blue: 0.55, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "slate-blue",
        summary: "Muted desaturated blue-grey, calmer than indigo, white glyph",
        backgroundTop: NSColor(srgbRed: 0.42, green: 0.49, blue: 0.60, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.28, green: 0.34, blue: 0.44, alpha: 1),
        glyphColor: .white
    ),
    IconVariant(
        name: "mint-on-dark",
        summary: "Dark background, mint-green glyph",
        backgroundTop: NSColor(srgbRed: 0.12, green: 0.14, blue: 0.15, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.04, green: 0.05, blue: 0.06, alpha: 1),
        glyphColor: NSColor(srgbRed: 0.38, green: 0.86, blue: 0.66, alpha: 1)
    ),
    IconVariant(
        name: "frosted",
        summary: "Very light silver \"glass\" background, dark graphite glyph (macOS 26 feel)",
        backgroundTop: NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1),
        glyphColor: NSColor(srgbRed: 0.22, green: 0.23, blue: 0.26, alpha: 1)
    ),

    // `.largeGlyphHighlight` composition: standard squircle, but a bigger
    // glyph with a soft inner highlight across its top half.
    IconVariant(
        name: "large-glyph-slate",
        summary: "Larger glyph + inner highlight, in slate-blue",
        backgroundTop: NSColor(srgbRed: 0.42, green: 0.49, blue: 0.60, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.28, green: 0.34, blue: 0.44, alpha: 1),
        glyphColor: .white,
        composition: .largeGlyphHighlight
    ),
    IconVariant(
        name: "large-glyph-graphite",
        summary: "Larger glyph + inner highlight, in graphite",
        backgroundTop: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.23, alpha: 1),
        backgroundBottom: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1),
        glyphColor: NSColor(srgbRed: 0.92, green: 0.93, blue: 0.95, alpha: 1),
        composition: .largeGlyphHighlight
    ),
]

/// The variants shown on the wide side-by-side comparison sheet (`options`
/// CLI mode), in display order.
let comparisonVariantNames = [
    "amber", "graphite", "teal", "coral", "plum", "slate-blue", "mint-on-dark", "frosted",
    "large-glyph-slate", "large-glyph-graphite",
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

/// Allocates a transparent square bitmap of `pixelSize` and makes it the
/// current graphics context, for the render functions below to draw into.
/// Callers must balance this with `NSGraphicsContext.restoreGraphicsState()`
/// (a `defer` right after calling it does the job).
func makeBitmapContext(pixelSize: Int, label: String) -> (rep: NSBitmapImageRep, context: NSGraphicsContext) {
    let size = CGFloat(pixelSize)
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
    ) else { fatalError("Could not allocate bitmap for \(label) at \(pixelSize)px") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context for \(label) at \(pixelSize)px")
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    return (rep, context)
}

/// Returns a glyph image for `symbolName`, tinted `color`, sized as
/// `pointSize` at the given weight/scale.
func makeGlyph(
    symbolName: String,
    pointSize: CGFloat,
    weight: NSFont.Weight,
    scale: NSImage.SymbolScale,
    color: NSColor
) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: scale)
    guard
        let symbolBase = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
        let symbol = symbolBase.withSymbolConfiguration(configuration)
    else { fatalError("SF Symbol \(symbolName) is unavailable on this system") }
    return tintedImage(symbol, color: color)
}

/// Draws the squircle body -- drop shadow (above `shadowMinPixelSize` only,
/// see IconMetrics) plus the background gradient clipped to the squircle.
func drawSquircleBackground(variant: IconVariant, bodyRect: NSRect, squircle: NSBezierPath, pixelSize: Int, scale: CGFloat) {
    let cgContext = NSGraphicsContext.current!.cgContext

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

    cgContext.saveGState()
    squircle.addClip()
    let gradient = NSGradient(starting: variant.backgroundTop, ending: variant.backgroundBottom)
    gradient?.draw(in: bodyRect, angle: IconMetrics.gradientAngle)
    cgContext.restoreGState()
}

/// Renders one variant at an exact pixel size, redrawing geometry and the
/// glyph at that scale rather than resampling a master image, so every size
/// -- including 16 px -- is crisp. Dispatches on `variant.composition`.
func renderIcon(_ variant: IconVariant, pixelSize: Int) -> NSBitmapImageRep {
    switch variant.composition {
    case .squircleGlyph:
        return renderSquircleGlyph(variant, pixelSize: pixelSize)
    case .largeGlyphHighlight:
        return renderSquircleGlyph(variant, pixelSize: pixelSize, largeWithHighlight: true)
    }
}

/// Squircle body, background gradient, centred glyph -- both compositions.
/// `largeWithHighlight` is `.largeGlyphHighlight`: the glyph is scaled up
/// and gets a soft top sheen.
func renderSquircleGlyph(_ variant: IconVariant, pixelSize: Int, largeWithHighlight: Bool = false) -> NSBitmapImageRep {
    let size = CGFloat(pixelSize)
    let scale = size / IconMetrics.canvasSize
    let (rep, context) = makeBitmapContext(pixelSize: pixelSize, label: variant.name)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let cgContext = context.cgContext

    let bodyRect = NSRect(
        x: IconMetrics.inset * scale,
        y: IconMetrics.inset * scale,
        width: IconMetrics.bodySize * scale,
        height: IconMetrics.bodySize * scale
    )
    let squircle = squirclePath(in: bodyRect, exponent: IconMetrics.superellipseExponent)
    drawSquircleBackground(variant: variant, bodyRect: bodyRect, squircle: squircle, pixelSize: pixelSize, scale: scale)

    let sizeFraction = largeWithHighlight
        ? IconMetrics.glyphSizeFraction * IconMetrics.largeGlyphSizeMultiplier
        : IconMetrics.glyphSizeFraction
    let glyphPointSize = IconMetrics.bodySize * scale * sizeFraction
    let glyph = makeGlyph(
        symbolName: IconMetrics.symbolName,
        pointSize: glyphPointSize,
        weight: IconMetrics.glyphWeight,
        scale: IconMetrics.glyphScale,
        color: variant.glyphColor
    )
    let glyphOrigin = NSPoint(
        x: bodyRect.midX - glyph.size.width / 2,
        y: bodyRect.midY - glyph.size.height / 2
    )
    glyph.draw(at: glyphOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

    if largeWithHighlight {
        // A soft white sheen over the glyph's top half -- clip to a band
        // above the glyph's vertical midpoint, then draw a lightened copy
        // of the same glyph at low opacity so only the strokes lighten.
        let highlight = makeGlyph(
            symbolName: IconMetrics.symbolName,
            pointSize: glyphPointSize,
            weight: IconMetrics.glyphWeight,
            scale: IconMetrics.glyphScale,
            color: .white
        )
        cgContext.saveGState()
        let bandHeight = glyph.size.height * IconMetrics.highlightHeightFraction
        let clipRect = NSRect(
            x: glyphOrigin.x,
            y: glyphOrigin.y + glyph.size.height - bandHeight,
            width: glyph.size.width,
            height: bandHeight
        )
        cgContext.clip(to: clipRect)
        highlight.draw(at: glyphOrigin, from: .zero, operation: .sourceOver, fraction: IconMetrics.highlightOpacity)
        cgContext.restoreGState()
    }

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

// MARK: - Comparison sheet (options mode)

/// The two sizes shown per variant on the comparison sheet: large enough to
/// read the composition and colour clearly, and the size where glyph
/// legibility is most at risk.
let comparisonSizes = [256, 32]

/// Builds one wide sheet with every variant in `comparisonVariantNames`
/// side by side, each showing 256px and 32px on a light row and a dark
/// row, labelled with its name, so a broad set of colour and composition
/// options can be judged against each other without opening a dozen
/// separate files.
func buildComparisonSheet() -> NSBitmapImageRep {
    let comparisonVariants = comparisonVariantNames.map { name -> IconVariant in
        guard let variant = variants.first(where: { $0.name == name }) else {
            fatalError("comparisonVariantNames references unknown variant \"\(name)\"")
        }
        return variant
    }

    let swatch: CGFloat = 96
    let swatchGap: CGFloat = 10
    let columnPadding: CGFloat = 20
    let columnWidth = swatch * 2 + swatchGap
    let rowLabelWidth: CGFloat = 60
    let captionHeight: CGFloat = 15
    let rowContentHeight = swatch + captionHeight
    let headerHeight: CGFloat = 30
    let titleHeight: CGFloat = 36
    let outerPadding: CGFloat = 20

    let sheetWidth = rowLabelWidth + outerPadding + CGFloat(comparisonVariants.count) * (columnWidth + columnPadding)
    let sheetHeight = titleHeight + headerHeight + 2 * rowContentHeight + outerPadding

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
    ) else { fatalError("Could not allocate comparison sheet") }
    rep.size = NSSize(width: sheetWidth, height: sheetHeight)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context for comparison sheet")
    }
    NSGraphicsContext.current = context

    NSColor(white: 0.80, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

    ("Icon options -- 256px and 32px, light and dark" as NSString).draw(
        at: NSPoint(x: outerPadding, y: sheetHeight - titleHeight + 8),
        withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black,
        ]
    )

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    paragraph.alignment = .center

    let backdrops: [(label: String, color: NSColor, textColor: NSColor)] = [
        ("Light", NSColor(white: 0.96, alpha: 1), .black),
        ("Dark", NSColor(white: 0.10, alpha: 1), .white),
    ]

    for (columnIndex, variant) in comparisonVariants.enumerated() {
        let columnX = rowLabelWidth + outerPadding + CGFloat(columnIndex) * (columnWidth + columnPadding)

        (variant.name as NSString).draw(
            with: NSRect(x: columnX, y: sheetHeight - titleHeight - headerHeight + 6, width: columnWidth, height: headerHeight),
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ]
        )

        for (rowIndex, backdrop) in backdrops.enumerated() {
            let rowTop = sheetHeight - titleHeight - headerHeight - CGFloat(rowIndex) * rowContentHeight
            let rowBottom = rowTop - rowContentHeight
            let rowRect = NSRect(x: columnX, y: rowBottom, width: columnWidth, height: rowContentHeight)

            backdrop.color.setFill()
            NSBezierPath(rect: rowRect).fill()

            if columnIndex == 0 {
                (backdrop.label as NSString).draw(
                    at: NSPoint(x: 6, y: rowBottom + rowContentHeight / 2 - 6),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: NSColor.black,
                    ]
                )
            }

            for (sizeIndex, pxSize) in comparisonSizes.enumerated() {
                let icon = renderIcon(variant, pixelSize: pxSize)
                let iconImage = NSImage(size: NSSize(width: pxSize, height: pxSize))
                iconImage.addRepresentation(icon)

                let swatchX = columnX + CGFloat(sizeIndex) * (swatch + swatchGap)
                let swatchRect = NSRect(x: swatchX, y: rowBottom + captionHeight, width: swatch, height: swatch)

                context.cgContext.saveGState()
                context.imageInterpolation = CGFloat(pxSize) >= swatch ? .high : .none
                iconImage.draw(in: swatchRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                context.cgContext.restoreGState()

                let caption = "\(pxSize)px" as NSString
                let captionSize = caption.size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)])
                caption.draw(
                    at: NSPoint(x: swatchRect.midX - captionSize.width / 2, y: rowBottom + (captionHeight - captionSize.height) / 2),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 9),
                        .foregroundColor: backdrop.textColor,
                    ]
                )
            }
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

/// Standalone PNG sizes for the `sizes` CLI mode -- the same rasters the
/// iconset ships (16 through 1024, including the intermediate @2x sizes),
/// but as individually named files rather than iconutil's naming scheme,
/// for dropping into something like an HTML comparison page.
let standaloneSizes = [1024, 256, 128, 64, 32, 16]

func printUsageAndExit() -> Never {
    print("""
    Usage:
      swift Scripts/generate-icon.swift export [variantName] <resourcesDir>
          Defaults to \"\(shippingVariantName)\" (shippingVariantName) if no
          variantName is given.
      swift Scripts/generate-icon.swift preview [variantName...] -o <outputDir>
      swift Scripts/generate-icon.swift options -o <outputDir>
      swift Scripts/generate-icon.swift sizes <variantName>... -o <outputDir>

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

case "options":
    var rest = Array(arguments.dropFirst())
    guard let flagIndex = rest.firstIndex(of: "-o"), rest.indices.contains(flagIndex + 1) else {
        printUsageAndExit()
    }
    let outputDir = URL(fileURLWithPath: rest[flagIndex + 1])
    rest.removeSubrange(flagIndex...(flagIndex + 1))

    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    let sheet = buildComparisonSheet()
    let sheetURL = outputDir.appendingPathComponent("icon-options.png")
    try! pngData(sheet).write(to: sheetURL)
    print("  \(sheetURL.path)")

case "sizes":
    var rest = Array(arguments.dropFirst())
    guard let flagIndex = rest.firstIndex(of: "-o"), rest.indices.contains(flagIndex + 1) else {
        printUsageAndExit()
    }
    let outputDir = URL(fileURLWithPath: rest[flagIndex + 1])
    rest.removeSubrange(flagIndex...(flagIndex + 1))

    let requested = rest.compactMap { name in variants.first { $0.name == name } }
    guard !requested.isEmpty else { printUsageAndExit() }

    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    for variant in requested {
        for pxSize in standaloneSizes {
            // Exactly the shipping render pipeline (renderIcon), so these
            // match the iconset pixel-for-pixel, shadow threshold included.
            let rep = renderIcon(variant, pixelSize: pxSize)
            let fileURL = outputDir.appendingPathComponent("\(variant.name)-\(pxSize).png")
            try! pngData(rep).write(to: fileURL)
            print("  \(fileURL.path)")
        }
    }

case "export":
    let variantName: String
    let resourcesDir: URL
    switch arguments.count {
    case 2:
        variantName = shippingVariantName
        resourcesDir = URL(fileURLWithPath: arguments[1])
    case 3:
        variantName = arguments[1]
        resourcesDir = URL(fileURLWithPath: arguments[2])
    default:
        printUsageAndExit()
    }
    exportVariant(named: variantName, to: resourcesDir)

default:
    printUsageAndExit()
}
