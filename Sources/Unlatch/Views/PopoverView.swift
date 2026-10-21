import AppKit
import SwiftUI

/// The 372 pt popover panel: header, current step, the persistent file rows
/// section, and a footer with an ellipsis menu (installed version, update
/// check, Check Automatically, Open at Login), the "Update Available" button when there is one,
/// and the Quit control.
struct PopoverView: View {
    @Bindable var model: AppModel
    let updater: AppUpdater

    /// The bundle's version never changes while running, so build it once.
    private static let versionText = versionLabel(
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch model.step {
            case .idle:
                IdleStepView(model: model)
            case .password:
                PasswordStepView(model: model)
            case .working:
                workingView
            case .destination:
                DestinationStepView(model: model)
            case .done:
                DoneStepView(model: model)
            }

            if model.showsFileRows {
                FileRowList(files: model.files, done: model.step == .done)
            }

            Divider()
            footer
        }
        .frame(width: 372)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Unlatch")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(model.headerText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }

    /// Single 26 pt row with a fixed height so it never clips under the hosting
    /// controller's preferred-content-size sizing. The version, the update
    /// check, and Open at Login live in the ellipsis menu; only Quit, and the
    /// "Update Available" button when there is something to act on, sit in the
    /// row itself (Design/sparkle-updates.md §2.4.2).
    private var footer: some View {
        let update = updateFooterPresentation(for: updater.buttonState)
        let automatic = automaticChecksMenuItem(
            availability: updater.availability, isOn: updater.automaticallyChecksForUpdates)
        return HStack(spacing: 6) {
            if update.showsUpdateIndicator { updateAvailableButton }
            Spacer()
            moreMenu(update, automaticChecks: automatic)
                .overlay(alignment: .topTrailing) {
                    if update.showsUpdateIndicator { updateDot }
                }
            quitButton
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }

    /// Version (a disabled item), the update item, Check Automatically, and Open at
    /// Login. Check Automatically mirrors Sparkle's setting the same way. Open at
    /// Login shows the system's login item state, not a stored preference; see
    /// `loginItemControl(for:)`. A menu item does not flip itself on click, so
    /// the checkmark always reads `model.loginItem.isOn`.
    @ViewBuilder
    private func moreMenu(
        _ update: UpdateFooterPresentation, automaticChecks: AutomaticChecksMenuItem?
    ) -> some View {
        let control = model.loginItem
        let menu = Menu {
            Text(Self.versionText)
            Divider()
            if let title = update.menuItemTitle {
                Button(title) { updater.checkForUpdates() }
                    .disabled(!update.menuItemEnabled)
            }
            if let automaticChecks {
                Toggle(
                    automaticChecks.title,
                    isOn: Binding(
                        get: { automaticChecks.isChecked },
                        set: { updater.setAutomaticallyChecksForUpdates($0) })
                )
            }
            Toggle(
                "Open at Login",
                isOn: Binding(get: { model.loginItem.isOn }, set: { model.setLaunchAtLogin($0) })
            )
            .disabled(!control.isEnabled)
            .help(control.help)
        } label: {
            // The padding leaves room for the dot beside the glyph.
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .padding(.top, 4)
                .padding(.trailing, 4)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
        // Only when there is something to announce: an empty string still
        // exposes an AXValue (checked with the AX API), and the design wants none.
        if update.showsUpdateIndicator {
            menu.accessibilityValue("Update available")
        } else {
            menu
        }
    }

    /// Drawn outside the menu label: the `NSPopUpButton` behind a `Menu`
    /// flattens its label to a template image and drops the accent colour.
    private var updateDot: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var updateAvailableButton: some View {
        FooterButton(title: "Update Available", tint: .accentColor, showsDot: true) {
            updater.checkForUpdates()
        }
        .help("See the available update")
        .accessibilityLabel("Update Available")
    }

    /// Unobtrusive quit affordance in the footer, reachable from every
    /// step. `.accessory` apps have no Dock icon and no application menu, so
    /// this is the only way to quit besides Force Quit.
    private var quitButton: some View {
        FooterButton(title: "Quit", symbol: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .help("Quit Unlatch")
        .accessibilityLabel("Quit Unlatch")
    }

    private var workingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Unlocking…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }
}

/// The footer's plain 11 pt button with a hover capsule, shared by Quit and
/// "Update Available" so the two can't drift apart.
private struct FooterButton: View {
    let title: String
    var symbol: String?
    var tint: Color?
    var showsDot = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if showsDot {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 11))
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if let tint { return tint }
        return hovering ? .primary : .secondary
    }
}

extension Color {
    /// Exact design colors for the hand-drawn parts (badges).
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
