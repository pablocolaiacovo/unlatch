import Foundation
import Testing
@testable import Unlatch

// Spanish (and English) text of every string `Logic.swift` returns, resolved with an explicit
// language so the result is the same on any Mac (see LocalizationSupport.swift). The expected
// Spanish is the maintainer-approved wording; these tests change with the wording.

private let source = URL(fileURLWithPath: "/tmp/Documents/Q3-Financials.pdf")
private let desktop = URL(fileURLWithPath: "/tmp/Desktop", isDirectory: true)

private func file(
    _ kind: FileKind, unlocked: Bool = false, failure: SaveFailure? = nil
) -> LoadedFile {
    var file = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: kind)
    file.unlocked = unlocked
    file.failure = failure
    return file
}

// MARK: - Plurals and counts

@Test func passwordCopyInSpanish() {
    #expect(es(passwordTitle(encryptedCount: 1)) == "Este PDF necesita una contraseña")
    #expect(es(passwordTitle(encryptedCount: 3)) == "3 archivos necesitan una contraseña")
    // One file: the subtitle is the file name, untouched in both languages.
    #expect(es(passwordSubtitle(encrypted: [file(.encrypted)])) == "a.pdf")
    #expect(es(passwordSubtitle(encrypted: [file(.encrypted), file(.encrypted)]))
        == "Probaremos la misma contraseña en todos. Los que no coincidan se omitirán.")
}

@Test func doneTitleInSpanish() {
    #expect(es(doneTitle(savedCount: 0)) == "No se pudo guardar — no se escribió nada")
    #expect(es(doneTitle(savedCount: 1)) == "Guardado")
    #expect(es(doneTitle(savedCount: 3)) == "3 archivos guardados")
    #expect(es(doneTitle(savedCount: 0, failedCount: 1)) == "No se pudo guardar — falló el archivo")
    #expect(es(doneTitle(savedCount: 0, failedCount: 3))
        == "No se pudo guardar — fallaron los 3 archivos")
    #expect(es(doneTitle(savedCount: 3, failedCount: 2)) == "3 guardados, 2 fallaron")
}

@Test func doneTitlePartialBatchAgreesInSpanish() {
    #expect(es(doneTitle(savedCount: 1, failedCount: 1)) == "1 guardado, 1 falló")
    #expect(es(doneTitle(savedCount: 2, failedCount: 1)) == "2 guardados, 1 falló")
    #expect(es(doneTitle(savedCount: 1, failedCount: 3)) == "1 guardado, 3 fallaron")
}

@Test func destinationQuestionInBothLanguages() {
    #expect(en(destinationQuestion(usableCount: 1)) == "Where should the unlocked file go?")
    #expect(en(destinationQuestion(usableCount: 2)) == "Where should the unlocked files go?")
    #expect(es(destinationQuestion(usableCount: 1)) == "¿Dónde quieres guardar el archivo desbloqueado?")
    #expect(es(destinationQuestion(usableCount: 2)) == "¿Dónde quieres guardar los archivos desbloqueados?")
}

// MARK: - Done summary and hints

@Test func doneSummaryInSpanish() {
    let a = URL(fileURLWithPath: "/tmp/Documents/A-unlocked.pdf")
    let b = URL(fileURLWithPath: "/tmp/Documents/B-unlocked.pdf")
    let c = URL(fileURLWithPath: "/tmp/Archive/C-unlocked.pdf")
    func summary(_ urls: [URL], _ option: DestinationOption) -> String? {
        doneSummary(destinations: urls, option: option).map(es)
    }
    // Paths are shown as they are.
    #expect(summary([a], .suffix) == "/tmp/Documents/A-unlocked.pdf")
    #expect(summary([a, b], .suffix) == "/tmp/Documents/…-unlocked.pdf")
    #expect(summary([a, b], .desktop) == "/tmp/Documents/")
    #expect(summary([a, b], .other) == "/tmp/Documents/")
    // The path moves into a sentence, which is translated.
    #expect(summary([a, b], .replace) == "/tmp/Documents/ (originales reemplazados)")
    #expect(summary([a, b, c], .suffix) == "3 archivos en 2 carpetas")
    #expect(summary([], .suffix) == nil)
}

