import Foundation

public enum SMBModelError: Error, Equatable {
    case invalidHost
    case invalidPort
    case invalidShareName
}

public struct SMBServer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let host: String
    public let port: Int

    public init(id: String, displayName: String, host: String, port: Int = 445) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !trimmedHost.isEmpty,
              !trimmedHost.contains("://"),
              !trimmedHost.contains("/"),
              !trimmedHost.contains("@"),
              trimmedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw SMBModelError.invalidHost
        }
        guard (1...65535).contains(port) else {
            throw SMBModelError.invalidPort
        }
        self.id = id
        self.displayName = displayName
        self.host = trimmedHost
        self.port = port
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, host, port
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(String.self, forKey: .id),
            displayName: values.decode(String.self, forKey: .displayName),
            host: values.decode(String.self, forKey: .host),
            port: values.decodeIfPresent(Int.self, forKey: .port) ?? 445
        )
    }
}

public struct SMBShare: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public var id: String { name }

    public init(name: String) throws {
        guard !name.isEmpty,
              !name.contains("/"),
              name != ".",
              name != "..",
              name.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw SMBModelError.invalidShareName
        }
        self.name = name
    }
}

public struct SMBCredentials: Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public enum SMBConnectionState: Equatable, Sendable {
    case idle
    case checkingServer
    case authenticating
    case findingShares
    case shares([SMBShare])
    case noShares
    case mounting
    case mounted([String])
    case failed(String)
}

public enum ServerAvailability: Equatable, Sendable {
    case unchecked
    case checking
    case reachable
    case unavailable
    case error
}
