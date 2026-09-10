import SwiftUI

/// The dashed drop zone plus the privacy caption. Click browses; it is also a
/// drop destination for file URLs, highlighting while a drag hovers.
struct IdleStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            dropZone
            Text("Removes the open password so the file opens without one. Nothing leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(14)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 24))
                .foregroundStyle(.primary.opacity(0.72))
            Text("Drop PDFs here")
                .font(.system(size: 13, weight: .medium))
            Text("or click to browse")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(model.dragging ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    model.dragging ? Color.accentColor : Color.primary.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { model.browse() }
        .dropDestination(for: URL.self) { urls, _ in
            model.load(urls)
            return true
        } isTargeted: { targeted in
            model.dragging = targeted
        }
        .animation(.easeOut(duration: 0.12), value: model.dragging)
    }
}
