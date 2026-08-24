import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// One attachment attached to the outgoing message. Converted to
/// `APIClient.SendAttachment` right before the send call.
struct ComposerAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
    let contentType: String
}

/// New-message composer: recipients, subject, body and file/photo
/// attachments. Minimalist iOS Mail style with chips autocomplete.
struct ComposerView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    // Recipients as chips + raw input
    @State private var recipients: [Contact] = []
    @State private var toInput = ""
    @State private var allContacts: [Contact] = []

    @State private var subject = ""
    @State private var bodyText = ""
    @State private var attachments: [ComposerAttachment] = []

    @State private var isLoading = false
    @State private var showFileImporter = false
    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showClearConfirm = false

    private var canSend: Bool {
        let hasRecipient = !recipients.isEmpty || !toInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasRecipient && !isLoading
    }

    /// True if there is any in-progress content. Used by Cancel to decide
    /// whether a confirmation alert is necessary before discarding the draft.
    private var hasContent: Bool {
        !recipients.isEmpty
            || !toInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.isEmpty
            || !attachments.isEmpty
    }

    private var filteredContacts: [Contact] {
        let query = toInput.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let normalizedQuery = normalized(query)
        return allContacts.filter { contact in
            guard !recipients.contains(where: { $0.id == contact.id || $0.email.lowercased() == contact.email.lowercased() }) else { return false }
            let nameNorm = normalized(contact.name)
            let emailNorm = normalized(contact.email)
            return nameNorm.contains(normalizedQuery) || emailNorm.contains(normalizedQuery)
        }
        .prefix(5)
        .map { $0 }
    }

    private func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    private var composedTo: String {
        let parts = recipients.map(\.email)
        let trimmed = toInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return parts.joined(separator: ", ")
        } else {
            if parts.isEmpty { return trimmed }
            return parts.joined(separator: ", ") + ", " + trimmed
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            recipientRow
            if !filteredContacts.isEmpty { suggestedCard.padding(.horizontal, 16) }
            Divider()
            HStack(spacing: 12) {
                Text("composer.subject").foregroundStyle(.secondary).font(.subheadline).frame(width: 58, alignment: .leading)
                TextField("", text: $subject, prompt: Text("composer.subject").foregroundStyle(.placeholder))
                    .font(.body).textInputAutocapitalization(.sentences)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty { Text("composer.body").foregroundStyle(.placeholder).font(.body).padding(.top, 10).padding(.leading, 5).allowsHitTesting(false) }
                TextEditor(text: $bodyText).font(.body).scrollContentBackground(.hidden).background(.clear)
                    .autocorrectionDisabled(false).textInputAutocapitalization(.sentences).keyboardType(.default)
            }
            .padding(.horizontal, 11).padding(.vertical, 8).frame(maxHeight: .infinity)
            if !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip").foregroundStyle(.secondary)
                            Text(attachment.filename).lineLimit(1).font(.subheadline)
                            Spacer()
                            Button { remove(attachment) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain).accessibilityLabel(Text("action.removeAttachment"))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
            }
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("action.compose").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("action.cancel") {
                    if hasContent {
                        showClearConfirm = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await send() } } label: { if isLoading { ProgressView() } else { Image(systemName: "paperplane.fill") } }
                    .disabled(!canSend).accessibilityLabel(Text("action.send"))
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button { showFileImporter = true } label: { Image(systemName: "paperclip") }
                Button { showPhotosPicker = true } label: { Image(systemName: "photo") }
            }
        }
        .task { await loadContacts() }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach { addFile(at: $0) } }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItems, maxSelectionCount: 6, matching: .images)
        .onChange(of: photosPickerItems) { Task { await loadPhotos() } }
        .alert(alertTitle, isPresented: $showAlert) { Button("action.ok", role: .cancel) {} } message: { Text(alertMessage) }
        .confirmationDialog("composer.discardTitle", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("composer.discard", role: .destructive) { clear(); dismiss() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("composer.discardMessage")
        }
    }

    // MARK: - Recipient row

    private var recipientRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("composer.to")
                .foregroundStyle(Color(.secondaryLabel))
                .font(.system(size: 15))
                .frame(width: 38, alignment: .leading)

            // Chips + input wrapping via FlowLayout
            FlowLayout(spacing: 6) {
                ForEach(recipients) { contact in
                    chip(for: contact)
                }
                TextField("", text: $toInput, prompt: Text("composer.toPlaceholder").foregroundStyle(Color(.placeholderText)))
                    .font(.system(size: 15))
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .frame(minWidth: 120)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func chip(for contact: Contact) -> some View {
        HStack(spacing: 6) {
            // avatar
            ZStack {
                Circle()
                    .fill(Color(red: 0, green: 122/255, blue: 1))
                    .frame(width: 22, height: 22)
                Text(initial(for: contact))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(contact.name.isEmpty ? contact.email : contact.name)
                .font(.system(size: 14))
                .lineLimit(1)
                .foregroundStyle(Color(.label))
            Button {
                recipients.removeAll { $0.id == contact.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func initial(for contact: Contact) -> String {
        let source = contact.name.isEmpty ? contact.email : contact.name
        return String(source.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    // MARK: - Suggested card

    private var suggestedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                Button {
                    addRecipient(contact)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0, green: 122/255, blue: 1))
                                    .frame(width: 28, height: 28)
                            Text(initial(for: contact))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name.isEmpty ? contact.email : contact.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(.label))
                                .lineLimit(1)
                            Text(contact.email)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0, green: 122/255, blue: 1))
                            .frame(width: 28, height: 28)
                            .background(Color(red: 229/255, green: 240/255, blue: 1))
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < filteredContacts.count - 1 {
                    Divider()
                        .padding(.leading, 56)
                        .background(Color(red: 229/255, green: 229/255, blue: 234/255))
                }
            }
        }
        .background(Color(.systemBackground))
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Contacts loading

    private func loadContacts() async {
        let token = authStore.sessionToken()
        do {
            let contacts = try await token.client.listContacts()
            allContacts = contacts
        } catch {
            // Fallback try without query alias
            do {
                let contacts = try await token.client.contacts()
                allContacts = contacts
            } catch {
                // keep empty
            }
        }
    }

    private func addRecipient(_ contact: Contact) {
        guard !recipients.contains(where: { $0.id == contact.id }) else {
            toInput = ""
            return
        }
        recipients.append(contact)
        toInput = ""
    }

    // Raw text in toInput is sent directly via composedTo; no chip conversion needed.

    // MARK: - Attachments

    private func addFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return }
        let contentType = UTType(filenameExtension: url.pathExtension)?
            .preferredMIMEType ?? "application/octet-stream"
        attachments.append(
            ComposerAttachment(
                filename: url.lastPathComponent,
                data: data,
                contentType: contentType
            )
        )
    }

    private func loadPhotos() async {
        let items = photosPickerItems
        photosPickerItems = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let name = "image-\(UUID().uuidString.prefix(6)).\(ext)"
            attachments.append(
                ComposerAttachment(
                    filename: name,
                    data: data,
                    contentType: type?.preferredMIMEType ?? "image/jpeg"
                )
            )
        }
    }

    private func remove(_ attachment: ComposerAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Send

    private func send() async {
        guard canSend else { return }
        let token = authStore.sessionToken()
        isLoading = true
        defer { isLoading = false }

        let payload = attachments.map {
            APIClient.SendAttachment(filename: $0.filename, data: $0.data, contentType: $0.contentType)
        }

        do {
            _ = try await token.client.send(
                to: composedTo,
                subject: subject,
                body: bodyText,
                attachments: payload
            )
            guard authStore.isCurrent(token) else { return }
            alertTitle = String(localized: "composer.sentTitle")
            alertMessage = String(localized: "composer.sentMessage")
            showAlert = true
            clear()
        } catch APIClientError.unauthorized {
            if authStore.isCurrent(token) { await authStore.logout() }
        } catch {
            guard authStore.isCurrent(token) else { return }
            alertTitle = String(localized: "errors.generic")
            alertMessage = String(localized: "composer.sendFailed")
            showAlert = true
        }
    }

    private func clear() {
        recipients = []
        toInput = ""
        subject = ""
        bodyText = ""
        attachments = []
    }
}

// MARK: - FlowLayout (wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

#Preview {
    ComposerView()
        .environment(AuthStore())
}
