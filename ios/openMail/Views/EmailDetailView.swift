import SwiftUI
import QuickLook

/// Full email view: header (sender/recipient/time), HTML or plain-text body
/// and a downloadable attachment list. Starring happens from the toolbar.
struct EmailDetailView: View {
    let emailID: Int

    @Environment(AuthStore.self) private var authStore

    @State private var detail: EmailDetail?
    @State private var isLoading = true
    @State private var htmlDidFailToLoad = false

    @State private var downloaded: [String: URL] = [:]
    @State private var downloading: Set<String> = []

    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("loading.email")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                content(detail)
            } else {
                ContentUnavailableView(
                    "errors.generic",
                    systemImage: "exclamationmark.triangle",
                    description: Text("errors.unauthorized")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleStar(detail) }
                    } label: {
                        Image(systemName: detail.isStarred ? "star.fill" : "star")
                            .foregroundStyle(detail.isStarred ? Color.yellow : Color.accentColor)
                            .accessibilityLabel(detail.isStarred ? "action.unstar" : "action.star")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await load() }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ActivityView(items: [url])
            }
        }
    }

    // MARK: - Content

    private func content(_ email: EmailDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let subject = email.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.title2.weight(.bold))
                }

                HStack(alignment: .top, spacing: 12) {
                    AvatarView(name: senderName(email))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(senderName(email))
                            .font(.subheadline.weight(.semibold))
                        if let recipient = email.recipient, !recipient.isEmpty {
                            Text(recipient)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(longTimeLabel(from: email.received_at ?? email.created_at))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // HTML is the primary representation. Plain text is only shown
                // when HTML is absent or WKWebView cannot render it.
                if let html = nonEmptyBodyHTML(email.body_html), !htmlDidFailToLoad {
                    EmailWebView(html: html) {
                        htmlDidFailToLoad = true
                    }
                    .frame(minHeight: 120, alignment: .topLeading)
                } else if let text = nonEmptyBodyText(email.body_text) {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("empty.inbox")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let attachments = email.attachments, !attachments.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("attachments.title")
                            .font(.headline)
                        ForEach(attachments) { attachment in
                            attachmentRow(attachment)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private func attachmentRow(_ attachment: Attachment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "paperclip")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(attachment.content_type ?? "application/octet-stream")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if downloading.contains(attachment.filename) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Menu {
                    Button {
                        Task { await preview(attachment) }
                    } label: {
                        Label("action.preview", systemImage: "eye")
                    }

                    Button {
                        Task { await share(attachment) }
                    } label: {
                        Label("action.share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Sender helpers

    private func senderName(_ email: EmailDetail) -> String {
        email.sender_name ?? email.sender_email ?? "?"
    }

    private func nonEmptyBodyText(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func nonEmptyBodyHTML(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        htmlDidFailToLoad = false
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.email(id: emailID)
        } catch APIClientError.unauthorized {
            await authStore.logout()
        } catch {
            // Leave `detail` nil → fallback state shown above.
        }
    }

    private func toggleStar(_ email: EmailDetail) async {
        let newValue = !email.isStarred
        do {
            let updated = try await APIClient.shared.patchEmail(id: email.id, fields: ["is_starred": newValue ? 1 : 0])
            detail = updated
        } catch APIClientError.unauthorized {
            await authStore.logout()
        } catch {
            // Keep previous visual state on failure.
        }
    }

    private func download(_ attachment: Attachment) async -> URL? {
        if let url = downloaded[attachment.filename] { return url }
        downloading.insert(attachment.filename)
        defer { downloading.remove(attachment.filename) }

        let remote = APIClient.shared.attachmentURL(emailId: emailID, filename: attachment.filename)
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remote)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension((attachment.filename as NSString).pathExtension.isEmpty ? "bin" : (attachment.filename as NSString).pathExtension)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            downloaded[attachment.filename] = destination
            return destination
        } catch APIClientError.unauthorized {
            await authStore.logout()
            return nil
        } catch {
            return nil
        }
    }

    private func preview(_ attachment: Attachment) async {
        guard let url = await download(attachment) else { return }
        previewURL = url
    }

    private func share(_ attachment: Attachment) async {
        guard let url = await download(attachment) else { return }
        shareURL = url
        showShare = true
    }
}

#Preview {
    NavigationStack {
        EmailDetailView(emailID: 1)
            .environment(AuthStore())
    }
}
