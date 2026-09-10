import SwiftUI

/// "Saved" summary with the destination path, plus Show in Finder / Done.
/// When nothing was written, the title becomes the failure message and
/// Show in Finder is hidden — there is nothing to show.
struct DoneStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(doneTitle(savedCount: model.savedURLs.count))
                .font(.system(size: 13, weight: .medium))
                .padding(.bottom, 2)
            if !model.savedTo.isEmpty {
                Text(model.savedTo)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                Spacer()
                if !model.savedURLs.isEmpty {
                    Button("Show in Finder") { model.showInFinder() }
                }
                Button("Done") { model.reset() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}
