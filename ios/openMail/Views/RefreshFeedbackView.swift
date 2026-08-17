import SwiftUI

enum RefreshFeedback: Equatable {
    case success(Int)
    case failure
}

struct RefreshFeedbackView: View {
    let feedback: RefreshFeedback
    let dismiss: () -> Void

    private var isError: Bool {
        if case .failure = feedback { return true }
        return false
    }

    private var message: String {
        switch feedback {
        case .failure:
            return NSLocalizedString("refresh.failed", comment: "Refresh failure")
        case .success(let count) where count == 0:
            return NSLocalizedString("refresh.noNewEmails", comment: "No new messages")
        case .success(let count):
            let key: String
            switch count {
            case 1: key = "refresh.newEmails.one"
            case 2...4: key = "refresh.newEmails.few"
            default: key = "refresh.newEmails.many"
            }
            return String.localizedStringWithFormat(
                NSLocalizedString(key, comment: "New message count"), count
            )
        }
    }

    private var icon: String { isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill" }
    private var tint: Color { isError ? .orange : .accentColor }

    var body: some View {
        Button(action: dismiss) {
            Label(message, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .tint(tint)
        .accessibilityLabel(message)
        .accessibilityHint(Text("refresh.dismissHint"))
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