@Test func destinationHintsInSpanish() {
    func hint(_ option: DestinationOption, sample: URL?, chosen: URL? = nil) -> String {
        es(destinationHint(
            option: option, sample: sample, desktopFolder: desktop, chosenFolder: chosen))
    }
    #expect(hint(.suffix, sample: nil) == "junto al original")
    #expect(hint(.suffix, sample: source) == "/tmp/Documents/Q3-Financials-unlocked.pdf")
    #expect(hint(.replace, sample: nil) == "reemplaza el original")
    #expect(hint(.replace, sample: source) == "/tmp/Documents/Q3-Financials.pdf")
    #expect(hint(.desktop, sample: source) == "/tmp/Desktop/")
    #expect(hint(.other, sample: source) == "abre un panel para guardar")
    #expect(hint(.other, sample: source, chosen: URL(fileURLWithPath: "/tmp/Unlocked", isDirectory: true))
        == "/tmp/Unlocked/")
}

@Test func destinationLabelsInSpanish() {
    #expect(es(DestinationOption.suffix.label) == "Misma carpeta, agregar “-unlocked”")
    #expect(es(DestinationOption.replace.label) == "Misma carpeta, reemplazar el original")
    #expect(es(DestinationOption.desktop.label) == "Escritorio")
    #expect(es(DestinationOption.other.label) == "Elegir carpeta…")
    // The suffix is the real file name suffix, so it stays in English in every language.
    #expect(en(DestinationOption.suffix.label) == "Same folder, add “-unlocked”")
}

@Test func versionLabelInSpanish() {
    #expect(es(versionLabel(version: "1.0.0", build: "42")) == "Versión 1.0.0 (42)")
    #expect(es(versionLabel(version: "1.0.0", build: nil)) == "Versión 1.0.0")
    #expect(es(versionLabel(version: nil, build: nil)) == "Versión dev")
    #expect(es(versionLabel(version: nil, build: "42")) == "Versión dev (42)")
}

// MARK: - Rows

@Test func rowNotesInSpanish() {
    func note(_ file: LoadedFile, done: Bool) -> String { es(rowInfo(for: file, done: done).note) }
    #expect(note(file(.encrypted), done: false) == "Protegido con contraseña")
    #expect(note(file(.encrypted, unlocked: true), done: true) == "Desbloqueado")
    #expect(note(file(.owner), done: false) == "Sin contraseña de apertura — solo permisos")
    #expect(note(file(.owner, unlocked: true), done: true)
        == "Copiado tal cual — se abre sin contraseña")
    #expect(note(file(.plain), done: false) == "Sin cifrar — nada que desbloquear")
    #expect(note(file(.plain, unlocked: true), done: true) == "Sin cifrar — copiado tal cual")
    #expect(note(file(.corrupt), done: false) == "No es un PDF legible — se omitió")
}

@Test func saveFailureNotesInSpanish() {
    #expect(es(SaveFailure.wrongPassword.note) == "La contraseña no coincide — no se guardó")
    #expect(es(SaveFailure.unreadable.note) == "No se pudo leer — no se guardó")
    #expect(es(SaveFailure.writeFailed.note) == "No se pudo escribir el archivo — no se guardó")
    #expect(es(SaveFailure.copyFailed.note) == "No se pudo copiar — no se guardó")
    // A failed row shows the failure note, not the kind's note.
    #expect(es(rowInfo(for: file(.encrypted, failure: .writeFailed), done: true).note)
        == es(SaveFailure.writeFailed.note))
}

// MARK: - Status item, login item, updates

