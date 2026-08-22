import SwiftUI

/// Address book for the signed-in mailbox. The view deliberately owns its
/// loading state so a failed request never looks like an empty address book.
struct ContactsView: View {
    @Environment(AuthStore.self) private var authStore
    private var client: APIClient { authStore.activeClient }
    @State private var contacts: [Contact] = []
    @State private var starredIDs: Set<Int> = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var editingContact: Contact?
    @State private var showingNewContact = false
    @State private var deletingContact: Contact?
    @State private var requestGeneration = 0

    var body: some View {
        List {
            if isLoading && !hasLoaded {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            } else if let errorMessage, !hasLoaded {
                ContentUnavailableView {
                    Label("contacts.loadFailed", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("action.retry") { Task { await load() } }
                }
                .listRowSeparator(.hidden)
            } else if contacts.isEmpty {
                ContentUnavailableView("contacts.empty", systemImage: "person.2")
                    .listRowSeparator(.hidden)
            } else {
                ForEach(contacts) { contact in
                    ContactRow(contact: contact, isStarred: starredIDs.contains(contact.id)) {
                        Task { await toggleStar(for: contact) }
                    } onEdit: {
                        editingContact = contact
                    } onDelete: {
                        deletingContact = contact
                    }
                }
            }
        }
        .navigationTitle("contacts.title")
        .searchable(text: $searchText, prompt: Text("contacts.search"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewContact = true } label: {
                    Label("action.add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { ContactRulesView() } label: {
                    Label("contacts.rules", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: searchText) { _, _ in Task { await load() } }
        .sheet(isPresented: $showingNewContact) {
            ContactFormView { name, email, notes in
                let token = authStore.sessionToken()
                do {
                    try await token.client.createContact(name: name, email: email, notes: notes)
                } catch {
                    if authStore.isCurrent(token) { throw error }
                    return
                }
                guard authStore.isCurrent(token) else { return }
                await load()
            }
        }
        .sheet(item: $editingContact) { contact in
            ContactFormView(contact: contact) { name, email, notes in
                let token = authStore.sessionToken()
                let updated: Contact
                do {
                    updated = try await token.client.updateContact(id: contact.id,
                        fields: ["name": name, "email": email, "notes": notes])
                } catch {
                    if authStore.isCurrent(token) { throw error }
                    return
                }
                guard authStore.isCurrent(token) else { return }
                if let index = contacts.firstIndex(where: { $0.id == updated.id }) {
                    contacts[index] = updated
                }
            }
        }
        .alert("contacts.deleteTitle", isPresented: Binding(
            get: { deletingContact != nil }, set: { if !$0 { deletingContact = nil } }
        ), presenting: deletingContact) { contact in
            Button("action.delete", role: .destructive) { Task { await delete(contact) } }
            Button("action.cancel", role: .cancel) { }
        } message: { contact in
            Text("contacts.deleteMessage \(contact.email)")
        }
        .alert("contacts.errorTitle", isPresented: Binding(
            get: { errorMessage != nil && hasLoaded }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("action.retry") { Task { await load() } }
            Button("action.cancel", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        guard !isLoading else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let token = authStore.sessionToken()
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await token.client.contacts(q: searchText.isEmpty ? nil : searchText)
            guard generation == requestGeneration, authStore.isCurrent(token) else { return }
            contacts = loaded
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard generation == requestGeneration, authStore.isCurrent(token) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func toggleStar(for contact: Contact) async {
        let token = authStore.sessionToken()
        let shouldStar = !starredIDs.contains(contact.id)
        do {
            _ = try await token.client.updateContact(id: contact.id, fields: ["is_starred": shouldStar])
            guard authStore.isCurrent(token) else { return }
            if shouldStar { starredIDs.insert(contact.id) } else { starredIDs.remove(contact.id) }
        } catch { if authStore.isCurrent(token) { errorMessage = error.localizedDescription } }
    }

    private func delete(_ contact: Contact) async {
        let token = authStore.sessionToken()
        do {
            try await token.client.deleteContact(id: contact.id)
            guard authStore.isCurrent(token) else { return }
            contacts.removeAll { $0.id == contact.id }
            starredIDs.remove(contact.id)
        } catch { if authStore.isCurrent(token) { errorMessage = error.localizedDescription } }
    }
}

private struct ContactRow: View {
    let contact: Contact
    let isStarred: Bool
    let onStar: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: contact.name.isEmpty ? contact.email : contact.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name.isEmpty ? contact.email : contact.name).font(.body.weight(.medium))
                if !contact.name.isEmpty { Text(contact.email).font(.caption).foregroundStyle(.secondary) }
                if let notes = contact.notes, !notes.isEmpty { Text(notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
            }
            Spacer()
            Button(action: onStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isStarred ? "contacts.unstar" : "contacts.star"))
        }
        .padding(.vertical, 5)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) { Label("action.delete", systemImage: "trash") }
            Button(action: onEdit) { Label("action.edit", systemImage: "pencil") }.tint(.blue)
        }
    }
}

struct ContactFormView: View {
    let contact: Contact?
    let onSave: (String, String, String?) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(contact: Contact? = nil, onSave: @escaping (String, String, String?) async throws -> Void) {
        self.contact = contact; self.onSave = onSave
        _name = State(initialValue: contact?.name ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("contacts.details") {
                    TextField("contacts.name", text: $name)
                    TextField("contacts.email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("contacts.notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(contact == nil ? "contacts.add" : "contacts.edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { Task { await save() } }.disabled(isSaving || name.trimmed.isEmpty || email.trimmed.isEmpty)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do { try await onSave(name.trimmed, email.trimmed, notes.trimmed.isEmpty ? nil : notes.trimmed); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
