import Foundation
import Testing
@testable import KonserveCore

struct KonserveCoreTests {
    @Test
    func parsesConfiguredServersAndDefaultsPort() throws {
        let data = Data(#"{"servers":[{"id":"media","displayName":"Media","host":"media.example.local"}]}"#.utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let servers = try SidecarConfigurationService(fileURL: url).loadServers()
        #expect(servers == [try SMBServer(id: "media", displayName: "Media", host: "media.example.local")])
    }

    @Test
    func missingConfigurationEnablesManualAddressMode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(try SidecarConfigurationService(fileURL: url).loadServers() == nil)
    }

    @Test
    func rejectsInvalidServerAndDuplicateIDs() throws {
        #expect(throws: (any Error).self) {
            _ = try SMBServer(id: "bad", displayName: "Bad", host: "smb://host")
        }
        let invalidServerData = Data(#"{"servers":[{"id":"bad","displayName":"Bad","host":"smb://host"}]}"#.utf8)
        let invalidServerURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try invalidServerData.write(to: invalidServerURL)
        defer { try? FileManager.default.removeItem(at: invalidServerURL) }
        #expect(throws: (any Error).self) {
            _ = try SidecarConfigurationService(fileURL: invalidServerURL).loadServers()
        }
        let data = Data(#"{"servers":[{"id":"media","displayName":"One","host":"one"},{"id":"media","displayName":"Two","host":"two"}]}"#.utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ConfigurationError.duplicateServerID("media")) {
            _ = try SidecarConfigurationService(fileURL: url).loadServers()
        }
    }

    @Test
    func parsesShareNamesContainingSpacesAndEmptyList() throws {
        let output = """
        Share                         Type       Comments
        ----------------------------  ---------  --------
        Public                        Disk
        Media Library                 Disk       Movies and music
        IPC$                          Pipe       Remote IPC
        """
        #expect(try SMBShareListParser.parse(output).map(\.name) == ["Public", "Media Library"])
        #expect(try SMBShareListParser.parse("Share Type Comments\n").isEmpty)
        #expect(throws: SMBServiceError.invalidShareList) {
            _ = try SMBShareListParser.parse("unexpected output")
        }
    }

    @Test
    func parsesTabSeparatedAndCaseVariantSMBOutput() throws {
        let output = """
        Share\tType\tComments
        Team Archive\tDisk\tShared documents
        Media Library\tdisk\tMovies
        IPC$\tPipe\tRemote IPC
        """
        #expect(try SMBShareListParser.parse(output).map(\.name) == ["Team Archive", "Media Library"])
    }

    @Test
    func parserStripsTerminalColorSequences() throws {
        let output = "\u{001B}[32mShare                         Type\u{001B}[0m\n\u{001B}[32mPublic                        Disk\u{001B}[0m\n"
        #expect(try SMBShareListParser.parse(output).map(\.name) == ["Public"])
    }

    @Test
    func invalidCredentialsAndUnreachableServersRemainExplicit() async throws {
        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        let credentials = SMBCredentials(username: "user", password: "secret")
        let invalid = MockSMBService(result: .invalidCredentials, delay: .zero)
        await #expect(throws: SMBServiceError.invalidCredentials) {
            try await invalid.discoverShares(on: server, credentials: credentials)
        }
        let unavailable = MockSMBService(result: .unavailable, delay: .zero)
        await #expect(throws: SMBServiceError.unreachable) {
            try await unavailable.discoverShares(on: server, credentials: credentials)
        }
    }

    @Test
    func mockMountReturnsStandardVolumePath() async throws {
        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        let share = try SMBShare(name: "Media Library")
        let mounted = try await MockMountService().mount(
            share,
            on: server,
            credentials: SMBCredentials(username: "user", password: "secret")
        )
        #expect(mounted.path == "/Volumes/Media Library")
    }

    @Test
    func keychainSupportsSaveReadUpdateAndDelete() throws {
        let server = try SMBServer(id: "media", displayName: "Media", host: "media.example.local")
        let keychain = InMemoryKeychainService()
        try keychain.save(SMBCredentials(username: "smb-user", password: "first"), for: server)
        #expect(try keychain.credentials(for: server, username: "smb-user")?.password == "first")
        try keychain.save(SMBCredentials(username: "smb-user", password: "updated"), for: server)
        #expect(try keychain.credentials(for: server, username: "smb-user")?.password == "updated")
        try keychain.deleteCredentials(for: server, username: "smb-user")
        #expect(try keychain.credentials(for: server, username: "smb-user") == nil)
    }

    @Test
    func processOutputIsRedactedAndPasswordNeverEntersArguments() throws {
        let password = "do-not-leak"
        let output = ProcessOutputRedactor.redact(
            "Password: \(password)\n",
            sensitiveValues: [password]
        )
        #expect(!output.contains(password))

        let arguments = SystemSMBService.arguments(
            smbutilPath: "/usr/bin/smbutil",
            host: "media.example.local",
            username: "smb-user"
        )
        #expect(!arguments.contains(password))
        #expect(arguments.last == "//smb-user@media.example.local")
    }

    @Test
    func systemDiscoveryRejectsNonstandardPortsBeforeStartingAProcess() async throws {
        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local", port: 1445)
        await #expect(throws: SMBServiceError.unsupportedOperation) {
            try await SystemSMBService().discoverShares(
                on: server,
                credentials: SMBCredentials(username: "user", password: "secret")
            )
        }
    }

    @Test
    func systemDiscoveryTimesOutAndTerminatesTheProcess() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("#!/bin/sh\nexec sleep 10\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        await #expect(throws: SMBServiceError.timedOut) {
            try await SystemSMBService(
                executableURL: scriptURL,
                timeout: .milliseconds(50)
            ).discoverShares(
                on: server,
                credentials: SMBCredentials(username: "user", password: "secret")
            )
        }
    }

    @Test
    func systemDiscoveryPassesPasswordToDirectSMBProcess() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("""
        #!/bin/sh
        IFS= read -r password
        [ "$password" = "secret" ] || exit 1
        printf 'Share                         Type       Comments\\n'
        printf 'Public                        Disk\\n'
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        let shares = try await SystemSMBService(
            executableURL: scriptURL,
            timeout: .seconds(1)
        ).discoverShares(
            on: server,
            credentials: SMBCredentials(username: "user", password: "secret")
        )
        #expect(shares.map(\.name) == ["Public"])
    }

    @Test
    func reachabilityCanReportAvailableAndUnavailable() async throws {
        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        #expect(try await MockReachabilityService(isReachable: true).isReachable(server))
        #expect(try await !MockReachabilityService(isReachable: false).isReachable(server))
    }

    @Test
    @MainActor
    func mountCoordinatorTransitionsFromMountingToMounted() async throws {
        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        let share = try SMBShare(name: "Public")
        let coordinator = MountCoordinator()
        let mountTask = Task {
            try await coordinator.mount(
                [share],
                on: server,
                credentials: SMBCredentials(username: "user", password: "secret"),
                using: DelayedMountService()
            )
        }
        await Task.yield()
        #expect(coordinator.state == .mounting)
        #expect(try await mountTask.value == ["Public"])
        #expect(coordinator.state == .mounted(["Public"]))
    }

    @Test
    @MainActor
    func mountCoordinatorReportsFailureState() async throws {
        let server = try SMBServer(id: "test", displayName: "Test", host: "example.local")
        let share = try SMBShare(name: "Public")
        let coordinator = MountCoordinator()
        await #expect(throws: SMBServiceError.mountFailed(-1)) {
            try await coordinator.mount(
                [share],
                on: server,
                credentials: SMBCredentials(username: "user", password: "secret"),
                using: FailingMountService()
            )
        }
        #expect(coordinator.state == .failed("A selected share could not be mounted."))
    }
}

private struct DelayedMountService: MountService {
    func mount(_ share: SMBShare, on server: SMBServer, credentials: SMBCredentials) async throws -> URL {
        try await Task.sleep(for: .milliseconds(50))
        return URL(fileURLWithPath: "/Volumes/\(share.name)")
    }
}

private struct FailingMountService: MountService {
    func mount(_ share: SMBShare, on server: SMBServer, credentials: SMBCredentials) async throws -> URL {
        throw SMBServiceError.mountFailed(-1)
    }
}
