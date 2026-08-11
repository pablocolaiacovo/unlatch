import SwiftUI

/// The four destination radio options with monospaced path hints, plus
/// Cancel/Save. "Choose folder…" opens a folder picker on click.
struct DestinationStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Where should the unlocked \(model.usableFiles.count > 1 ? "files" : "file") go?")
                .font(.system(size: 13, weight: .medium))
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(DestinationOption.allCases, id: \.self) { option in
                    optionRow(option)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.reset() }
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(14)
    }

    private func optionRow(_ option: DestinationOption) -> some View {
        let selected = model.destination == option
        return HStack(alignment: .top, spacing: 8) {
            ZStack {
                // Semantic fill so the unselected radio doesn't glare in
                // dark mode; the inner dot stays white on the accent fill,
                // matching real AppKit radios in both appearances.
                Circle()
                    .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                Circle()
                    .strokeBorder(Color.primary.opacity(0.28), lineWidth: 0.5)
                if selected {
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 14, height: 14)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: 13))
                Text(destinationHint(
                    option: option,
                    sample: model.sampleFile,
                    desktopFolder: model.desktopFolder,
                    chosenFolder: model.chosenFolder
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if option == .other {
                model.chooseOtherFolder()
            } else {
                model.destination = option
            }
        }
    }
}
