import SwiftUI

/// The 372 pt popover panel: header, current step, and the persistent file
/// rows section.
struct PopoverView: View {
    @Bindable var model: AppModel

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
        }
        .frame(width: 372)
    }

    private var header: some View {
        HStack {
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
