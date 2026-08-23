import Foundation

/// Public metadata published with each device build.  URLs remain strings so
/// that malformed manifests can be rejected before they are opened.
struct UpdateManifest: Codable, Equatable {
    let version: String
    let build: Int
    let title: String
    let releaseURL: String
    let ipaURL: String
    let minimumSupportedVersion: String
    let changelog: [String]
    let history: [UpdateHistoryEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        build = try container.decode(Int.self, forKey: .build)
        title = try container.decode(String.self, forKey: .title)
        releaseURL = try container.decode(String.self, forKey: .releaseURL)
        ipaURL = try container.decode(String.self, forKey: .ipaURL)
        minimumSupportedVersion = try container.decode(String.self, forKey: .minimumSupportedVersion)
        changelog = try container.decodeIfPresent([String].self, forKey: .changelog) ?? []
        history = try container.decodeIfPresent([UpdateHistoryEntry].self, forKey: .history) ?? []
    }
}

/// One entry in the version history, sorted newest first.  Version + build
/// identify the release uniquely; `changelog` lists the user-visible bullets.
struct UpdateHistoryEntry: Codable, Equatable, Identifiable {
    let version: String
    let build: Int
    let changelog: [String]

    var id: String { "\(version)-\(build)" }
}

enum UpdateState: Equatable {
    case available(UpdateManifest)
    case upToDate(UpdateManifest)
    case unavailable
    case invalidManifest
    case networkError

    var manifest: UpdateManifest? {
        switch self {
        case .available(let value), .upToDate(let value): return value
        default: return nil
        }
    }
}

/// Fetches the signed-by-location (public raw GitHub) update metadata.
/// This service only reports a release URL; it never downloads or installs an IPA.
final class UpdateService {
    static let shared = UpdateService()

    /// Release notes bundled with the currently installed 0.0.22 (build 22)
    /// release.  These remain available when the remote update manifest cannot
    /// be reached, and can be displayed directly by SettingsView.
    /// Values are localization keys (update.changelog.current.*), resolved in SettingsView via LocalizedStringKey.
    static let currentChangelog: [String] = [
        "update.changelog.current.item1",
        "update.changelog.current.item2",
        "update.changelog.current.item3",
        "update.changelog.current.item4",
        "update.changelog.current.item5"
    ]

    /// Readable alias for callers that refer to the bundled changelog as
    /// release notes.
    static var currentReleaseNotes: [String] { currentChangelog }

    /// Instance-level access for views that already hold the shared service.
    var bundledReleaseNotes: [String] { Self.currentChangelog }

    /// Bundled fallback for the version history dropdown in Settings.  Each
    /// entry identifies one release that shipped before `currentChangelog`.
    /// When the remote manifest supplies its own `history`, the runtime
    /// merger in `mergedHistory()` uses it instead.
    /// Changelog arrays contain localization keys (update.history.*), not literal text.
    static let bundledChangelogHistory: [UpdateHistoryEntry] = [
        UpdateHistoryEntry(version: "0.0.20", build: 20, changelog: [
            "update.history.0_0_20.item1",
            "update.history.0_0_20.item2",
            "update.history.0_0_20.item3",
            "update.history.0_0_20.item4",
            "update.history.0_0_20.item5",
            "update.history.0_0_20.item6",
            "update.history.0_0_20.item7",
            "update.history.0_0_20.item8"
        ]),
        UpdateHistoryEntry(version: "0.0.19", build: 19, changelog: [
            "update.history.0_0_19.item1",
            "update.history.0_0_19.item2",
            "update.history.0_0_19.item3",
            "update.history.0_0_19.item4",
            "update.history.0_0_19.item5",
            "update.history.0_0_19.item6"
        ]),
        UpdateHistoryEntry(version: "0.0.18", build: 18, changelog: [
            "update.history.0_0_18.item1",
            "update.history.0_0_18.item2",
            "update.history.0_0_18.item3",
            "update.history.0_0_18.item4",
            "update.history.0_0_18.item5"
        ]),
        UpdateHistoryEntry(version: "0.0.17", build: 17, changelog: [
            "update.history.0_0_17.item1",
            "update.history.0_0_17.item2",
            "update.history.0_0_17.item3",
            "update.history.0_0_17.item4",
            "update.history.0_0_17.item5"
        ]),
        UpdateHistoryEntry(version: "0.0.16", build: 16, changelog: [
            "update.history.0_0_16.item1",
            "update.history.0_0_16.item2",
            "update.history.0_0_16.item3",
            "update.history.0_0_16.item4",
            "update.history.0_0_16.item5"
        ]),
        UpdateHistoryEntry(version: "0.0.15", build: 15, changelog: [
            "update.history.0_0_15.item1",
            "update.history.0_0_15.item2",
            "update.history.0_0_15.item3",
            "update.history.0_0_15.item4",
            "update.history.0_0_15.item5"
        ])
    ]

