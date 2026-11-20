import Foundation
import Combine
import KonserveCore

@MainActor
final class ConnectorViewModel: ObservableObject {
    @Published var servers: [SMBServer] = []
    @Published var selectedServerID = ""
    @Published var manualAddress = ""
    @Published var username = ""
    @Published var password = ""
    @Published var rememberCredentials = false
    @Published var addToConfiguration = false
    @Published var connectionState: SMBConnectionState = .idle
    @Published var availability: [String: ServerAvailability] = [:]
    @Published var selectedShareNames = Set<String>()
    @Published var statusMessage = ""
    @Published private(set) var availableShares: [SMBShare] = []

    private let configurationService: any ConfigurationService
    private let keychainService: any KeychainService
    private let reachabilityService: any ServerReachabilityService
    private let smbService: any SMBService
    private let mountService: any MountService
    private var activeServers: [String: SMBServer] = [:]
    private var isCheckingAvailability = false

    init(
        configurationService: any ConfigurationService = SidecarConfigurationService(),
        keychainService: any KeychainService = SystemKeychainService(),
        reachabilityService: (any ServerReachabilityService)? = nil,
        smbService: (any SMBService)? = nil,
        mountService: (any MountService)? = nil
    ) {
        self.configurationService = configurationService
        self.keychainService = keychainService
        self.reachabilityService = reachabilityService ?? TCPReachabilityService()
        self.smbService = smbService ?? SystemSMBService()
        self.mountService = mountService ?? SystemMountService()
        loadConfiguration()
    }

    var shares: [SMBShare] {
        availableShares
    }

    var canAddCurrentServer: Bool {
        !isCurrentServerConfigured
    }

    var isBusy: Bool {
        switch connectionState {
        case .checkingServer, .authenticating, .findingShares, .mounting:
            return true
        default:
            return false
        }
    }

    func checkConfiguredServers() async {
        guard !isCheckingAvailability else { return }
        isCheckingAvailability = true
        defer { isCheckingAvailability = false }

        for server in servers {
            availability[server.id] = .checking
            var hadError = false
            var reachable = false
            for endpoint in server.endpoints {
                do {
                    let endpointServer = try server.using(endpoint)
                    if try await reachabilityService.isReachable(endpointServer) {
                        reachable = true
                        break
                    }
                } catch {
                    hadError = true
                }
            }
            availability[server.id] = reachable ? .reachable : (hadError ? .error : .unavailable)
        }
    }

