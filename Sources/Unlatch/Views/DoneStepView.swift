import SwiftUI

/// "Saved" summary with the destination path, plus Show in Finder / Done.
struct DoneStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(doneTitle(savedCount: model.savedURLs.count))
                .font(.system(size: 13, weight: .medium))
                .padding(.bottom, 2)
            Text(model.savedTo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Spacer()
                Button("Show in Finder") { model.showInFinder() }
                Button("Done") { model.reset() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}
