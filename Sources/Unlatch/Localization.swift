import Foundation

// Localization plumbing (Design/spanish-localization.md §2.2). Every user-facing string in this
// target is a `LocalizedStringResource` created with `bundle: .unlatch`, or built by `verbatim(_:)`.

extension LocalizedStringResource.BundleDescription {
    /// The app's resource bundle (`UnlatchCore_Unlatch.bundle`), which holds the compiled
    /// Localizable.xcstrings. Every LocalizedStringResource in this target passes
    /// `bundle: .unlatch`; the default `.main` finds no strings.
    static var unlatch: Self { .atURL(Bundle.module.bundleURL) }
}

/// Text shown exactly as given: file names, paths, the app name. Resolves through the
/// catalog's "%@" entry, which is marked Don't Translate, so nothing is ever looked up for
/// the text itself. Lets functions that sometimes return a path and sometimes a sentence
/// return one type.
func verbatim(_ text: String) -> LocalizedStringResource {
    LocalizedStringResource(
        "\(text)", bundle: .unlatch,
        comment: "A file name or path shown as is. Do not translate.")
}

/// Static labels for views and AppKit, one `LocalizedStringResource` each, so translator
/// comments live in one place. Empty until the views are converted (task T2); the strings that
/// `Logic.swift` returns carry their own comments there.
enum Strings {}
