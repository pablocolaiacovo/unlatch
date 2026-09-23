import AppKit
import SwiftUI

/// Hosts the unchanged `PopoverView` inside the AppKit `NSPopover`.
///
/// Esc is handled by `PopoverDismissalMonitor`'s local key monitor, not by
/// overriding `cancelOperation(_:)` here — see that type's doc comment for
/// why a first-responder-based override isn't reliable on every step.
final class PopoverHostingController: NSHostingController<PopoverView> {
    init(model: AppModel) {
        super.init(rootView: PopoverView(model: model))
        // Below the macOS 14 target (13.3 on the controller, 13.0 on the
        // option set), so NSPopover follows the SwiftUI content height as
        // steps change. The width stays 372 pt from PopoverView's own frame.
        sizingOptions = .preferredContentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
