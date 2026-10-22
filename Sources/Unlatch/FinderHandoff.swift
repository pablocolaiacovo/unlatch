import AppKit

/// Receives PDFs from outside the popover and hands them to AppModel. There
/// are two sources: the "Unlock with Unlatch" Services entry, and Open With,
/// `open -a`, or a drop on the app's icon in Finder (forwarded by
/// AppDelegate.application(_:open:)). There is one instance, owned by
/// AppDelegate for the process lifetime.
/// See Design/finder-quick-action.md, §2.3.
@MainActor
final class FinderHandoff: NSObject {
    private let coalescingDelay: Duration
    private var buffer = IncomingFiles()
    private var deliver: (@MainActor ([URL]) -> Void)?
    private var timer: Task<Void, Never>?

    init(coalescingDelay: Duration = .milliseconds(250)) {
        self.coalescingDelay = coalescingDelay
        super.init()
    }

    /// Called once by AppDelegate after StatusItemController exists. Stores
    /// `deliver` and, if the buffer is non-empty (on a cold launch AppKit
    /// calls application(_:open:) before applicationDidFinishLaunching),
    /// restarts the coalescing timer with the full delay. Never delivers
    /// inline: that would open the popover before the status item button has
    /// been laid out.
    func connect(to deliver: @escaping @MainActor ([URL]) -> Void) {
        self.deliver = deliver
        if !buffer.isEmpty {
            restartTimer()
        }
    }

    /// Open With, `open -a`, a drop on the app icon.
    func receive(_ urls: [URL]) {
        buffer.add(urls)
        restartTimer()
    }

    /// Drops buffered URLs and cancels the pending flush. AppModel calls it
    /// (through onPanelConfirmed) when the user confirms the "Choose PDFs…"
    /// or "Choose folder…" panel, so a hand-off received before that point
    /// can't replace the panel's selection or the batch the folder was
    /// chosen for. It never delivers.
    func discardPending() {
        timer?.cancel()
        timer = nil
        _ = buffer.take()
    }

    /// Services entry point. The selector must match NSMessage "unlockPDFs"
    /// in Resources/Info.plist.template (InfoPlistTemplateTests checks it).
    /// Returns immediately, so the Services request never waits on PDF work.
    @objc func unlockPDFs(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls =
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        NSLog("Unlatch: hand-off received %d file(s) via %@", urls.count, "Services")
        guard !urls.isEmpty else {
            error.pointee = String(localized: Strings.finderCouldntReadFiles) as NSString
            return
        }
        receive(urls)
    }

    /// Launch Services doesn't promise one open call per user action (9 files
    /// from one Open With have arrived as 5 plus 4), so every arrival restarts
    /// the same timer and one flush delivers the whole burst.
    private func restartTimer() {
        timer?.cancel()
        let delay = coalescingDelay
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        timer = nil
        guard let deliver, !buffer.isEmpty else { return }
        deliver(buffer.take())
    }
}
