import Foundation

@MainActor
public final class MountCoordinator {
    public private(set) var state: SMBConnectionState = .idle

    public init() {}

    @discardableResult
    public func mount(
        _ shares: [SMBShare],
        on server: SMBServer,
        credentials: SMBCredentials,
        using service: any MountService
    ) async throws -> [String] {
        state = .mounting
        var mountedNames: [String] = []
        do {
            for share in shares {
                _ = try await service.mount(share, on: server, credentials: credentials)
                mountedNames.append(share.name)
            }
            state = .mounted(mountedNames)
            return mountedNames
        } catch {
            state = .failed("A selected share could not be mounted.")
            throw error
        }
    }
}