@Test func statusItemInSpanish() {
    let update = statusItemPresentation(hasLockedWork: false, updateState: .updateAvailable)
    #expect(update.accessibilityValue.map(es) == "Actualización disponible")
    #expect(es(update.toolTip) == "Unlatch: actualización disponible")
    // The app name is never translated.
    let plain = statusItemPresentation(hasLockedWork: false, updateState: .check)
    #expect(es(plain.toolTip) == "Unlatch")
    #expect(en(plain.toolTip) == "Unlatch")
}

@Test func loginItemHelpInSpanish() {
    #expect(es(loginItemControl(for: .enabled).help) == "Unlatch se abre al iniciar sesión")
    #expect(es(loginItemControl(for: .disabled).help) == "Abrir Unlatch al iniciar sesión")
    #expect(es(loginItemControl(for: .requiresApproval).help)
        == "Desactivado en los ajustes de inicio de sesión de macOS. Marca la opción para abrirlos y permitir Unlatch.")
    #expect(es(loginItemControl(for: .unavailable).help)
        == "Disponible cuando Unlatch se ejecuta desde una App")
}

@Test func updateMenuItemsInSpanish() {
    #expect(es(UpdateFooterPresentation.checkTitle) == "Buscar actualizaciones…")
    #expect(es(UpdateFooterPresentation.updateAvailableTitle) == "Actualización disponible…")
    #expect(es(AutomaticChecksMenuItem.checkAutomaticallyTitle) == "Verificar automáticamente")
}

// MARK: - Every string, in both languages

/// One `Logic` output with what its resolved text must contain and whether Spanish may equal
/// English (paths, file names, and the app name are never translated).
private struct Sample: Sendable, CustomTestStringConvertible {
    let name: String
    let resource: LocalizedStringResource
    var contains: [String] = []
    var translated = true

    var testDescription: String { name }
}