    func connect() async {
        guard let server = selectedServer() else {
            connectionState = .failed("Enter a valid server address.")
            return
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty
        else {
            connectionState = .failed("Enter your SMB username and password.")
            return
        }

        selectedShareNames.removeAll()
        availableShares = []
        connectionState = .checkingServer
        statusMessage = "Checking server…"
        let reachableServer: SMBServer?
        do {
            reachableServer = try await firstReachableServer(for: server)
        } catch {
            availability[server.id] = .error
            connectionState = .failed("Could not check the server connection.")
            statusMessage = ""
            return
        }
        guard let reachableServer else {
            availability[server.id] = .unavailable
            connectionState = .failed("The server is unavailable. Check the address and try again.")
            statusMessage = ""
            return
        }
        activeServers[server.id] = reachableServer
        availability[server.id] = .reachable
        do {
            connectionState = .authenticating
            statusMessage = "Authenticating…"
            await Task.yield()

            connectionState = .findingShares
            statusMessage = "Finding available shares…"
            let credentials = SMBCredentials(username: username, password: password)
            let discoveredShares = try await smbService.discoverShares(on: reachableServer, credentials: credentials)
            availableShares = discoveredShares
            connectionState = discoveredShares.isEmpty ? .noShares : .shares(discoveredShares)
            statusMessage = discoveredShares.isEmpty ? "" : "Select one or more shares to mount."
            addServerToConfigurationIfRequested(server)
            do {
                if rememberCredentials {
                    try keychainService.save(credentials, for: reachableServer)
                } else {
                    try keychainService.deleteCredentials(for: reachableServer, username: username)
                }
            } catch {
                statusMessage = rememberCredentials
                    ? "Connected, but the credentials could not be saved to Keychain."
                    : "Connected, but the saved credentials could not be removed from Keychain."
            }
        } catch {
            if case SMBServiceError.invalidCredentials = error {
                connectionState = .failed("The username or password was not accepted. Try again.")
            } else if case SMBServiceError.timedOut = error {
                connectionState = .failed("Share discovery timed out. Check the server and try again.")
            } else if case SMBServiceError.unsupportedOperation = error {
                connectionState = .failed("Share discovery currently supports SMB port 445 only.")
            } else if case SMBServiceError.invalidShareList = error {
                connectionState = .failed("The server returned a share list Konserve could not read.")
            } else if case SMBServiceError.commandFailed = error {
                connectionState = .failed("The SMB command failed. Check the Console diagnostic log for details.")
            } else {
                connectionState = .failed("Could not connect to this server. Check your details and try again.")
            }
            statusMessage = ""
        }
    }

    func loadRememberedCredentials() {
        guard password.isEmpty,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let server = selectedServer()
        else {
            return
        }
        do {
            guard let saved = try keychainService.credentials(for: server, username: username) else { return }
            password = saved.password
            rememberCredentials = true
        } catch {
            statusMessage = "Saved credentials could not be read from Keychain."
        }
    }

    func serverSelectionDidChange() {
        activeServers.removeAll()
        password = ""
        rememberCredentials = false
        addToConfiguration = canAddCurrentServer
        connectionState = .idle
        availableShares = []
        selectedShareNames.removeAll()
        statusMessage = ""
        loadRememberedCredentials()
    }

    func usernameDidChange() {
        password = ""
        rememberCredentials = false
    }

    func useConfiguredServer(_ server: SMBServer) {
        selectedServerID = server.id
        manualAddress = server.endpoints[0].host
        serverSelectionDidChange()
    }

    func returnToConnectionForm() {
        password = ""
        rememberCredentials = false
        addToConfiguration = false
        connectionState = .idle
        availableShares = []
        selectedShareNames.removeAll()
        statusMessage = ""
    }

    func mountSelectedShares() async {
        guard let server = selectedConnectionServer(), !selectedShareNames.isEmpty else { return }
        connectionState = .mounting
        statusMessage = "Mounting selected shares…"
        let credentials = SMBCredentials(username: username, password: password)
        let selectedShares = shares.filter { selectedShareNames.contains($0.name) }
        let coordinator = MountCoordinator()
        do {
            let mountedNames = try await coordinator.mount(
                selectedShares,
                on: server,
                credentials: credentials,
                using: mountService
            )
            connectionState = coordinator.state
            statusMessage = "Mounted \(mountedNames.count) share\(mountedNames.count == 1 ? "" : "s")."
        } catch {
            if case SMBServiceError.mountFailed(let status) = error {
                connectionState = .failed("The selected share could not be mounted (NetFS status \(status)).")
            } else {
                connectionState = .failed("A selected share could not be mounted.")
            }
            statusMessage = ""
        }
    }

    private func loadConfiguration() {
        do {
            servers = try configurationService.loadServers() ?? []
            selectedServerID = servers.first?.id ?? ""
            for server in servers {
                availability[server.id] = .unchecked
            }
        } catch {
            statusMessage = "The server configuration could not be loaded."
        }
    }

    private func addServerToConfigurationIfRequested(_ server: SMBServer) {
        guard addToConfiguration,
              !servers.contains(where: {
                  $0.id == server.id
                      || $0.endpoints.contains { $0.host.caseInsensitiveCompare(server.host) == .orderedSame }
              })
        else { return }

        _ = saveServers(servers + [server])
    }

    private var isCurrentServerConfigured: Bool {
        let host = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return false }
        return servers.contains {
            $0.endpoints.contains { $0.host.caseInsensitiveCompare(host) == .orderedSame }
        }
    }

    @discardableResult
    func saveServers(_ updatedServers: [SMBServer]) -> Bool {
        do {
            try configurationService.saveServers(updatedServers)
            servers = updatedServers
            activeServers.removeAll()
            availability = Dictionary(uniqueKeysWithValues: updatedServers.map { ($0.id, .unchecked) })
            if !updatedServers.contains(where: { $0.id == selectedServerID }) {
                selectedServerID = updatedServers.first?.id ?? ""
                serverSelectionDidChange()
            }
            statusMessage = ""
            Task {
                await checkConfiguredServers()
            }
            return true
        } catch {
            statusMessage = "The server configuration could not be saved."
            return false
        }
    }

    func deleteServer(_ server: SMBServer) {
        saveServers(servers.filter { $0.id != server.id })
    }

    private func selectedConnectionServer() -> SMBServer? {
        guard let server = selectedServer() else { return nil }
        return activeServers[server.id] ?? server
    }

    private func firstReachableServer(for server: SMBServer) async throws -> SMBServer? {
        var hadError = false
        for endpoint in server.endpoints {
            let endpointServer = try server.using(endpoint)
            do {
                if try await reachabilityService.isReachable(endpointServer) {
                    return endpointServer
                }
            } catch {
                hadError = true
            }
        }
        if hadError {
            throw SMBServiceError.unreachable
        }
        return nil
    }

    private func selectedServer() -> SMBServer? {
        let host = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredServer = servers.first(where: { $0.id == selectedServerID }),
           configuredServer.endpoints.contains(where: { $0.host.caseInsensitiveCompare(host) == .orderedSame }) {
            return configuredServer
        }
        guard !host.isEmpty else { return nil }
        return try? SMBServer(id: "manual-\(host.lowercased())", displayName: host, host: host)
    }
}
