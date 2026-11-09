import Foundation
import Combine
import SMBConnectorCore

@MainActor
final class ConnectorViewModel: ObservableObject {
    @Published var servers: [SMBServer] = []
    @Published var selectedServerID = ""
    @Published var manualAddress = ""
    @Published var username = ""
    @Published var password = ""
    @Published var rememberCredentials = false
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

    init(
        configurationService: any ConfigurationService = SidecarConfigurationService(),
        keychainService: any KeychainService = SystemKeychainService(),
        reachabilityService: (any ServerReachabilityService)? = nil,
        smbService: (any SMBService)? = nil,
        mountService: (any MountService)? = nil
    ) {
        self.configurationService = configurationService
        self.keychainService = keychainService
        let arguments = Set(CommandLine.arguments)
        let environment = ProcessInfo.processInfo.environment
        let useRealSMB = environment["SMB_CONNECTOR_USE_REAL_SMB"] == "1"
            || arguments.contains("--use-real-smb")
        let mockMode = environment["SMB_CONNECTOR_MOCK_MODE"]
        let mockUnreachable = arguments.contains("--mock-unreachable") || mockMode == "unavailable"
        self.reachabilityService = reachabilityService ?? (
            useRealSMB
                ? TCPReachabilityService()
                : MockReachabilityService(isReachable: !mockUnreachable)
        )
        if let smbService {
            self.smbService = smbService
        } else if useRealSMB {
            self.smbService = SystemSMBService()
        } else if arguments.contains("--mock-invalid-credentials") || mockMode == "invalid-credentials" {
            self.smbService = MockSMBService(result: .invalidCredentials)
        } else if arguments.contains("--mock-empty") || mockMode == "empty" {
            self.smbService = MockSMBService(result: .success([]))
        } else {
            self.smbService = MockSMBService()
        }
        self.mountService = mountService ?? (
            useRealSMB
                ? SystemMountService()
                : MockMountService(shouldFail: arguments.contains("--mock-mount-failure"))
        )
        loadConfiguration()
    }

    var shares: [SMBShare] {
        availableShares
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
        for server in servers {
            availability[server.id] = .checking
            do {
                availability[server.id] = try await reachabilityService.isReachable(server)
                    ? .reachable
                    : .unavailable
            } catch {
                availability[server.id] = .error
            }
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
        let isReachable: Bool
        do {
            isReachable = try await reachabilityService.isReachable(server)
        } catch {
            availability[server.id] = .error
            connectionState = .failed("Could not check the server connection.")
            statusMessage = ""
            return
        }
        guard isReachable else {
            availability[server.id] = .unavailable
            connectionState = .failed("The server is unavailable. Check the address and try again.")
            statusMessage = ""
            return
        }
        availability[server.id] = .reachable
        do {
            connectionState = .authenticating
            statusMessage = "Authenticating…"
            await Task.yield()

            connectionState = .findingShares
            statusMessage = "Finding available shares…"
            let credentials = SMBCredentials(username: username, password: password)
            let discoveredShares = try await smbService.discoverShares(on: server, credentials: credentials)
            availableShares = discoveredShares
            connectionState = discoveredShares.isEmpty ? .noShares : .shares(discoveredShares)
            statusMessage = discoveredShares.isEmpty ? "" : "Select one or more shares to mount."
            do {
                if rememberCredentials {
                    try keychainService.save(credentials, for: server)
                } else {
                    try keychainService.deleteCredentials(for: server, username: username)
                }
            } catch {
                statusMessage = rememberCredentials
                    ? "Connected, but the credentials could not be saved to Keychain."
                    : "Connected, but the saved credentials could not be removed from Keychain."
            }
        } catch {
            if case SMBServiceError.invalidCredentials = error {
                connectionState = .failed("The username or password was not accepted. Try again.")
            } else if case SMBServiceError.unsupportedOperation = error {
                connectionState = .failed("Share discovery currently supports SMB port 445 only.")
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
        password = ""
        rememberCredentials = false
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

    func useDifferentCredentials() {
        username = ""
        password = ""
        rememberCredentials = false
        connectionState = .idle
        availableShares = []
        selectedShareNames.removeAll()
        statusMessage = ""
    }

    func mountSelectedShares() async {
        guard let server = selectedServer(), !selectedShareNames.isEmpty else { return }
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
            connectionState = .failed("A selected share could not be mounted.")
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

    private func selectedServer() -> SMBServer? {
        if !servers.isEmpty {
            return servers.first(where: { $0.id == selectedServerID })
        }
        let host = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        return try? SMBServer(id: "manual-\(host.lowercased())", displayName: host, host: host)
    }
}
