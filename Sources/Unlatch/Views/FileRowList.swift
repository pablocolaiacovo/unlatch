import SwiftUI

/// The grouped file list: hairline top border, slightly darker background,
/// one row per file with a 14 pt circular badge, name, and note.
struct FileRowList: View {
    let files: [LoadedFile]
    let done: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(files) { file in
                row(for: file)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .top) { Divider() }
    }

    private func row(for file: LoadedFile) -> some View {
        let info = rowInfo(for: file, done: done)
        return HStack(spacing: 8) {
            Circle()
                .fill(badgeColor(info.tone))
                .frame(width: 14, height: 14)
                .overlay(
                    Text(info.badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(info.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(noteColor(info.tone))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func badgeColor(_ tone: RowTone) -> Color {
        switch tone {
        // systemGray, not primary.opacity: primary flips to white in dark
        // mode, which would erase the white badge glyph. A mid gray keeps
        // the white text legible in both appearances.
        case .neutral: Color(nsColor: .systemGray)
        case .success: Color(hex: 0x3A9D5D)
        case .warning: Color(hex: 0xB9A24A)
        case .error: Color(hex: 0xD0563E)
        }
    }

    private func noteColor(_ tone: RowTone) -> Color {
        switch tone {
        case .error: Color(hex: 0xB04A34)
        default: Color.secondary
        }
    }
}
