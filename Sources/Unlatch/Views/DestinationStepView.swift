import SwiftUI

/// The four destination radio options with monospaced path hints, plus
/// Cancel/Save. "Choose folder…" opens a folder picker on click.
///
/// The radios are hand-drawn to carry a path hint, so they get what an AppKit radio group gives for
/// free: the group takes focus when the step appears, arrows move the selection, Space re-chooses
/// the current option, and VoiceOver sees a real radio group.
struct DestinationStepView: View {
    @Bindable var model: AppModel
    @FocusState private var optionsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(destinationQuestion(usableCount: model.usableFiles.count))
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(DestinationOption.allCases, id: \.self) { option in
                    optionRow(option)
                }
            }
            .focusable()
            .focused($optionsFocused)
            .onMoveCommand { direction in
                switch direction {
                case .up: select(model.destination.moved(by: -1))
                case .down: select(model.destination.moved(by: 1))
                default: break
                }
            }
            .onKeyPress(.space) {
                select(model.destination)
                return .handled
            }
            .accessibilityRepresentation {
                Picker(selection: selection) {
                    ForEach(DestinationOption.allCases, id: \.self) { option in
                        Text(option.label) + Text(verbatim: ", ") + Text(hint(for: option))
                    }
                } label: {
                    Text(destinationQuestion(usableCount: model.usableFiles.count))
                }
                .pickerStyle(.radioGroup)
            }

            HStack(spacing: 8) {
                Spacer()
                Button(Strings.cancel) { model.reset() }
                Button(Strings.save) { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(14)
        .onAppear { optionsFocused = true }
    }

    private var selection: Binding<DestinationOption> {
        Binding(get: { model.destination }, set: { select($0) })
    }

    private func select(_ option: DestinationOption) {
        if option == .other {
            model.chooseOtherFolder()
        } else {
            model.destination = option
        }
    }

    private func hint(for option: DestinationOption) -> LocalizedStringResource {
        destinationHint(
            option: option,
            sample: model.sampleFile,
            desktopFolder: model.desktopFolder,
            chosenFolder: model.chosenFolder
        )
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
                Text(hint(for: option))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(option) }
    }
}
