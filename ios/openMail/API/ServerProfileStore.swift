import Foundation
import Observation

/// Local profile persistence.  Only endpoint metadata is stored here; session
/// credentials remain in KeychainStore, namespaced by profile UUID.
@Observable
final class ServerProfileStore {
    private struct State: Codable {
        var profiles: [ServerProfile]
        var activeProfileID: UUID?
    }

    private let defaults: UserDefaults
    private let key: String
    private(set) var profiles: [ServerProfile]
    private(set) var activeProfileID: UUID?

    init(defaults: UserDefaults = .standard, key: String = "openmail.serverProfiles") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key), let state = try? JSONDecoder().decode(State.self, from: data) {
            profiles = state.profiles
            activeProfileID = state.activeProfileID
        } else {
            profiles = []
            activeProfileID = nil
        }
        if profiles.isEmpty {
            activeProfileID = nil
        } else if activeProfileID == nil || !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }
    }

    var activeProfile: ServerProfile? { profiles.first { $0.id == activeProfileID } }

    var hasConfiguredProfile: Bool {
        profiles.contains(where: { !$0.isEmptyProfile })
    }

    func save() throws {
        let data = try JSONEncoder().encode(State(profiles: profiles, activeProfileID: activeProfileID))
        defaults.set(data, forKey: key)
    }

    func setProfiles(_ profiles: [ServerProfile]) throws {
        self.profiles = profiles
        if self.profiles.isEmpty {
            activeProfileID = nil
        } else if !self.profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = self.profiles[0].id
        }
        try save()
    }

    func setActiveProfile(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        try save()
    }
}