private let samples: [Sample] = {
    let a = URL(fileURLWithPath: "/tmp/Documents/A-unlocked.pdf")
    let b = URL(fileURLWithPath: "/tmp/Documents/B-unlocked.pdf")
    let c = URL(fileURLWithPath: "/tmp/Archive/C-unlocked.pdf")
    let sample = URL(fileURLWithPath: "/tmp/Documents/Q3-Financials.pdf")
    let chosen = URL(fileURLWithPath: "/tmp/Unlocked", isDirectory: true)
    var list: [Sample] = []
    for option in DestinationOption.allCases {
        list.append(Sample(name: "label \(option)", resource: option.label))
        list.append(Sample(
            name: "hint \(option) without paths",
            resource: destinationHint(
                option: option, sample: nil, desktopFolder: desktop, chosenFolder: nil),
            translated: option == .suffix || option == .replace || option == .other))
        list.append(Sample(
            name: "hint \(option) with paths",
            resource: destinationHint(
                option: option, sample: sample, desktopFolder: desktop, chosenFolder: chosen),
            contains: ["/tmp/"], translated: false))
    }
    for failure in [SaveFailure.wrongPassword, .unreadable, .writeFailed, .copyFailed] {
        list.append(Sample(name: "note \(failure)", resource: failure.note))
    }
    for count in [1, 3] {
        list.append(Sample(
            name: "password title \(count)", resource: passwordTitle(encryptedCount: count),
            contains: count > 1 ? ["\(count)"] : []))
    }
    list.append(Sample(
        name: "password subtitle, one file",
        resource: passwordSubtitle(encrypted: [file(.encrypted)]),
        contains: ["a.pdf"], translated: false))
    list.append(Sample(
        name: "password subtitle, batch",
        resource: passwordSubtitle(encrypted: [file(.encrypted), file(.encrypted)])))
    for (saved, failed) in [(0, 0), (1, 0), (3, 0), (0, 1), (0, 3), (1, 1), (2, 1), (1, 3), (5, 2)] {
        var contains: [String] = []
        if saved > 1 || (saved > 0 && failed > 0) { contains.append("\(saved)") }
        if failed > 1 || (saved > 0 && failed > 0) { contains.append("\(failed)") }
        list.append(Sample(
            name: "done title \(saved)/\(failed)",
            resource: doneTitle(savedCount: saved, failedCount: failed), contains: contains))
    }
    for option in DestinationOption.allCases {
        for (name, urls) in [("one", [a]), ("one folder", [a, b]), ("two folders", [a, b, c])] {
            guard let resource = doneSummary(destinations: urls, option: option) else { continue }
            let spread = name == "two folders"
            let replaced = name == "one folder" && option == .replace
            list.append(Sample(
                name: "summary \(name) \(option)", resource: resource,
                contains: spread ? ["3", "2"] : ["/tmp/Documents/"],
                translated: spread || replaced))
        }
    }
    for usable in [1, 2] {
        list.append(Sample(
            name: "question \(usable)", resource: destinationQuestion(usableCount: usable)))
    }
    list.append(Sample(
        name: "version", resource: versionLabel(version: "1.2.3", build: "45"),
        contains: ["1.2.3", "45"]))
    list.append(Sample(
        name: "version dev", resource: versionLabel(version: nil, build: nil), contains: ["dev"]))
    for kind in [FileKind.encrypted, .owner, .plain, .corrupt] {
        for done in [false, true] {
            list.append(Sample(
                name: "row \(kind) done=\(done)",
                resource: rowInfo(for: file(kind, unlocked: done), done: done).note))
        }
    }
    for status in [LoginItemStatus.enabled, .disabled, .requiresApproval, .unavailable] {
        list.append(Sample(name: "login \(status)", resource: loginItemControl(for: status).help))
    }
    let update = statusItemPresentation(hasLockedWork: false, updateState: .updateAvailable)
    list.append(Sample(name: "status value", resource: StatusItemPresentation.updateAvailableValue))
    list.append(Sample(name: "status tooltip", resource: update.toolTip))
    list.append(Sample(
        name: "status tooltip, no update",
        resource: statusItemPresentation(hasLockedWork: false, updateState: .check).toolTip,
        contains: ["Unlatch"], translated: false))
    list.append(Sample(name: "check title", resource: UpdateFooterPresentation.checkTitle))
    list.append(Sample(
        name: "update title", resource: UpdateFooterPresentation.updateAvailableTitle))
    list.append(Sample(
        name: "automatic title", resource: AutomaticChecksMenuItem.checkAutomaticallyTitle))
    return list
}()

@Test(arguments: samples, ["en", "es"])
private func resolvedTextIsCompleteInEveryLanguage(_ sample: Sample, _ language: String) {
    let text = resolved(sample.resource, language)
    #expect(!text.isEmpty)
    for specifier in ["%@", "%lld", "%#@", "%arg", "%1$", "%2$"] {
        #expect(!text.contains(specifier), "\(sample.name) in \(language): \(text)")
    }
    for part in sample.contains {
        #expect(text.contains(part), "\(sample.name) in \(language): \(text)")
    }
    if language == "es", sample.translated {
        #expect(text != resolved(sample.resource, "en"), "\(sample.name) is not translated")
    }
}

/// File names reach the screen as they are, even when they look like format specifiers.
@Test func fileNamesAndPathsPassThroughUntouched() {
    let odd = URL(fileURLWithPath: "/tmp/100% sure %d %@ %lld.pdf")
    for language in ["en", "es"] {
        #expect(resolved(passwordSubtitle(encrypted: [
            LoadedFile(url: odd, kind: .encrypted),
        ]), language) == "100% sure %d %@ %lld.pdf")
        #expect(resolved(
            doneSummary(destinations: [odd], option: .suffix) ?? verbatim(""), language)
            == "/tmp/100% sure %d %@ %lld.pdf")
    }
}
