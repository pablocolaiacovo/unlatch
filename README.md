# Unlatch

Unlatch is a macOS menu bar app for inspecting how a PDF is protected and saving a decrypted copy.
Click the lock icon, choose one or more PDFs, and it tells you which ones need a password, which
are only owner-restricted (so they open freely but PDFKit and other readers honor a printing or
copying lock), and which are unreadable — then writes unlocked copies wherever you choose.

The app is built on **`UnlatchCore`**, a small Swift package that does the underlying work and can
also be used on its own as a library. See [Using UnlatchCore as a library](#using-unlatchcore-as-a-library)
below.

## Install

1. Download `Unlatch.zip` from the [Releases page](https://github.com/pablocolaiacovo/unlatch/releases).
2. Unzip it and drag `Unlatch.app` to `/Applications`.
3. Click the lock icon that appears in the menu bar.

Requires macOS 14 or later.

### First launch

Unlatch v1.0 is **ad-hoc signed, not notarized by Apple** — it's a free, single-maintainer project
without a paid Apple Developer membership. Because of that, every copy downloaded from a browser is
quarantined, and macOS Gatekeeper blocks the very first launch. This is expected, not a sign of a
broken or malicious download, and it only needs to be dealt with once per install.

The fastest way past it, in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Unlatch.app
```

Then open the app normally. This works on every supported version of macOS.

If you'd rather not use Terminal:

1. Double-click Unlatch (or launch it from Spotlight). macOS shows a dialog titled **"Unlatch" Not
   Opened**, saying *Apple could not verify "Unlatch" is free of malware that may harm your Mac or
   compromise your privacy.* There is no Open button on this dialog — only **Move to Trash** and
   **Done**. Click **Done**. **Do not click "Move to Trash"** — it's the default, highlighted button,
   but it deletes the app instead of dismissing the warning.
2. Open **System Settings > Privacy & Security**, scroll to the Security section, where it now says
   Unlatch **was blocked to protect your Mac**, and click **Open Anyway**.
3. Confirm in the dialog that appears. You only need to do this once.

**Right-click (Control-click) > Open no longer bypasses Gatekeeper.** That trick still works on
macOS 14, but Apple removed it starting with macOS 15 Sequoia — use one of the two steps above
instead.

On some macOS versions, this same Gatekeeper block can instead say Unlatch **"is damaged and can't
be opened."** That's not a corrupt download — the `xattr` command above resolves it the same way.

## Using the app

Click the lock icon in the menu bar to open the popover, then choose PDFs via the file picker.
Unlatch classifies each file — not encrypted, password protected, owner-restricted, or unreadable —
prompts for a password only where one is actually needed, and lets you pick a destination for the
unlocked copies.

## Building from source

You don't need an Apple Developer account to build or run Unlatch locally.

```sh
swift build
swift run Unlatch
```

To produce a standalone, ad-hoc signed `Unlatch.app` you can drag into `/Applications` or hand to
someone else, use `Scripts/package-app.sh`. A locally built app isn't quarantined, so it launches
without the first-launch steps above.

> `Scripts/package-app.sh` is being added in [#7](https://github.com/pablocolaiacovo/unlatch/issues/7);
> once it lands, run it from the repository root and see its `--help` output for options.

## Using UnlatchCore as a library

`UnlatchCore` does two things:

- **`classify(_:)`** — reports how a file is protected, separating the case where a PDF cannot be opened at all from the case where it opens freely but declares restrictions.
- **`unlock(_:password:destination:)`** — writes a copy with the encryption removed.

### Requirements

- macOS 14 or later — the menu bar app's `@Observable` and `NSApp.activate(ignoringOtherApps:)` need it, and `UnlatchCore` declares the same platform floor (Apple platforms only; it will not build on Linux).
- Swift 6.3 or later, built in Swift 6 language mode

### Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pablocolaiacovo/unlatch.git", branch: "main")
]
```

Then add `UnlatchCore` to your target's dependencies.

### Usage

#### Classifying

```swift
import UnlatchCore

switch classify(url) {
case .notEncrypted:    print("nothing to do")
case .userLocked:      print("needs a password to open")
case .ownerRestricted: print("opens freely, but printing/copying are restricted")
case .unreadable:      print("not a PDF, or damaged")
}
```

The four cases map to PDFKit as follows:

| Case | Condition | What it means |
| --- | --- | --- |
| `.unreadable` | `PDFDocument(url:)` returns `nil` | Not a PDF, or damaged past parsing |
| `.userLocked` | `isLocked` | A user password is set; the content cannot be read without it |
| `.ownerRestricted` | `isEncrypted && !isLocked` | Only an owner password is set — viewers open it freely while still advertising restrictions |
| `.notEncrypted` | neither | No encryption dictionary |

The middle two are the distinction worth having. An owner-restricted file looks unprotected to a reader and is the case a naive implementation quietly does nothing about.

#### Unlocking

```swift
import UnlatchCore

do {
    try unlock(source, password: "hunter2", destination: output)
} catch UnlockError.wrongPassword {
    // password was missing or incorrect
} catch UnlockError.unreadable {
    // not a PDF, or damaged
} catch UnlockError.writeFailed {
    // could not serialize the result
}
```

Pass `password: nil` for owner-restricted files — they need no password to open, only re-serializing. The output is written to a temporary file and swapped into place, so `destination` is never left half-written. It does not need to exist beforehand, though its parent directory does.

### Implementation notes

Two things about this problem are easy to get wrong, and both are why the code looks the way it does.

**`PDFDocument.write` can carry the encryption through.** Calling `unlock(withPassword:)` grants access in memory only; writing that document back out can reproduce the source's encryption dictionary, yielding an output file that is still encrypted. In testing this depended on which tool authored the input — files originally written by qpdf came out clean, files written by PDFKit stayed encrypted. Neither `write(to:withOptions:)` with empty passwords nor `dataRepresentation()` avoided it. Copying the pages into a fresh `PDFDocument` is what reliably drops the encryption, so that is what `unlock` does.

**Rebuilding costs fidelity, and the bill is not obvious.** Page copies bring their own annotations, so form field values and links survive. The outline does not: bookmarks live on the document rather than on any page, and a page-by-page rebuild silently discards them. `unlock` therefore remaps the outline onto the new pages explicitly. Anything else stored at the document level — a document-wide `/AcroForm` dictionary with JavaScript or a calculation order, for instance — is not covered by the current tests and should be assumed lost until proven otherwise.

### Tests

```sh
swift test
```

The fixtures are committed, so running the tests needs nothing beyond a Swift toolchain.

#### The fixture corpus

The encrypted fixtures come from **two different producers on purpose**. Encrypting the test files with PDFKit would only test PDFKit against itself, and — per the note above — an implementation that strips qpdf's encryption but not PDFKit's passes a qpdf-only corpus while failing on real input. Both are represented, and `bothProducersClassifyAndUnlockAlike` holds them to identical expectations.

| Fixture | Producer | Purpose |
| --- | --- | --- |
| `plain.pdf` | CoreGraphics | Unencrypted base for everything below |
| `user-locked.pdf` | qpdf | AES-256, user password `hunter2` |
| `owner-restricted.pdf` | qpdf | AES-256, owner password only, printing and modification denied |
| `pdfkit-user-locked.pdf` | PDFKit | Same protection, different producer |
| `pdfkit-owner-restricted.pdf` | PDFKit | Same protection, different producer |
| `truncated.pdf` | `head -c` | Valid header, body cut off — exercises `.unreadable` |
| `filled-form.pdf` | PDFKit | AcroForm text field with a typed-in value |
| `outlined.pdf` | PDFKit | Three bookmarks, to catch outline loss |

To regenerate them:

```sh
brew install qpdf
./Scripts/generate-fixtures.sh
```

CoreGraphics and PDFKit author the base documents; qpdf applies all the encryption.

## Contributing

See [RELEASING.md](RELEASING.md) for how work lands on `main`, how versions are decided, and how a
release is cut.

## License

MIT — see [LICENSE](LICENSE).
