import Foundation

public enum ConfigurationError: Error, Equatable {
    case duplicateServerID(String)
    case unreadableFile
}

public struct SidecarConfigurationService: ConfigurationService {
    public static let defaultURL = URL(
        fileURLWithPath: "/Library/Application Support/SMBConnector/servers.json"
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

    private struct ConfigurationFile: Decodable {
        let servers: [SMBServer]
    }
}
