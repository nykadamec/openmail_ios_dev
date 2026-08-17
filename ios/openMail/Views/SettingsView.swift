import SwiftUI

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
