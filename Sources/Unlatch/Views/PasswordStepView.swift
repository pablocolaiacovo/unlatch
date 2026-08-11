import SwiftUI

/// Password entry with a Show/Hide toggle, inline error, and a shake on a
/// wrong password. Enter submits; empty passwords do nothing.
struct PasswordStepView: View {
    private enum Field: Hashable {
        case secure, plain
    }

    @Bindable var model: AppModel
    @FocusState private var focusedField: Field?

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
                Button(model.revealPassword ? "Hide" : "Show") {
                    model.revealPassword.toggle()
                    // Re-assert focus on the now-visible twin so typing
                    // continues uninterrupted after the toggle.
                    focusedField = model.revealPassword ? .plain : .secure
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
        .onAppear { focusedField = .secure }
        .onChange(of: model.password) { model.passwordError = false }
    }

    /// Both fields stay mounted, sharing the text binding; Show/Hide only
    /// swaps which one is visible and focused. Conditionally replacing
    /// SecureField with TextField would tear down the control and drop
    /// focus mid-typing.
    private var passwordField: some View {
        ZStack {
            SecureField("Password", text: $model.password)
                .focused($focusedField, equals: .secure)
                .opacity(model.revealPassword ? 0 : 1)
                .allowsHitTesting(!model.revealPassword)
            TextField("Password", text: $model.password)
                .focused($focusedField, equals: .plain)
                .opacity(model.revealPassword ? 1 : 0)
                .allowsHitTesting(model.revealPassword)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .onSubmit { model.submitPassword() }
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
