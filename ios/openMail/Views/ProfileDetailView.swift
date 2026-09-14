import SwiftUI

/// Account detail reachable from the Settings profile card.
///
/// Editable profile form (first name, last name, phone) following the
/// `ServerEditorView` / `ContactFormView` pattern, plus the sign-out
/// affordance. Saving goes through `APIClient.updateProfile` and refreshes
/// the cached user in `AuthStore` so the Settings card updates on return.
struct ProfileDetailView: View {
    @Environment(AuthStore.self) private var authStore

    let user: User

    @State private var firstName: String
    @State private var lastName: String
    @State private var phone: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var justSaved = false

    init(user: User) {
        self.user = user
        _firstName = State(initialValue: user.first_name ?? "")
        _lastName = State(initialValue: user.last_name ?? "")
        _phone = State(initialValue: user.phone ?? "")
    }

    /// The freshest known user — the stored one after a save, otherwise the
    /// snapshot this view was opened with.
    private var effectiveUser: User { authStore.user ?? user }

    private var storedFirstName: String { effectiveUser.first_name ?? "" }
    private var storedLastName: String { effectiveUser.last_name ?? "" }
    private var storedPhone: String { effectiveUser.phone ?? "" }

    private var isModified: Bool {
        firstName.trimmed != storedFirstName.trimmed
            || lastName.trimmed != storedLastName.trimmed
            || phone.trimmed != storedPhone.trimmed
    }

    var body: some View {
        let displayUser = effectiveUser
        List {
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0, green: 122.0/255.0, blue: 1))
                            .frame(width: 88, height: 88)
                        Text(String((displayUser.fullName ?? displayUser.username).prefix(1).uppercased()))
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(displayUser.fullName ?? displayUser.username)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(displayUser.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color(.systemBackground))
            }

            Section("settings.profile") {
                TextField("profile.firstName", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                TextField("profile.lastName", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                TextField("profile.phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if justSaved {
                Section {
                    Label("profile.saved", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await authStore.logout() }
                } label: {
                    Label("action.signout", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle("settings.profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { resetFields() }
                    .disabled(isSaving || !isModified)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("action.save") { Task { await save() } }
                    .disabled(isSaving || !isModified)
            }
        }
        .overlay {
            if isSaving { ProgressView().controlSize(.large) }
        }
        .onChange(of: firstName) { justSaved = false }
        .onChange(of: lastName) { justSaved = false }
        .onChange(of: phone) { justSaved = false }
    }

    private func resetFields() {
        firstName = storedFirstName
        lastName = storedLastName
        phone = storedPhone
        errorMessage = nil
        justSaved = false
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        justSaved = false
        do {
            let updated = try await authStore.activeClient.updateProfile(
                firstName: firstName,
                lastName: lastName,
                phone: phone
            )
            authStore.updateStoredUser(updated)
            firstName = updated.first_name ?? ""
            lastName = updated.last_name ?? ""
            phone = updated.phone ?? ""
            justSaved = true
        } catch let apiError as APIClientError {
            // Server validation messages are specific; anything else falls
            // back to the generic save failure.
            if case .server(let message) = apiError {
                errorMessage = message
            } else {
                errorMessage = apiError.errorDescription ?? String(localized: "profile.error")
            }
        } catch {
            errorMessage = String(localized: "profile.error")
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    NavigationStack {
        ProfileDetailView(user: ProfileDetailView.previewUser)
    }
    .environment(AuthStore())
}

extension ProfileDetailView {
    static var previewUser: User {
        let json = #"{"id":1,"username":"dominik","email":"dominik@adamec.pro","first_name":"Dominik","last_name":"Adamec","phone":"+420 123 456 789"}"#
        let data = Data(json.utf8)
        return try! JSONDecoder().decode(User.self, from: data)
    }
}
