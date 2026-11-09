import Foundation
import Network

public struct TCPReachabilityService: ServerReachabilityService {
    private let timeout: Duration

    public init(timeout: Duration = .seconds(4)) {
        self.timeout = timeout
    }

    public func isReachable(_ server: SMBServer) async throws -> Bool {
        guard let port = NWEndpoint.Port(rawValue: UInt16(server.port)) else {
            return false
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(server.host),
            port: port,
            using: .tcp
        )
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let completion = ReachabilityCompletion(continuation: continuation, connection: connection)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            completion.finish(true)
                        case .failed, .cancelled:
                            completion.finish(false)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .utility))
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            connection.cancel()
            return result
        }
    }
}

private final class ReachabilityCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private let connection: NWConnection

    init(continuation: CheckedContinuation<Bool, Never>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ result: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        pending.resume(returning: result)
        connection.cancel()
    }
}
