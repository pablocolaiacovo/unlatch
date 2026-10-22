import Foundation
import Testing
@testable import Unlatch

// The compiled string catalog (Design/spanish-localization.md §2.1, §4).

/// Swift Build compiles `Localizable.xcstrings` into one `.lproj` per language. The deprecated
/// native build system copies the raw catalog instead, which would leave the app English-only
/// without any other sign, so this fails if that ever ships.
@Test func moduleBundleHasCompiledSpanish() {
    let bundle = Bundle.module
    #expect(bundle.localizations.contains("en"))
    #expect(bundle.localizations.contains("es"))
    #expect(
        bundle.url(
            forResource: "Localizable", withExtension: "strings", subdirectory: nil,
            localization: "es") != nil)
    #expect(bundle.url(forResource: "Localizable", withExtension: "xcstrings") == nil)
}
