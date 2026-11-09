import Foundation
import NetFS

public struct SystemSMBService: SMBService {
    private let executableURL: URL
    private let terminalURL: URL

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/smbutil"),
        terminalURL: URL = URL(fileURLWithPath: "/usr/bin/script")
    ) {
        self.executableURL = executableURL
        self.terminalURL = terminalURL
    }

    public func discoverShares(on server: SMBServer, credentials: SMBCredentials) async throws -> [SMBShare] {
        guard server.port == 445 else {
            throw SMBServiceError.unsupportedOperation
        }

        let process = Process()
        process.executableURL = terminalURL
        process.arguments = Self.arguments(
            smbutilPath: executableURL.path,
            host: server.host,
            username: credentials.username
        )
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let passwordData = Data((credentials.password + "\n").utf8)
            input.fileHandleForWriting.write(passwordData)
            try input.fileHandleForWriting.close()
            let rawOutput = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let text = ProcessOutputRedactor.redact(
                String(decoding: rawOutput, as: UTF8.self),
                sensitiveValues: [credentials.password]
            )
            guard process.terminationStatus == 0 else {
                if text.localizedCaseInsensitiveContains("authentication")
                    || text.localizedCaseInsensitiveContains("denied")
                    || text.localizedCaseInsensitiveContains("logon_failure")
                {
                    throw SMBServiceError.invalidCredentials
                }
                throw SMBServiceError.commandFailed
            }
            return try SMBShareListParser.parse(text)
        } catch let error as SMBServiceError {
            throw error
        } catch {
            throw SMBServiceError.commandFailed
        }
    }

    public static func arguments(
        smbutilPath: String,
        host: String,
        username: String
    ) -> [String] {
        ["-q", "/dev/null", smbutilPath, "view", "//\(username)@\(host)"]
    }
}

public enum ProcessOutputRedactor {
    public static func redact(_ output: String, sensitiveValues: [String]) -> String {
        sensitiveValues
            .filter { !$0.isEmpty }
            .reduce(output) { result, secret in
                result.replacingOccurrences(of: secret, with: "[REDACTED]")
            }
    }
}

public enum SMBShareListParser {
    public static func parse(_ output: String) throws -> [SMBShare] {
        let hasShareHeader = output.components(separatedBy: .newlines).contains {
            $0.localizedCaseInsensitiveContains("Share")
                && $0.localizedCaseInsensitiveContains("Type")
        }
        guard hasShareHeader else {
            throw SMBServiceError.invalidShareList
        }
        let pattern = #"^(.+?)\s{2,}(Disk|Pipe)\b"#
        let expression = try NSRegularExpression(pattern: pattern)
        var shares: [SMBShare] = []
        for line in output.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = expression.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let typeRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }
            guard line[typeRange] == "Disk" else { continue }
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "Share" else { continue }
            do {
                let share = try SMBShare(name: name)
                shares.append(share)
            } catch {
                throw SMBServiceError.invalidShareList
            }
        }
        return shares
    }
}

public struct SystemMountService: MountService {
    public init() {}

    public func mount(_ share: SMBShare, on server: SMBServer, credentials: SMBCredentials) async throws -> URL {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = server.host
        components.port = server.port == 445 ? nil : server.port
        components.path = "/" + share.name
        guard let remoteURL = components.url else {
            throw SMBServiceError.mountFailed(-1)
        }

        let mountURL = URL(fileURLWithPath: "/Volumes/\(share.name)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: mountURL.path) {
            do {
                try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: false)
            } catch {
                throw SMBServiceError.mountFailed(-1)
            }
        }

        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey] = kNAUIOptionNoUI
        var mountedPaths: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            remoteURL as CFURL,
            mountURL as CFURL,
            credentials.username as CFString,
            credentials.password as CFString,
            openOptions as CFMutableDictionary,
            nil,
            &mountedPaths
        )
        _ = mountedPaths?.takeRetainedValue()
        guard status == 0 else {
            throw SMBServiceError.mountFailed(Int32(status))
        }
        return mountURL
    }
}
