import Foundation
import PDFKit

/// How a PDF is protected, which determines what `unlock` has to do with it.
public enum Classification: Equatable, Sendable {
    /// No encryption dictionary at all — nothing to strip.
    case notEncrypted
    /// Encrypted with a user password: the file cannot be opened without it.
    case userLocked
    /// Encrypted with only an owner password. It opens with an empty user
    /// password, so viewers show it freely while still advertising
    /// restrictions on printing, copying, and editing.
    case ownerRestricted
    /// Not a PDF, or damaged badly enough that PDFKit cannot parse it.
    case unreadable
}

public func classify(_ source: URL) -> Classification {
    guard let doc = PDFDocument(url: source) else { return .unreadable }

    // isLocked means PDFKit could not open the content with an empty user
    // password, so a user password is set. An encrypted-but-unlocked document
    // is the owner-password case.
    if doc.isLocked { return .userLocked }
    if doc.isEncrypted { return .ownerRestricted }
    return .notEncrypted
}
