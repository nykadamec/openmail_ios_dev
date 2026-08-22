import Foundation

/// A server endpoint.  Credentials and session cookies are deliberately not
/// part of this value so profiles can safely be persisted as Codable data.
struct ServerProfile: Codable, Identifiable, Equatable {
    enum Scheme: String, Codable {
        case http
        case https
    }

    enum ValidationError: Error, LocalizedError, Equatable {
        case emptyHost
        case invalidScheme
        case invalidHost
        case invalidPort
        case forbiddenURLComponents

        var errorDescription: String? {
            switch self {
            case .emptyHost: return "Server hostname is required"
            case .invalidScheme: return "Only HTTP and HTTPS are supported"
            case .invalidHost: return "Invalid server hostname or IP address"
            case .invalidPort: return "Invalid server port"
            case .forbiddenURLComponents: return "Server URL must not contain credentials, path, query, or fragment"
            }
        }
    }

    let id: UUID
    var name: String
    var scheme: Scheme
    var host: String
    var port: Int?

    static let defaultPublicProfile: ServerProfile = try! ServerProfile(
        id: UUID(uuidString: "4E8F2C37-0A10-4D5F-9E2F-7A9B3B4F1E21")!,
        name: "openMail",
        scheme: .https,
        host: "email.adamec.pro",
        port: nil
    )

    init(id: UUID = UUID(), name: String, scheme: Scheme = .https, host: String, port: Int? = nil) throws {
        let normalized = try Self.normalize(scheme: scheme, host: host, port: port)
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalized.host : name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scheme = scheme
        self.host = normalized.host
        self.port = normalized.port
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let scheme = try container.decode(Scheme.self, forKey: .scheme)
        let host = try container.decode(String.self, forKey: .host)
        let port = try container.decodeIfPresent(Int.self, forKey: .port)
        let normalized = try Self.normalize(scheme: scheme, host: host, port: port)
        self.id = id
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? normalized.host : trimmedName
        self.scheme = scheme
        self.host = normalized.host
        self.port = normalized.port
    }

    var baseURL: URL {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = host
        components.port = port
        return components.url!
    }

    init(urlString: String, id: UUID = UUID(), name: String? = nil) throws {
        guard let components = URLComponents(string: urlString),
              let rawScheme = components.scheme,
              let scheme = Scheme(rawValue: rawScheme.lowercased()) else { throw ValidationError.invalidScheme }
        guard components.user == nil, components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil else { throw ValidationError.forbiddenURLComponents }
        guard let host = components.host else { throw ValidationError.emptyHost }
        // URLComponents exposes IPv6 hosts without their URL brackets.  Keep
        // that representation here; normalize() validates it and baseURL
        // adds the brackets again when serializing the URL.
        try self.init(id: id, name: name ?? host, scheme: scheme, host: host, port: components.port)
    }

    private static func normalize(scheme: Scheme, host: String, port: Int?) throws -> (host: String, port: Int?) {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ValidationError.emptyHost }
        guard !value.contains(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == "@" }) else { throw ValidationError.invalidHost }
        let bracketedIPv6 = value.hasPrefix("[") || value.hasSuffix("]")
        guard (!bracketedIPv6 || (value.hasPrefix("[") && value.hasSuffix("]"))) else {
            throw ValidationError.invalidHost
        }
        let normalized = (value.hasPrefix("[") && value.hasSuffix("]"))
            ? String(value.dropFirst().dropLast())
            : value
        let authorityHost = normalized.contains(":") ? "[\(normalized)]" : normalized
        guard let parsed = URLComponents(string: "\(scheme.rawValue)://\(authorityHost)"),
              parsed.user == nil, parsed.password == nil, parsed.path.isEmpty,
              parsed.query == nil, parsed.fragment == nil, parsed.port == nil,
              parsed.host.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }).map({ $0.lowercased() }) == normalized.lowercased(),
              !normalized.contains("[") && !normalized.contains("]") else { throw ValidationError.invalidHost }
        if let port, !(1...65535).contains(port) { throw ValidationError.invalidPort }
        return (normalized.lowercased(), port)
    }
}
