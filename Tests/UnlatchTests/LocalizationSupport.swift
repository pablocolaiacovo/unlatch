import Foundation
@testable import Unlatch

// Test helpers for strings that `Logic.swift` returns as `LocalizedStringResource`
// (Design/spanish-localization.md §2.7).
//
// The test runner's main bundle has no localizations, so a resource resolved with its default
// locale is English on every Mac, even one whose language is Spanish. These helpers set the
// resource's `locale` to a literal language instead, so a test gives the same answer on any
// machine. Only tests do this: production code leaves `locale` alone.

/// Resolves `resource` in `language` ("en" or "es"), independent of this Mac's language.
func resolved(_ resource: LocalizedStringResource, _ language: String) -> String {
    var resource = resource
    resource.locale = Locale(identifier: language)
    return String(localized: resource)
}

func en(_ resource: LocalizedStringResource) -> String { resolved(resource, "en") }
func es(_ resource: LocalizedStringResource) -> String { resolved(resource, "es") }
