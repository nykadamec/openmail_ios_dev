import SwiftUI

struct ContactRulesView: View {
    @Environment(AuthStore.self) private var authStore
    private var client: APIClient { authStore.activeClient }
    @State private var rules: [ContactRule] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var editingRule: ContactRule?
    @State private var isAdding = false
    @State private var deletingRule: ContactRule?
    @State private var requestGeneration = 0

    var body: some View {
        List {
            Section {
                Text("contacts.rulesExplanation").font(.footnote).foregroundStyle(.secondary)
            }
            if isLoading && !hasLoaded { HStack { Spacer(); ProgressView(); Spacer() } }
            else if let errorMessage, !hasLoaded {
                ContentUnavailableView { Label("contacts.loadFailed", systemImage: "wifi.exclamationmark") } description: { Text(errorMessage) } actions: { Button("action.retry") { Task { await load() } } }
            } else if rules.isEmpty { ContentUnavailableView("contacts.rulesEmpty", systemImage: "line.3.horizontal.decrease.circle") }
            else {
                ForEach(rules) { rule in
                    HStack {
                        Image(systemName: rule.isStarred ? "star.fill" : "star").foregroundStyle(rule.isStarred ? .yellow : .secondary)
                        VStack(alignment: .leading) { Text("@\(rule.domain)").font(.body.weight(.medium)); Text("contacts.newEmailsOnly").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); if !rule.enabled { Text("contacts.disabled").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deletingRule = rule } label: { Label("action.delete", systemImage: "trash") }
                        Button { editingRule = rule } label: { Label("action.edit", systemImage: "pencil") }.tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("contacts.rules")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { isAdding = true } label: { Label("action.add", systemImage: "plus") } } }
        .refreshable { await load() }.task { await load() }
        .sheet(isPresented: $isAdding) { RuleFormView { domain, starred in let token = authStore.sessionToken(); do { try await token.client.createContactRule(domain: domain, isStarred: starred) } catch { if authStore.isCurrent(token) { throw error }; return }; guard authStore.isCurrent(token) else { return }; await load() } }
        .sheet(item: $editingRule) { rule in RuleFormView(rule: rule) { domain, starred in let token = authStore.sessionToken(); let updated: ContactRule; do { updated = try await token.client.updateContactRule(id: rule.id, fields: ["domain": domain, "is_starred": starred]) } catch { if authStore.isCurrent(token) { throw error }; return }; guard authStore.isCurrent(token) else { return }; if let i = rules.firstIndex(where: { $0.id == updated.id }) { rules[i] = updated } } }
        .alert("contacts.deleteTitle", isPresented: Binding(get: { deletingRule != nil }, set: { if !$0 { deletingRule = nil } }), presenting: deletingRule) { rule in Button("action.delete", role: .destructive) { Task { await delete(rule) } }; Button("action.cancel", role: .cancel) {} } message: { rule in Text("contacts.deleteRuleMessage \(rule.domain)") }
        .alert("contacts.errorTitle", isPresented: Binding(get: { errorMessage != nil && hasLoaded }, set: { if !$0 { errorMessage = nil } })) { Button("action.retry") { Task { await load() } }; Button("action.cancel", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func load() async { guard !isLoading else { return }; requestGeneration += 1; let generation = requestGeneration; let token = authStore.sessionToken(); isLoading = true; defer { isLoading = false }; do { let loaded = try await token.client.contactRules(); guard generation == requestGeneration, authStore.isCurrent(token) else { return }; rules = loaded; hasLoaded = true; errorMessage = nil } catch { guard generation == requestGeneration, authStore.isCurrent(token) else { return }; errorMessage = error.localizedDescription } }
    private func delete(_ rule: ContactRule) async { let token = authStore.sessionToken(); do { try await token.client.deleteContactRule(id: rule.id); guard authStore.isCurrent(token) else { return }; rules.removeAll { $0.id == rule.id } } catch { if authStore.isCurrent(token) { errorMessage = error.localizedDescription } } }
}

private struct RuleFormView: View {
    let rule: ContactRule?
    let onSave: (String, Bool) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var domain: String
    @State private var isStarred: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(rule: ContactRule? = nil, onSave: @escaping (String, Bool) async throws -> Void) { self.rule = rule; self.onSave = onSave; _domain = State(initialValue: rule?.domain ?? ""); _isStarred = State(initialValue: rule?.isStarred ?? true) }
    var body: some View { NavigationStack { Form { Section("contacts.ruleDetails") { TextField("contacts.domain", text: $domain).textInputAutocapitalization(.never).autocorrectionDisabled(); Toggle("contacts.starNew", isOn: $isStarred) }; if let errorMessage { Text(errorMessage).foregroundStyle(.red) } }.navigationTitle(rule == nil ? "contacts.addRule" : "contacts.editRule").toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("action.save") { Task { await save() } }.disabled(isSaving || domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
    private func save() async { isSaving = true; defer { isSaving = false }; do { try await onSave(domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: ""), isStarred); dismiss() } catch { errorMessage = error.localizedDescription } }
}
