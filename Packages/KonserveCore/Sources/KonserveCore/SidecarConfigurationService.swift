import Foundation

public enum ConfigurationError: Error, Equatable {
    case duplicateServerID(String)
    case unreadableFile
    case cannotCreateDirectory
    case cannotWriteFile
}

public struct SidecarConfigurationService: ConfigurationService {
    public static let defaultURL = URL(
        fileURLWithPath: "/Users/Shared/Konserve/servers.json"
    )

    private let fileURL: URL

    public init(fileURL: URL = SidecarConfigurationService.defaultURL) {
        self.fileURL = fileURL
    }

    public func loadServers() throws -> [SMBServer]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigurationError.unreadableFile
        }
        let configuration: ConfigurationFile
        do {
            configuration = try JSONDecoder().decode(ConfigurationFile.self, from: data)
        } catch let error as SMBModelError {
            throw error
        } catch {
            throw ConfigurationError.unreadableFile
        }

        var seenIDs = Set<String>()
        for server in configuration.servers {
            guard seenIDs.insert(server.id).inserted else {
                throw ConfigurationError.duplicateServerID(server.id)
            }
        }
        return configuration.servers
    }

    public func saveServers(_ servers: [SMBServer]) throws {
        var seenIDs = Set<String>()
        for server in servers {
            guard seenIDs.insert(server.id).inserted else {
                throw ConfigurationError.duplicateServerID(server.id)
            }
        }

        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o775]
            )
        } catch {
            throw ConfigurationError.cannotCreateDirectory
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(ConfigurationFile(servers: servers))
        } catch {
            throw ConfigurationError.cannotWriteFile
        }

        let temporaryURL = directoryURL.appendingPathComponent(".servers-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw ConfigurationError.cannotWriteFile
            }
        }
    }

    private struct ConfigurationFile: Codable {
        let servers: [SMBServer]
    }
}
