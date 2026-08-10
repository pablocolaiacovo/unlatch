# Unlatch

A small Swift package for inspecting how a PDF is protected and writing a decrypted copy of it, built on PDFKit.

`UnlatchCore` does two things:

- **`classify(_:)`** — reports how a file is protected, separating the case where a PDF cannot be opened at all from the case where it opens freely but declares restrictions.
- **`unlock(_:password:destination:)`** — writes a copy with the encryption removed.

## Requirements

- macOS 11 or later (the package depends on `PDFKit`, so Apple platforms only — it will not build on Linux)
- Swift 6.3 or later, built in Swift 6 language mode

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pablocolaiacovo/unlatch.git", branch: "main")
]
```

Then add `UnlatchCore` to your target's dependencies.

## Usage

### Classifying

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

### Unlocking

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

## Implementation notes

Two things about this problem are easy to get wrong, and both are why the code looks the way it does.

**`PDFDocument.write` can carry the encryption through.** Calling `unlock(withPassword:)` grants access in memory only; writing that document back out can reproduce the source's encryption dictionary, yielding an output file that is still encrypted. In testing this depended on which tool authored the input — files originally written by qpdf came out clean, files written by PDFKit stayed encrypted. Neither `write(to:withOptions:)` with empty passwords nor `dataRepresentation()` avoided it. Copying the pages into a fresh `PDFDocument` is what reliably drops the encryption, so that is what `unlock` does.

**Rebuilding costs fidelity, and the bill is not obvious.** Page copies bring their own annotations, so form field values and links survive. The outline does not: bookmarks live on the document rather than on any page, and a page-by-page rebuild silently discards them. `unlock` therefore remaps the outline onto the new pages explicitly. Anything else stored at the document level — a document-wide `/AcroForm` dictionary with JavaScript or a calculation order, for instance — is not covered by the current tests and should be assumed lost until proven otherwise.

## Tests

```sh
swift test
```

The fixtures are committed, so running the tests needs nothing beyond a Swift toolchain.

### The fixture corpus

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

## License

MIT — see [LICENSE](LICENSE).