    /// Returns the history to display, preferring the manifest payload when
    /// available and falling back to the bundled entries otherwise.
    func mergedHistory() -> [UpdateHistoryEntry] {
        if let manifestHistory = lastState?.manifest?.history, !manifestHistory.isEmpty {
            return manifestHistory
        }
        return Self.bundledChangelogHistory
    }

    static let manifestURL = URL(string:
        "https://raw.githubusercontent.com/nykadamec/openmail_ios_dev/main/ios/update.json"
    )!

    private let session: URLSession
    private(set) var lastCheckDate: Date?
    private(set) var lastState: UpdateState?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var currentBuild: Int {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? Int {
            return value
        }
        return 0
    }

    /// The validated release URL, available only after a newer manifest was found.
    var availableReleaseURL: URL? {
        guard case .available(let manifest) = lastState else { return nil }
        return Self.validatedGitHubURL(manifest.releaseURL, release: true)
    }

    /// Convenience alias for callers displaying the action for an available update.
    var releaseURL: URL? { availableReleaseURL }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    @discardableResult
    func checkForUpdate() async -> UpdateState {
        do {
            guard Self.isExpectedManifestURL(Self.manifestURL) else {
                return record(.invalidManifest)
            }
            var request = URLRequest(url: Self.manifestURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return record(.networkError)
            }

            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            guard Self.isValid(manifest), Self.isValidVersion(currentVersion), currentBuild >= 0 else {
                return record(.invalidManifest)
            }

            let newer = manifest.build > currentBuild
                || (manifest.build == currentBuild
                    && Self.compareVersions(manifest.version, currentVersion) == .orderedDescending)
            return record(newer ? .available(manifest) : .upToDate(manifest))
        } catch is DecodingError {
            return record(.invalidManifest)
        } catch {
            return record(.networkError)
        }
    }

    private func record(_ state: UpdateState) -> UpdateState {
        lastCheckDate = Date()
        lastState = state
        return state
    }

    private static func isExpectedManifestURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "raw.githubusercontent.com"
            && url.path == "/nykadamec/openmail_ios_dev/main/ios/update.json"
    }

    private static func isValid(_ manifest: UpdateManifest) -> Bool {
        !manifest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && manifest.build >= 0
            && isValidVersion(manifest.version)
            && isValidVersion(manifest.minimumSupportedVersion)
            && validatedGitHubURL(manifest.releaseURL, release: true) != nil
            && validatedGitHubURL(manifest.ipaURL, release: false) != nil
    }

    private static func isValidVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        return parts.count >= 1 && parts.allSatisfy { !$0.isEmpty && Int($0) != nil }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func validatedGitHubURL(_ value: String, release: Bool) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com", url.user == nil, url.password == nil else {
            return nil
        }
        let path = url.path
        if release {
            guard path.hasPrefix("/nykadamec/openmail_ios_dev/releases/tag/") else { return nil }
        } else {
            guard path.hasPrefix("/nykadamec/openmail_ios_dev/releases/download/") else { return nil }
        }
        return url
    }
}
