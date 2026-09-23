import SwiftUI

/// The "Choose PDFs…" call to action plus the privacy caption. v1.0 is
/// picker-only: dragging a file in from Finder closes the popover before it
/// reaches this view (see `PopoverDismissalMonitor`), so the copy never
/// promises a drop. The button is still a drop destination for file URLs,
/// harmless on the rare occasion a drop reaches it, but nothing here
/// advertises it: no drop wording and no hover highlight.
/// Click or Return opens the file picker.
struct IdleStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            chooseButton
            Text("Removes the open password so the file opens without one. Nothing leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                // Under NSHostingController's preferredContentSize sizing,
                // an unconstrained multi-line Text can report a one-line
                // ideal height and get clipped. Forcing the ideal height at
                // the frame's fixed width makes it grow to fit both lines.
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private var chooseButton: some View {
        Button { model.browse() } label: {
            VStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.primary.opacity(0.72))
                    .accessibilityHidden(true)
                Text("Choose PDFs…")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .dropDestination(for: URL.self) { urls, _ in
            model.load(urls)
            return true
        }
    }
}
