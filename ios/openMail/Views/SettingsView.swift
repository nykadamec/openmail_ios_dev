import SwiftUI
import Foundation
import LocalAuthentication

/// Account details and sign-out.
struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.openURL) private var openURL

    private let updateService = UpdateService.shared
    @State private var updateState: UpdateState?
    @State private var isCheckingForUpdates = false

    var body: some View {
        NavigationStack {
            List {
                Section("settings.account") {
                    if let user = authStore.user {
                        accountRow(
                            title: "settings.username",
                            value: user.username,
                            icon: "person"
                        )
                        accountRow(
                            title: "settings.email",
                            value: user.email,
                            icon: "envelope"
                        )
                        if let name = user.from_name, !name.isEmpty {
                            accountRow(
                                title: "settings.fromName",
                                value: name,
                                icon: "signature"
                            )
                        }
                    }

                    NavigationLink {
                        ContactsView()
                    } label: {
                        Label("contacts.title", systemImage: "person.2")
                    }

                    NavigationLink {
                        ServerProfilesView()
                    } label: {
                        Label("settings.servers", systemImage: "server.rack")
                    }
                }

                appSettingsSection

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
            .navigationTitle("settings.account")
            .task {
                await checkForUpdates()
            }
        }
    }

    private var appSettingsSection: some View {
        Section("settings.app") {
            HStack(spacing: 12) {
                Image(systemName: "app.badge")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.appVersion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(updateService.currentVersion) (\(updateService.currentBuild))")
                        .font(.body)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("settings.appVersionAccessibility"))
            .accessibilityValue(Text("\(updateService.currentVersion), \(updateService.currentBuild)"))

            if !UpdateService.currentReleaseNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Co je nového v této verzi")
                        .font(.subheadline.weight(.semibold))

                    ForEach(Array(UpdateService.currentReleaseNotes.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(entry)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .contain)
            }

            updateStatus

            if let lastCheckDate = updateService.lastCheckDate {
                Text("settings.lastChecked \(lastCheckDate, format: .dateTime.day().month().year().hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let releaseURL = updateService.releaseURL,
               case .available(let manifest) = updateState {
                Button {
                    openURL(releaseURL)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.openRelease")
                                .font(.body.weight(.medium))
                            Text(manifest.version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("settings.openReleaseAccessibility"))
                .accessibilityHint(Text("settings.openReleaseHint"))

                if !manifest.changelog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.changelog")
                            .font(.subheadline.weight(.semibold))

                        ForEach(Array(manifest.changelog.enumerated()), id: \.offset) { _, entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(entry)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .contain)
                }
            }

            Button {
                Task { await checkForUpdates() }
            } label: {
                HStack {
                    Label(
                        isCheckingForUpdates ? "settings.checkingForUpdates" : "settings.checkForUpdates",
                        systemImage: isCheckingForUpdates ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                    )
                    Spacer()
                    if isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCheckingForUpdates)
            .accessibilityLabel(Text("settings.checkForUpdatesAccessibility"))
            .accessibilityHint(Text("settings.checkForUpdatesHint"))
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateState {
        case .available:
            Label("settings.updateAvailable", systemImage: "sparkles")
                .foregroundStyle(.tint)
        case .upToDate:
            Label("settings.upToDate", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .invalidManifest:
            Label("settings.invalidUpdateManifest", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .networkError, .unavailable:
            Label("settings.updateCheckFailed", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        let state = await updateService.checkForUpdate()
        updateState = state
        isCheckingForUpdates = false
    }

    private func accountRow(title: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environment(AuthStore())
}

// MARK: - Server profiles

/// A locally managed list of endpoints.  Authentication is deliberately kept
/// outside this view: changing an endpoint always goes through AuthStore so
/// its cookie jar and login state are invalidated together.
struct ServerProfilesView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var profiles: [ServerProfile] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isAuthorized = false
    @State private var showingEditor = false
    @State private var editingProfile: ServerProfile?
    @State private var deletingProfile: ServerProfile?
    @State private var switchingProfileID: UUID?
    @State private var connectivity: [UUID: ServerConnectivity] = [:]

    private let defaultProfileID = ServerProfile.defaultPublicProfile.id

    var body: some View {
        Group {
            if isAuthorized {
                profilesList
            } else {
                ServerProtectionView {
                    isAuthorized = true
                }
            }
        }
        .navigationTitle("settings.servers")
        .task {
            guard !isAuthorized else { return }
            await loadProfiles()
        }
        .sheet(isPresented: $showingEditor) {
            ServerEditorView { profile in
                try save(profile)
            }
        }
        .sheet(item: $editingProfile) { profile in
            ServerEditorView(profile: profile) { updated in
                try save(updated)
            }
        }
        .alert("settings.serverDeleteTitle", isPresented: Binding(
            get: { deletingProfile != nil },
            set: { if !$0 { deletingProfile = nil } }
        ), presenting: deletingProfile) { profile in
            Button("action.delete", role: .destructive) {
                Task { await delete(profile) }
            }
            Button("action.cancel", role: .cancel) { }
        } message: { profile in
            Text("settings.serverDeleteMessage \(profile.name)")
        }
        .alert("settings.serverErrorTitle", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("action.retry") { Task { await loadProfiles() } }
            Button("action.cancel", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private var profilesList: some View {
        List {
            Section {
                Text("settings.serversExplanation")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            if isLoading && profiles.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if profiles.isEmpty {
                ContentUnavailableView("settings.serversEmpty", systemImage: "server.rack")
                    .listRowSeparator(.hidden)
            } else {
                Section("settings.savedServers") {
                    ForEach(profiles) { profile in
                        ServerProfileRow(
                            profile: profile,
                            isActive: profile.id == authStore.activeProfile.id,
                            connectivity: connectivity[profile.id],
                            isSwitching: switchingProfileID == profile.id,
                            canEdit: profile.id != defaultProfileID,
                            canDelete: profile.id != defaultProfileID,
                            onSelect: { select(profile) },
                            onEdit: { editingProfile = profile },
                            onDelete: { deletingProfile = profile },
                            onRetry: { Task { await checkConnectivity(for: profile) } }
                        )
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Label("action.add", systemImage: "plus")
                }
                .accessibilityLabel(Text("settings.addServer"))
            }
        }
        .refreshable { await loadProfiles() }
    }

    private func loadProfiles() async {
        guard !isLoading || profiles.isEmpty else { return }
        isLoading = true
        loadError = nil
        // ServerProfileStore validates and persists the local payload.  Keep a
        // copy in view state because the store intentionally is not observable.
        var loadedProfiles = authStore.profileStore.profiles
        if !loadedProfiles.contains(where: { $0.id == defaultProfileID }) {
            loadedProfiles.insert(.defaultPublicProfile, at: 0)
            do {
                try authStore.profileStore.setProfiles(loadedProfiles)
            } catch {
                isLoading = false
                loadError = String(localized: "settings.serversLoadFailed")
                return
            }
        }
        profiles = authStore.profileStore.profiles
        isLoading = false
        guard !profiles.isEmpty else {
            loadError = String(localized: "settings.serversLoadFailed")
            return
        }

        await withTaskGroup(of: (UUID, ServerConnectivity).self) { group in
            for profile in profiles {
                group.addTask { (profile.id, await ServerConnectivity.check(profile: profile)) }
            }
            for await (id, result) in group {
                connectivity[id] = result
            }
        }
    }

    private func checkConnectivity(for profile: ServerProfile) async {
        connectivity[profile.id] = .checking
        connectivity[profile.id] = await ServerConnectivity.check(profile: profile)
    }

    private func select(_ profile: ServerProfile) {
        guard profile.id != authStore.activeProfile.id, switchingProfileID == nil else { return }
        switchingProfileID = profile.id
        Task {
            await authStore.switchProfile(id: profile.id)
            switchingProfileID = nil
        }
    }

    private func save(_ profile: ServerProfile) throws {
        let previous = profiles.first(where: { $0.id == profile.id })
        let wasActive = profile.id == authStore.activeProfile.id
        let endpointChanged = previous.map {
            $0.scheme != profile.scheme || $0.host != profile.host || $0.port != profile.port
        } ?? false
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) {
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        try authStore.profileStore.setProfiles(updated)
        profiles = authStore.profileStore.profiles
        connectivity[profile.id] = .checking
        Task { await checkConnectivity(for: profile) }

        // AuthStore intentionally has no in-place client mutation.  Recreate
        // the active client through its public switch contract when an active
        // profile's endpoint changes, ending at the edited profile and forcing
        // the expected fresh login.
        if wasActive && endpointChanged {
            Task {
                await authStore.switchProfile(id: defaultProfileID)
                await authStore.switchProfile(id: profile.id)
            }
        }
    }

    private func delete(_ profile: ServerProfile) async {
        guard profile.id != defaultProfileID else { return }
        let wasActive = profile.id == authStore.activeProfile.id
        var updated = profiles
        updated.removeAll { $0.id == profile.id }

        do {
            try authStore.profileStore.setProfiles(updated)
            profiles = authStore.profileStore.profiles
            connectivity.removeValue(forKey: profile.id)

            // AuthStore owns the active client.  Once the active profile is
            // removed, switch to the built-in profile to invalidate the old
            // session and return the user to login.
            if wasActive {
                await authStore.switchProfile(id: defaultProfileID)
            }
        } catch {
            loadError = String(localized: "settings.serverSaveFailed")
        }
    }
}

private struct ServerProfileRow: View {
    let profile: ServerProfile
    let isActive: Bool
    let connectivity: ServerConnectivity?
    let isSwitching: Bool
    let canEdit: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                    if isActive {
                        Text("settings.activeServer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                Text(profile.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusView
            }
            Spacer(minLength: 4)
            if isSwitching {
                ProgressView().controlSize(.small)
            } else if !isActive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .onTapGesture { onSelect() }
        .accessibilityAddTraits(.isButton)
        .disabled(isSwitching)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("action.delete", systemImage: "trash")
                }
            }
            if canEdit {
                Button(action: onEdit) {
                    Label("action.edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if canEdit {
                Button(action: onEdit) { Label("action.edit", systemImage: "pencil") }
            }
            if canDelete {
                Button(role: .destructive, action: onDelete) { Label("action.delete", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(isActive ? "settings.activeServerHint" : "settings.switchServerHint"))
    }

    @ViewBuilder
    private var statusView: some View {
        switch connectivity {
        case .checking:
            Label("settings.serverChecking", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .online(let code):
            Label("settings.serverOnline \(code)", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .offline:
            Button(action: onRetry) {
                Label("settings.serverOffline", systemImage: "wifi.exclamationmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}

private enum ServerConnectivity: Equatable {
    case checking
    case online(Int)
    case offline

    static func check(profile: ServerProfile) async -> ServerConnectivity {
        var request = URLRequest(url: profile.baseURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.httpShouldHandleCookies = false

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .offline }
            // A 401/403 is still a healthy, reachable endpoint; the session
            // must not be sent just to determine connectivity.
            return (100..<500).contains(http.statusCode) ? .online(http.statusCode) : .offline
        } catch {
            return .offline
        }
    }
}

struct ServerEditorView: View {
    let profile: ServerProfile?
    let onSave: (ServerProfile) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var scheme: ServerProfile.Scheme
    @State private var host: String
    @State private var port: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(profile: ServerProfile? = nil, onSave: @escaping (ServerProfile) throws -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _scheme = State(initialValue: profile?.scheme ?? .https)
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: profile?.port.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.serverDetails") {
                    TextField("settings.serverName", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("settings.serverScheme", selection: $scheme) {
                        Text("HTTPS").tag(ServerProfile.Scheme.https)
                        Text("HTTP").tag(ServerProfile.Scheme.http)
                    }
                    .pickerStyle(.segmented)
                    TextField("settings.serverHost", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("settings.serverPortOptional", text: $port)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("settings.serverSecurityNote")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(profile == nil ? "settings.addServer" : "settings.editServer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(isSaving || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSaving { ProgressView().controlSize(.large) }
            }
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portValue = trimmedPort.isEmpty ? nil : Int(trimmedPort)
        if !trimmedPort.isEmpty && portValue == nil {
            errorMessage = String(localized: "settings.serverInvalidPort")
            return
        }

        do {
            let saved = try ServerProfile(
                id: profile?.id ?? UUID(),
                name: name,
                scheme: scheme,
                host: host,
                port: portValue
            )
            try onSave(saved)
            dismiss()
        } catch let validation as ServerProfile.ValidationError {
            errorMessage = validation.localizedMessage
        } catch {
            errorMessage = String(localized: "settings.serverSaveFailed")
        }
    }
}

private extension ServerProfile.ValidationError {
    var localizedMessage: String {
        switch self {
        case .emptyHost: return String(localized: "settings.serverEmptyHost")
        case .invalidScheme: return String(localized: "settings.serverInvalidScheme")
        case .invalidHost: return String(localized: "settings.serverInvalidHost")
        case .invalidPort: return String(localized: "settings.serverInvalidPort")
        case .forbiddenURLComponents: return String(localized: "settings.serverForbiddenURL")
        }
    }
}

private struct ServerProtectionView: View {
    let onUnlock: () -> Void

    @State private var phase: ProtectionPhase = .checking
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    private let pinStore = KeychainStore(service: "nykadamec.openmail.server-protection", account: "profiles-pin-v1")

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: phase == .createPin ? "lock.badge.plus" : "faceid")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text(phase.title)
                    .font(.title3.weight(.semibold))
                Text(phase.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch phase {
            case .checking:
                ProgressView()
                    .controlSize(.large)
            case .createPin:
                pinFields(showConfirmation: true)
                Button("settings.savePin") { savePin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !validPin(pin) || pin != confirmation)
            case .unlock:
                pinFields(showConfirmation: false)
                Button("settings.unlockWithPin") { unlockWithPin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !validPin(pin))
                Button {
                    Task { await authenticateWithFaceID() }
                } label: {
                    Label("settings.useFaceID", systemImage: "faceid")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            await prepareProtection()
        }
    }

    @ViewBuilder
    private func pinFields(showConfirmation: Bool) -> some View {
        VStack(spacing: 12) {
            SecureField("settings.pin", text: $pin)
                .textContentType(.newPassword)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            if showConfirmation {
                SecureField("settings.confirmPin", text: $confirmation)
                    .textContentType(.newPassword)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: pin) { _, value in
            pin = String(value.filter(\.isNumber).prefix(8))
        }
        .onChange(of: confirmation) { _, value in
            confirmation = String(value.filter(\.isNumber).prefix(8))
        }
    }

    private func prepareProtection() async {
        guard phase == .checking else { return }
        do {
            if try pinStore.read() == nil {
                phase = .createPin
            } else {
                phase = .unlock
                await authenticateWithFaceID()
            }
        } catch {
            phase = .createPin
            errorMessage = String(localized: "settings.protectionUnavailable")
        }
    }

    private func authenticateWithFaceID() async {
        let context = LAContext()
        var authenticationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authenticationError) else {
            errorMessage = String(localized: "settings.faceIDUnavailable")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "settings.faceIDReason")
            )
            if success { onUnlock() }
        } catch {
            // A cancelled or unavailable biometric prompt is not a hard
            // failure; the PIN control remains visible as the fallback.
            errorMessage = String(localized: "settings.faceIDFallback")
        }
    }

    private func savePin() {
        guard validPin(pin), pin == confirmation else {
            errorMessage = String(localized: "settings.pinMismatch")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try pinStore.save(pin)
            onUnlock()
        } catch {
            errorMessage = String(localized: "settings.pinSaveFailed")
        }
    }

    private func unlockWithPin() {
        guard validPin(pin) else { return }
        do {
            if try pinStore.read() == pin {
                onUnlock()
                return
            }
            errorMessage = String(localized: "settings.pinIncorrect")
        } catch {
            errorMessage = String(localized: "settings.pinReadFailed")
        }
    }

    private func validPin(_ value: String) -> Bool {
        (4...8).contains(value.count) && value.allSatisfy(\.isNumber)
    }
}

private enum ProtectionPhase: Equatable {
    case checking
    case createPin
    case unlock

    var title: LocalizedStringKey {
        switch self {
        case .checking: return "settings.protectionChecking"
        case .createPin: return "settings.createPinTitle"
        case .unlock: return "settings.protectionTitle"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .checking: return "settings.protectionChecking"
        case .createPin: return "settings.createPinExplanation"
        case .unlock: return "settings.protectionExplanation"
        }
    }
}
