import Foundation
import PDFKit

public enum UnlockError: Error { case wrongPassword, unreadable, writeFailed }

public func unlock(_ source: URL, password: String?, destination: URL) throws {
    guard let doc = PDFDocument(url: source) else { throw UnlockError.unreadable }

    if doc.isLocked {
        guard let password, doc.unlock(withPassword: password) else {
            throw UnlockError.wrongPassword
        }
    }

    // Unlocking a document only grants access in memory: PDFDocument.write
    // carries the source's encryption dictionary through to the output, so
    // writing the unlocked document still produces an encrypted file. Whether
    // that happens depends on who authored the source -- files written by qpdf
    // come out clean, files written by PDFKit stay encrypted -- so it fails
    // silently on a subset of inputs. Copying the pages into a fresh document
    // is what actually drops the encryption, on every producer tested.
    let rebuilt = PDFDocument()
    for index in 0..<doc.pageCount {
        guard let page = doc.page(at: index)?.copy() as? PDFPage else {
            throw UnlockError.writeFailed
        }
        rebuilt.insert(page, at: rebuilt.pageCount)
    }
    rebuilt.documentAttributes = doc.documentAttributes

    // Page copies carry their own annotations, but the outline lives on the
    // document and is lost with it, so bookmarks need remapping onto the new
    // pages by hand.
    if let outline = doc.outlineRoot {
        rebuilt.outlineRoot = copyOutline(outline, from: doc, to: rebuilt)
    }

    // Write to a temp file first, then swap it into place atomically.
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")

    guard rebuilt.write(to: temp) else {
        try? FileManager.default.removeItem(at: temp)
        throw UnlockError.writeFailed
    }

    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
}

/// Recreates an outline subtree against `target`'s pages. A destination whose
/// page no longer resolves is dropped rather than left dangling; the entry
/// keeps its label and children so the structure stays intact.
private func copyOutline(
    _ node: PDFOutline, from source: PDFDocument, to target: PDFDocument
) -> PDFOutline {
    let copy = PDFOutline()
    copy.label = node.label

    if let destination = node.destination, let page = destination.page {
        let index = source.index(for: page)
        if index != NSNotFound, let newPage = target.page(at: index) {
            copy.destination = PDFDestination(page: newPage, at: destination.point)
        }
    }

    for childIndex in 0..<node.numberOfChildren {
        guard let child = node.child(at: childIndex) else { continue }
        copy.insertChild(copyOutline(child, from: source, to: target),
                         at: copy.numberOfChildren)
    }
    return copy
}
