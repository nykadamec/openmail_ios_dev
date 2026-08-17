import SwiftUI

/// Modern, clean sign-in screen. Works in both light and dark mode.
struct LoginView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var username = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// An optional message supplied when a previously stored session expired.
    var initialMessage: String?

    init(initialMessage: String? = nil) {
        self.initialMessage = initialMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            // Brand mark
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 104, height: 104)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 24, y: 8)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 24)

            Text("login.title")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .padding(.bottom, 6)

            Text("login.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

            // Fields
            VStack(spacing: 14) {
                field(
                    icon: "person",
                    placeholder: "login.username",
                    text: $username,
                    secure: false
                )
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                field(
                    icon: "lock",
                    placeholder: "login.password",
                    text: $password,
                    secure: true
                )
                .textContentType(.password)
                .onSubmit {
                    Task { await submit() }
                }
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $rememberMe) {
                    Text("login.rememberMe")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(.switch)
                .disabled(isLoading)
                .accessibilityHint(Text("login.rememberMeAccessibilityHint"))

                Text("login.rememberMeHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            // Error
            if let errorMessage = errorMessage ?? initialMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            // Submit
            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("login.submit")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canSubmit && !isLoading ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.4)))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || !canSubmit)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .accessibilityLabel(Text("login.submit"))
            .accessibilityHint(Text(isLoading ? "login.submittingAccessibilityHint" : "login.submitAccessibilityHint"))

            Spacer(minLength: 40)
        }
        .background(Color(.systemBackground))
        .onChange(of: authStore.isAuthenticated) { _, authenticated in
            if authenticated {
                reset()
            }
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func field(icon: String, placeholder: LocalizedStringKey, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.body)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
        )
    }

    private func submit() async {
        guard canSubmit, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await authStore.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                rememberMe: rememberMe
            )
        } catch is APIClientError {
            errorMessage = String(localized: "login.error")
        } catch {
            errorMessage = String(localized: "errors.generic")
        }
    }

    private func reset() {
        password = ""
        errorMessage = nil
    }
}

#Preview {
    LoginView()
        .environment(AuthStore())
}
