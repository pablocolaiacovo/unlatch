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
/// comments live in one place. Each is a literal initializer call, not a wrapper, because the
/// compiler extracts catalog keys only from the real initializers. The strings that
/// `Logic.swift` returns carry their own comments there. Add an entry here, run
/// `Scripts/sync-strings.sh`, and translate the new catalog entry.
enum Strings {
    // MARK: Buttons

    static let cancel = LocalizedStringResource(
        "Cancel", bundle: .unlatch,
        comment: "Button: abandon this batch and return to the start (password and destination steps).")
    static let unlock = LocalizedStringResource(
        "Unlock", bundle: .unlatch,
        comment: "Button on the password step: try the password and unlock the PDFs.")
    static let save = LocalizedStringResource(
        "Save", bundle: .unlatch,
        comment: "Button on the destination step: write the unlocked copies.")
    static let showInFinder = LocalizedStringResource(
        "Show in Finder", bundle: .unlatch,
        comment: "Button on the done step: reveal the saved files in Finder.")
    static let done = LocalizedStringResource(
        "Done", bundle: .unlatch,
        comment: "Button on the done step: close the summary and return to the start.")
    static let choosePDFs = LocalizedStringResource(
        "Choose PDFs…", bundle: .unlatch,
        comment: "Idle step: the big button that opens the file picker.")

    // MARK: Idle and working steps

    static let idleCaption = LocalizedStringResource(
        "Removes the open password so the file opens without one. Nothing leaves your Mac.",
        bundle: .unlatch,
        comment: "Idle step: privacy caption under the Choose PDFs button.")
    static let unlocking = LocalizedStringResource(
        "Unlocking…", bundle: .unlatch,
        comment: "Shown with a spinner while the passwords are being checked.")

    // MARK: Password step

    static let show = LocalizedStringResource(
        "Show", bundle: .unlatch,
        comment: "Password step: small button that reveals the typed password. Same length as Hide.")
    static let hide = LocalizedStringResource(
        "Hide", bundle: .unlatch,
        comment: "Password step: small button that masks the typed password again.")
    static let password = LocalizedStringResource(
        "Password", bundle: .unlatch,
        comment: "Password step: placeholder and accessibility label of the password field.")
    static let passwordDidntWork = LocalizedStringResource(
        "That password didn’t work. Try again.", bundle: .unlatch,
        comment: "Password step: inline error after none of the PDFs opened with the password.")

    // MARK: Popover footer and menu

    static let openAtLogin = LocalizedStringResource(
        "Open at Login", bundle: .unlatch,
        comment: "Ellipsis menu: checkable item that makes Unlatch start when the user logs in.")
    static let more = LocalizedStringResource(
        "More", bundle: .unlatch,
        comment: "Help text and accessibility label of the ellipsis menu button in the footer.")
    static let updateAvailable = LocalizedStringResource(
        "Update Available", bundle: .unlatch,
        comment: "Footer button, shown only when a new version exists, and its accessibility label.")
    static let seeAvailableUpdate = LocalizedStringResource(
        "See the available update", bundle: .unlatch,
        comment: "Help text of the footer's Update Available button.")
    static let quit = LocalizedStringResource(
        "Quit", bundle: .unlatch,
        comment: "Footer button that quits the app.")
    static let quitUnlatch = LocalizedStringResource(
        "Quit Unlatch", bundle: .unlatch,
        comment: "Help text and accessibility label of the footer's Quit button, and the title of the main menu's Quit item. Keep the app name as is.")

    // MARK: AppKit: folder picker and main menu

    static let chooseFolderPrompt = LocalizedStringResource(
        "Choose", bundle: .unlatch,
        comment: "Confirm button of the folder picker opened by Choose folder…")
    static let editMenu = LocalizedStringResource(
        "Edit", bundle: .unlatch,
        comment: "Title of the Edit menu in the hidden main menu. Never shown, but reachable through Accessibility.")
    static let undo = LocalizedStringResource(
        "Undo", bundle: .unlatch, comment: "Edit menu item (hidden main menu).")
    static let redo = LocalizedStringResource(
        "Redo", bundle: .unlatch, comment: "Edit menu item (hidden main menu).")
    static let cut = LocalizedStringResource(
        "Cut", bundle: .unlatch, comment: "Edit menu item (hidden main menu).")
    static let copy = LocalizedStringResource(
        "Copy", bundle: .unlatch, comment: "Edit menu item (hidden main menu).")
    static let paste = LocalizedStringResource(
        "Paste", bundle: .unlatch, comment: "Edit menu item (hidden main menu).")
    static let selectAll = LocalizedStringResource(
        "Select All", bundle: .unlatch, comment: "Edit menu item (hidden main menu).")

    // MARK: Finder

    static let finderCouldntReadFiles = LocalizedStringResource(
        "Unlatch couldn't read the selected files.", bundle: .unlatch,
        comment: "Error text macOS shows when the Unlock with Unlatch Services entry was used but the files could not be read. Keep the app name as is.")
}
