import Foundation
import NetFS

public struct SystemSMBService: SMBService {
    private let executableURL: URL
    private let timeout: Duration

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/smbutil"),
        timeout: Duration = .seconds(30)
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    public func discoverShares(on server: SMBServer, credentials: SMBCredentials) async throws -> [SMBShare] {
        guard server.port == 445 else {
            throw SMBServiceError.unsupportedOperation
        }

        let process = SMBProcessExecution(
            executableURL: executableURL,
            arguments: Self.arguments(
                smbutilPath: executableURL.path,
                host: server.host,
                username: credentials.username
            ),
            password: credentials.password
        )

        do {
            let rawOutput = try await withTaskCancellationHandler {
                try await process.run(timeout: timeout)
            } onCancel: {
                process.terminate()
            }

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

    private final class SMBProcessExecution: @unchecked Sendable {
        private let process: Process
        private let input: Pipe
        private let output: Pipe
        private let password: String

        init(executableURL: URL, arguments: [String], password: String) {
            process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            input = Pipe()
            output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            self.password = password
        }

        var terminationStatus: Int32 {
            process.terminationStatus
        }

        func run(timeout: Duration) async throws -> Data {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await Task.detached { [self] in
                        try process.run()
                        input.fileHandleForWriting.write(Data((password + "\n").utf8))
                        try input.fileHandleForWriting.close()
                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        return data
                    }.value
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    self.terminate()
                    throw SMBServiceError.timedOut
                }
                defer {
                    group.cancelAll()
                }
                return try await group.next()!
            }
        }

        func terminate() {
            if process.isRunning {
                process.terminate()
            }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
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
        let cleanedOutput = output.replacingOccurrences(
            of: #"\x{001B}\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        let lines = cleanedOutput.components(separatedBy: .newlines)
        let hasShareHeader = lines.contains {
            $0.localizedCaseInsensitiveContains("Share")
                && $0.localizedCaseInsensitiveContains("Type")
        }
        guard hasShareHeader else {
            throw SMBServiceError.invalidShareList
        }
        let pattern = #"^(.+?)(?: {2,}|\t+)(Disk|Pipe)\b"#
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        var shares: [SMBShare] = []
        for line in lines {
            let tabSeparatedFields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if tabSeparatedFields.count >= 2 {
                let type = tabSeparatedFields[1].trimmingCharacters(in: .whitespaces)
                guard type.caseInsensitiveCompare("Disk") == .orderedSame else { continue }
                let name = tabSeparatedFields[0].trimmingCharacters(in: .whitespaces)
                do {
                    shares.append(try SMBShare(name: name))
                } catch {
                    throw SMBServiceError.invalidShareList
                }
                continue
            }

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
