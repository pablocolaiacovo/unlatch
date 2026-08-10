import SwiftUI

/// Password entry with a Show/Hide toggle, inline error, and a shake on a
/// wrong password. Enter submits; empty passwords do nothing.
struct PasswordStepView: View {
    @Bindable var model: AppModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(passwordTitle(encryptedCount: model.encryptedFiles.count))
                .font(.system(size: 13, weight: .medium))
                .padding(.bottom, 4)
            Text(passwordSubtitle(encrypted: model.encryptedFiles))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.bottom, 12)

            HStack(spacing: 6) {
                passwordField
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .focused($fieldFocused)
                    .onSubmit { model.submitPassword() }
                Button(model.revealPassword ? "Hide" : "Show") {
                    model.revealPassword.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
            }
            .modifier(Shake(animatableData: CGFloat(model.shakeCount)))
            .animation(.linear(duration: 0.4), value: model.shakeCount)

            if model.passwordError {
                Text("That password didn’t work. Try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xC9302C))
                    .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.reset() }
                Button("Unlock") { model.submitPassword() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(14)
        .onAppear { fieldFocused = true }
        .onChange(of: model.password) { model.passwordError = false }
    }

    @ViewBuilder
    private var passwordField: some View {
        if model.revealPassword {
            TextField("Password", text: $model.password)
        } else {
            SecureField("Password", text: $model.password)
        }
    }
}

/// Horizontal shake, equivalent to the design's `shake` keyframes.
struct Shake: GeometryEffect {
    var travel: CGFloat = 4
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2),
            y: 0
        ))
    }
}
