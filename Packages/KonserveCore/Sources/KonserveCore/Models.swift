import Foundation

public enum SMBModelError: Error, Equatable {
    case invalidHost
    case invalidPort
    case invalidShareName
    case noEndpoints
}

public struct SMBEndpoint: Codable, Equatable, Identifiable, Sendable {
    public let host: String
    public let port: Int

    public var id: String {
        "\(host):\(port)"
    }

    public init(host: String, port: Int = 445) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
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
        self.host = trimmedHost
        self.port = port
    }

    private enum CodingKeys: String, CodingKey {
        case host, port
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            host: values.decode(String.self, forKey: .host),
            port: values.decodeIfPresent(Int.self, forKey: .port) ?? 445
        )
    }
}

public struct SMBServer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let endpoints: [SMBEndpoint]

    public var host: String {
        endpoints[0].host
    }

    public var port: Int {
        endpoints[0].port
    }

    public init(id: String, displayName: String, host: String, port: Int = 445) throws {
        try self.init(
            id: id,
            displayName: displayName,
            endpoints: [SMBEndpoint(host: host, port: port)]
        )
    }

    public init(id: String, displayName: String, endpoints: [SMBEndpoint]) throws {
        guard !endpoints.isEmpty else {
            throw SMBModelError.noEndpoints
        }
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SMBModelError.invalidHost
        }
        self.id = id
        self.displayName = displayName
        self.endpoints = endpoints
    }

    public func using(_ endpoint: SMBEndpoint) throws -> SMBServer {
        try SMBServer(id: id, displayName: displayName, endpoints: [endpoint])
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, host, port, endpoints
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .id)
        let displayName = try values.decode(String.self, forKey: .displayName)
        if let endpoints = try values.decodeIfPresent([SMBEndpoint].self, forKey: .endpoints) {
            try self.init(id: id, displayName: displayName, endpoints: endpoints)
        } else {
            try self.init(
                id: id,
                displayName: displayName,
                host: values.decode(String.self, forKey: .host),
                port: values.decodeIfPresent(Int.self, forKey: .port) ?? 445
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(endpoints, forKey: .endpoints)
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
