import Foundation

/// Local profile persistence.  Only endpoint metadata is stored here; session
/// credentials remain in KeychainStore, namespaced by profile UUID.
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
            profiles = [ServerProfile.defaultPublicProfile]
            activeProfileID = ServerProfile.defaultPublicProfile.id
        }
        if profiles.isEmpty { profiles = [ServerProfile.defaultPublicProfile] }
        if activeProfileID == nil || !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }
    }

    var activeProfile: ServerProfile? { profiles.first { $0.id == activeProfileID } }

    func save() throws {
        let data = try JSONEncoder().encode(State(profiles: profiles, activeProfileID: activeProfileID))
        defaults.set(data, forKey: key)
    }

    func setProfiles(_ profiles: [ServerProfile]) throws {
        self.profiles = profiles.isEmpty ? [ServerProfile.defaultPublicProfile] : profiles
        if !self.profiles.contains(where: { $0.id == activeProfileID }) { activeProfileID = self.profiles[0].id }
        try save()
    }

    func setActiveProfile(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        try save()
    }
}
