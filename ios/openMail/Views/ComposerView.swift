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
/// attachments. Works both as a tab and as a sheet.
struct ComposerView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var to = ""
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

    private var canSend: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("composer.to", text: $to)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)

                    TextField("composer.subject", text: $subject)
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("composer.body")
                                .foregroundStyle(Color(.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 180)
                    }
                }

                Section("composer.attachments") {
                    if attachments.isEmpty {
                        Text("composer.noAttachments")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(attachments) { attachment in
                            HStack {
                                Image(systemName: "paperclip")
                                    .foregroundStyle(.secondary)
                                Text(attachment.filename)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    remove(attachment)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color(.tertiaryLabel))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("action.removeAttachment")
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("composer.addFile", systemImage: "folder")
                        }

                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("composer.addPhotos", systemImage: "photo")
                        }
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Label("action.send", systemImage: "paperplane.fill")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle("action.compose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !attachments.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            attachments.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .accessibilityLabel("composer.clearAttachments")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        addFile(at: url)
                    }
                }
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $photosPickerItems,
                maxSelectionCount: 6,
                matching: .images
            )
            .onChange(of: photosPickerItems) {
                Task { await loadPhotos() }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

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
        isLoading = true
        defer { isLoading = false }

        let payload = attachments.map {
            APIClient.SendAttachment(filename: $0.filename, data: $0.data, contentType: $0.contentType)
        }

        do {
            _ = try await APIClient.shared.send(
                to: to.trimmingCharacters(in: .whitespaces),
                subject: subject,
                body: bodyText,
                attachments: payload
            )
            alertTitle = String(localized: "composer.sentTitle")
            alertMessage = String(localized: "composer.sentMessage")
            showAlert = true
            clear()
        } catch APIClientError.unauthorized {
            await authStore.logout()
        } catch {
            alertTitle = String(localized: "errors.generic")
            alertMessage = String(localized: "composer.sendFailed")
            showAlert = true
        }
    }

    private func clear() {
        to = ""
        subject = ""
        bodyText = ""
        attachments = []
    }
}

#Preview {
    ComposerView()
        .environment(AuthStore())
}