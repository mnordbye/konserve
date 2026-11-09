import Foundation

public protocol SMBService: Sendable {
    func discoverShares(on server: SMBServer, credentials: SMBCredentials) async throws -> [SMBShare]
}

public protocol KeychainService: Sendable {
    func save(_ credentials: SMBCredentials, for server: SMBServer) throws
    func credentials(for server: SMBServer, username: String) throws -> SMBCredentials?
    func deleteCredentials(for server: SMBServer, username: String) throws
}

public protocol ConfigurationService: Sendable {
    func loadServers() throws -> [SMBServer]?
}

public protocol ServerReachabilityService: Sendable {
    func isReachable(_ server: SMBServer) async throws -> Bool
}

public protocol MountService: Sendable {
    func mount(_ share: SMBShare, on server: SMBServer, credentials: SMBCredentials) async throws -> URL
}

public enum SMBServiceError: Error, Equatable {
    case invalidCredentials
    case unreachable
    case commandFailed
    case invalidShareList
    case unsupportedOperation
    case mountFailed(Int32)
}

public struct MockSMBService: SMBService {
    public enum Result: Sendable {
        case success([SMBShare])
        case invalidCredentials
        case unavailable
    }

    private let result: Result
    private let delay: Duration

    public init(
        result: Result = .success([
            try! SMBShare(name: "Shared"),
            try! SMBShare(name: "Media Library")
        ]),
        delay: Duration = .milliseconds(500)
    ) {
        self.result = result
        self.delay = delay
    }

    public func discoverShares(on server: SMBServer, credentials: SMBCredentials) async throws -> [SMBShare] {
        try await Task.sleep(for: delay)
        switch result {
        case .success(let shares):
            return shares
        case .invalidCredentials:
            throw SMBServiceError.invalidCredentials
        case .unavailable:
            throw SMBServiceError.unreachable
        }
    }
}

public struct MockMountService: MountService {
    private let shouldFail: Bool

    public init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    public func mount(_ share: SMBShare, on server: SMBServer, credentials: SMBCredentials) async throws -> URL {
        if shouldFail {
            throw SMBServiceError.mountFailed(-1)
        }
        return URL(fileURLWithPath: "/Volumes/\(share.name)", isDirectory: true)
    }
}

public struct MockReachabilityService: ServerReachabilityService {
    public var isReachableResult: Bool

    public init(isReachable: Bool = true) {
        self.isReachableResult = isReachable
    }

    public func isReachable(_ server: SMBServer) async throws -> Bool {
        isReachableResult
    }
}

public final class InMemoryKeychainService: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: String] = [:]

    public init() {}

    public func save(_ credentials: SMBCredentials, for server: SMBServer) throws {
        lock.lock()
        defer { lock.unlock() }
        entries[key(server: server, username: credentials.username)] = credentials.password
    }

    public func credentials(for server: SMBServer, username: String) throws -> SMBCredentials? {
        lock.lock()
        defer { lock.unlock() }
        guard let password = entries[key(server: server, username: username)] else { return nil }
        return SMBCredentials(username: username, password: password)
    }

    public func deleteCredentials(for server: SMBServer, username: String) throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key(server: server, username: username))
    }

    private func key(server: SMBServer, username: String) -> String {
        "\(server.id)\u{0}\(username)"
    }
}
