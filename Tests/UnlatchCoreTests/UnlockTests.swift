import Testing
import PDFKit
@testable import UnlatchCore

func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: name, withExtension: "pdf",
                      subdirectory: "Fixtures")!
}

@Test func classifiesAllFourBuckets() {
    #expect(classify(fixture("plain")) == .notEncrypted)
    #expect(classify(fixture("user-locked")) == .userLocked)
    #expect(classify(fixture("owner-restricted")) == .ownerRestricted)
    #expect(classify(fixture("truncated")) == .unreadable)
}

// The core promise: output is actually not encrypted anymore.
@Test func outputIsNotEncrypted() throws {
    let out = tempURL()
    try unlock(fixture("user-locked"), password: "hunter2", destination: out)
    let result = PDFDocument(url: out)!
    #expect(result.isEncrypted == false)
}

// The case a naive implementation silently no-ops on.
@Test func ownerRestrictedIsRewritten() throws {
    let out = tempURL()
    try unlock(fixture("owner-restricted"), password: nil, destination: out)
    #expect(PDFDocument(url: out)!.isEncrypted == false)
}

// Round-trip fidelity: does re-serializing lose pages?
@Test func pageCountSurvives() throws {
    let source = fixture("user-locked")
    let before = PDFDocument(url: source)!
    before.unlock(withPassword: "hunter2")
    let out = tempURL()
    try unlock(source, password: "hunter2", destination: out)
    #expect(PDFDocument(url: out)!.pageCount == before.pageCount)
}

// Round-trip fidelity: does it wipe what someone typed into the form?
@Test func formValuesSurvive() throws {
    let out = tempURL()
    try unlock(fixture("filled-form"), password: nil, destination: out)
    let values = PDFDocument(url: out)!.page(at: 0)!.annotations
        .compactMap(\.widgetStringValue)
    #expect(values.contains("Pablo"))
}

@Test func wrongPasswordThrows() {
    #expect(throws: UnlockError.wrongPassword) {
        try unlock(fixture("user-locked"), password: "wrong", destination: tempURL())
    }
}

// Round-trip fidelity: bookmarks live on the document, not on any page, so a
// page-by-page rebuild drops them unless they are explicitly carried over.
@Test func outlineSurvives() throws {
    let out = tempURL()
    try unlock(fixture("outlined"), password: nil, destination: out)

    let result = try #require(PDFDocument(url: out))
    let root = try #require(result.outlineRoot, "output has no outline at all")
    #expect(root.numberOfChildren == 3)
    #expect((0..<root.numberOfChildren).compactMap { root.child(at: $0)?.label }
        == ["Chapter 1", "Chapter 2", "Chapter 3"])
    // A bookmark that points nowhere is as good as missing.
    #expect(root.child(at: 2)?.destination?.page != nil, "bookmark lost its destination")
}

// The encrypted fixtures above are all written by qpdf. PDFKit writes
// encryption differently, and an implementation that strips only qpdf's leaves
// these encrypted while the rest of the suite stays green -- so both producers
// are covered, and the classifier is held to the same answer for each.
@Test(arguments: [
    ("user-locked", "pdfkit-user-locked", "hunter2", Classification.userLocked),
    ("owner-restricted", "pdfkit-owner-restricted", nil, Classification.ownerRestricted),
])
func bothProducersClassifyAndUnlockAlike(
    qpdfName: String, pdfkitName: String, password: String?, expected: Classification
) throws {
    for name in [qpdfName, pdfkitName] {
        #expect(classify(fixture(name)) == expected, "classify(\(name))")

        let out = tempURL()
        try unlock(fixture(name), password: password, destination: out)
        let result = try #require(PDFDocument(url: out), "\(name) produced an unreadable file")
        #expect(result.isEncrypted == false, "\(name) output still encrypted")
        #expect(result.pageCount == 3, "\(name) lost pages")
    }
}
