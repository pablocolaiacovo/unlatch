import AppKit
import SwiftUI

/// Hosts the unchanged `PopoverView` inside the AppKit `NSPopover`.
final class PopoverHostingController: NSHostingController<PopoverView> {
    private let onCancel: @MainActor () -> Void

    init(model: AppModel, onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
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

    /// Esc: NSResponder routes it here while the popover is key.
    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
