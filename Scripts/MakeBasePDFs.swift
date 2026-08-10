// Authors the two fixtures qpdf cannot produce: a neutral unencrypted base
// document, and a PDF carrying a filled-in AcroForm text field.
// Driven by Scripts/generate-fixtures.sh — see there for the full corpus.

import Foundation
import PDFKit
import CoreGraphics
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func basePDFData(pages: Int) -> Data {
    let data = NSMutableData()
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
    for i in 0..<pages {
        ctx.beginPDFPage(nil)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        ("Page \(i + 1)" as NSString).draw(
            at: NSPoint(x: 72, y: 640),
            withAttributes: [.font: NSFont.systemFont(ofSize: 36)]
        )
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return data as Data
}

// plain.pdf — 3 pages, no encryption. Base for every qpdf-derived fixture.
let plain = basePDFData(pages: 3)
try plain.write(to: outDir.appendingPathComponent("plain.pdf"))
print("  plain.pdf (3 pages)")

// PDFKit-authored counterparts to the qpdf encrypted fixtures. PDFKit and qpdf
// write encryption differently, and an implementation that strips only qpdf's
// passes a qpdf-only corpus while silently leaving these encrypted. Both
// producers are represented so that failure mode stays visible.
let pdfkitUserLocked = PDFDocument(data: plain)!
guard pdfkitUserLocked.write(
    to: outDir.appendingPathComponent("pdfkit-user-locked.pdf"),
    withOptions: [.userPasswordOption: "hunter2", .ownerPasswordOption: "ownersecret"]
) else { fatalError("failed to write pdfkit-user-locked.pdf") }
print("  pdfkit-user-locked.pdf (user password: hunter2)")

let pdfkitOwnerRestricted = PDFDocument(data: plain)!
guard pdfkitOwnerRestricted.write(
    to: outDir.appendingPathComponent("pdfkit-owner-restricted.pdf"),
    withOptions: [.ownerPasswordOption: "ownersecret"]
) else { fatalError("failed to write pdfkit-owner-restricted.pdf") }
print("  pdfkit-owner-restricted.pdf (owner password only)")

// outlined.pdf — carries bookmarks, which live on the document rather than on
// any page and so are the first thing a page-by-page rebuild loses.
let outlined = PDFDocument(data: plain)!
let root = PDFOutline()
for index in 0..<outlined.pageCount {
    let entry = PDFOutline()
    entry.label = "Chapter \(index + 1)"
    entry.destination = PDFDestination(page: outlined.page(at: index)!, at: .zero)
    root.insertChild(entry, at: index)
}
outlined.outlineRoot = root
guard outlined.write(to: outDir.appendingPathComponent("outlined.pdf")) else {
    fatalError("failed to write outlined.pdf")
}
print("  outlined.pdf (3 bookmarks)")

// filled-form.pdf — a text field with a value someone typed in, to catch
// re-serialization silently dropping AcroForm content.
let formDoc = PDFDocument(data: basePDFData(pages: 1))!
let page = formDoc.page(at: 0)!
let field = PDFAnnotation(bounds: CGRect(x: 72, y: 500, width: 300, height: 30),
                          forType: .widget, withProperties: nil)
field.widgetFieldType = .text
field.fieldName = "applicantName"
field.widgetStringValue = "Pablo"
field.backgroundColor = .white
page.addAnnotation(field)
guard formDoc.write(to: outDir.appendingPathComponent("filled-form.pdf")) else {
    fatalError("failed to write filled-form.pdf")
}
print("  filled-form.pdf (applicantName = Pablo)")
