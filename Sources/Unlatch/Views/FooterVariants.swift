import AppKit
import Observation
import SwiftUI

// EXPLORATION ONLY (branch explore/footer-options). Nothing here ships: it
// compares four footer layouts against a stubbed updater. Environment:
//   UNLATCH_FOOTER_STYLE       compact | twoRow | menu | versionLink
//   UNLATCH_FOOTER_UPDATE      1 = "Update Available", 0 = normal
//   UNLATCH_FOOTER_LOGIN       on | off  (fakes the login item; swift run has none)
//   UNLATCH_FOOTER_APPEARANCE  light | dark
//   UNLATCH_FOOTER_VERSION     overrides the version label (long-string stress)
//   UNLATCH_FOOTER_AUTOSHOW    1 = open the popover at launch

enum FooterStyle: String {
    case compact, twoRow, menu, versionLink
}

/// Stand-in for T3's `AppUpdater`.
@MainActor
@Observable
final class StubUpdater {
    var updateAvailable: Bool
    var latestVersion = "1.2.0"
    init(updateAvailable: Bool) { self.updateAvailable = updateAvailable }
    func checkForUpdates() { NSLog("Unlatch(stub): checkForUpdates()") }
}

@MainActor
final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus
    init(on: Bool) { status = on ? .enabled : .disabled }
    func register() throws { status = .enabled }
    func unregister() throws { status = .disabled }
    func openSystemSettings() {}
}

enum ExplorationConfig {
    nonisolated static let versionOverride: String? =
        ProcessInfo.processInfo.environment["UNLATCH_FOOTER_VERSION"]

    @MainActor static let style =
        FooterStyle(rawValue: ProcessInfo.processInfo.environment["UNLATCH_FOOTER_STYLE"] ?? "") ?? .compact
    @MainActor static let updater =
        StubUpdater(updateAvailable: ProcessInfo.processInfo.environment["UNLATCH_FOOTER_UPDATE"] == "1")

    @MainActor static func makeModel() -> AppModel {
        if let login = ProcessInfo.processInfo.environment["UNLATCH_FOOTER_LOGIN"] {
            return AppModel(loginItemService: FakeLoginItem(on: login == "on"))
        }
        return AppModel()
    }

    @MainActor static var appearance: NSAppearance? {
        switch ProcessInfo.processInfo.environment["UNLATCH_FOOTER_APPEARANCE"] {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
    }

    /// A solid, neutral full-screen window behind the popover so every
    /// capture has the same backdrop instead of whatever is on the desktop.
    @MainActor private static var backdrop: NSWindow?

    /// Opens the footer menu without synthesising mouse events (CGEvents
    /// posted to this process did not open it). Tracking blocks the main
    /// thread until the menu closes, which is fine for a capture run.
    @MainActor private static func openFirstPopUpButton() {
        func find(_ view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton { return button }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        for window in NSApp.windows {
            if let root = window.contentView?.superview, let button = find(root) {
                button.performClick(nil)
                return
            }
        }
    }

    @MainActor static func applyLaunchOptions(_ controller: StatusItemController?) {
        let env = ProcessInfo.processInfo.environment
        NSApp.appearance = appearance
        if env["UNLATCH_FOOTER_BACKDROP"] == "1", let screen = NSScreen.main {
            let window = NSWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor =
                env["UNLATCH_FOOTER_APPEARANCE"] == "dark"
                ? NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
                : NSColor(red: 0.80, green: 0.83, blue: 0.88, alpha: 1)
            window.level = .normal
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            backdrop = window
        }
        if env["UNLATCH_FOOTER_AUTOSHOW"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                controller?.presentAndFocus()
                if env["UNLATCH_FOOTER_OPENMENU"] == "1" {
                    try? await Task.sleep(for: .milliseconds(1500))
                    openFirstPopUpButton()
                }
            }
        }
    }
}

struct FooterVariants: View {
    let view: PopoverView
    let style: FooterStyle
    let updater: StubUpdater

    var body: some View {
        switch style {
        case .compact: compact
        case .twoRow: twoRow
        case .menu: menuFooter
        case .versionLink: versionLink
        }
    }

    // MARK: Shared pieces

    private var versionLabelView: some View {
        Text(PopoverView.versionText)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// T3's button as designed in sparkle-updates.md 2.4.
    private var updateButton: some View {
        HoverButton(
            title: updater.updateAvailable ? "Update Available" : "Check for Updates…",
            dot: updater.updateAvailable,
            tint: updater.updateAvailable ? .accentColor : nil
        ) { updater.checkForUpdates() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .padding(.horizontal, 14)
            .frame(height: 26)
    }

    // MARK: A. One row, compact

    /// Everything in one 26 pt row; Quit drops its label to an icon so the
    /// version label keeps some room.
    private var compact: some View {
        row {
            versionLabelView
            Spacer(minLength: 4)
            updateButton
            view.loginItemToggle
            HoverButton(title: nil, symbol: "power", help: "Quit Unlatch") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: B. Two rows

    /// Row 1 holds the two settings-like controls, row 2 the status line:
    /// version on the left, Quit on the right.
    private var twoRow: some View {
        VStack(spacing: 0) {
            row {
                view.loginItemToggle
                Spacer()
                updateButton
            }
            row {
                versionLabelView
                Spacer()
                view.quitButton
            }
        }
    }

    // MARK: C. Ellipsis menu

    /// Version, Check for Updates, and Open at Login live in a menu next to
    /// Quit. The only thing outside it is "Update Available", which appears
    /// when there is something to act on, plus a dot on the menu button.
    private var menuFooter: some View {
        row {
            if updater.updateAvailable {
                updateButton
            }
            Spacer()
            Menu {
                Text(PopoverView.versionText)
                Divider()
                Button(updater.updateAvailable ? "Update Available…" : "Check for Updates…") {
                    updater.checkForUpdates()
                }
                Toggle(
                    "Open at Login",
                    isOn: Binding(
                        get: { view.model.loginItem.isOn },
                        set: { view.model.setLaunchAtLogin($0) }))
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .padding(.top, 4)
                    .padding(.trailing, 4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            // Drawn outside the menu label: NSPopUpButton flattens its label
            // to a template image and drops the accent colour.
            .overlay(alignment: .topTrailing) {
                if updater.updateAvailable {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(updater.updateAvailable ? "More, update available" : "More")
            view.quitButton
        }
    }

    // MARK: D. The version label is the update entry point

    /// Version text is a button: click to check for updates. When an update
    /// is waiting it turns into an accent "Version 1.2.0 available" with a dot.
    private var versionLink: some View {
        row {
            HoverButton(
                title: updater.updateAvailable
                    ? "Version \(updater.latestVersion) available"
                    : PopoverView.versionText,
                dot: updater.updateAvailable,
                tint: updater.updateAvailable ? .accentColor : nil,
                help: updater.updateAvailable ? "Update Available" : "Check for Updates…"
            ) { updater.checkForUpdates() }
            Spacer(minLength: 4)
            view.loginItemToggle
            view.quitButton
        }
    }
}

/// The footer's plain 11 pt button with a hover capsule, like Quit.
private struct HoverButton: View {
    var title: String?
    var symbol: String?
    var dot = false
    var tint: Color?
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    init(
        title: String?, symbol: String? = nil, dot: Bool = false, tint: Color? = nil,
        help: String? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.dot = dot
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if dot { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                if let title {
                    Text(title).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                }
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(
                tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(hovering ? .primary : .secondary)
            )
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? title ?? "")
        .accessibilityLabel(help ?? title ?? "")
        .onHover { hovering = $0 }
    }
}
