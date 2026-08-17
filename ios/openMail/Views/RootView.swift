import SwiftUI

/// Top-level switch between the signed-out login screen and the signed-in
/// tab shell, driven by `AuthStore.isAuthenticated`.
struct RootView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var restoreState: RestoreState = .restoring

    private enum RestoreState {
        case restoring
        case ready
        case failed
        case expired
    }

    var body: some View {
        Group {
            if authStore.isRestoringSession || restoreState == .restoring {
                restoringView
            } else if restoreState == .failed {
                retryView
            } else if authStore.isAuthenticated {
                MainTab()
            } else {
                LoginView(initialMessage: restoreState == .expired ? String(localized: "login.sessionExpired") : nil)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authStore.isAuthenticated)
        .task {
            await restoreSession()
        }
    }

    private var restoringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("login.restoringSession")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("login.restoringSession"))
    }

    private var retryView: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text("login.restoreFailed")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("login.retry") {
                Task { await restoreSession() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint(Text("login.retryAccessibilityHint"))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func restoreSession() async {
        guard restoreState == .restoring || restoreState == .failed else { return }
        restoreState = .restoring
        await authStore.restoreSession()

        if authStore.isAuthenticated {
            restoreState = .ready
        } else if let restoreError = authStore.restoreError {
            if case .unauthorized = restoreError {
                restoreState = .expired
            } else {
                // Do not turn a temporary network outage into an apparent logout.
                restoreState = .failed
            }
        } else {
            restoreState = .ready
        }
    }
}
