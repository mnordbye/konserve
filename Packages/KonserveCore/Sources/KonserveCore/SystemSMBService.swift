import Foundation
import NetFS
import Darwin
import os

private let smbLogger = Logger(subsystem: "com.gunzdev.konserve", category: "SMB")

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

        smbLogger.notice("Starting share discovery on SMB port \(server.port)")
        let process = SMBProcessExecution(
            executableURL: executableURL,
            arguments: Self.arguments(
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
                sensitiveValues: [credentials.password, credentials.username, server.host]
            )
            smbLogger.debug("smbutil exited with status \(process.terminationStatus); output: \(text, privacy: .public)")
            guard process.terminationStatus == 0 else {
                if text.localizedCaseInsensitiveContains("authentication")
                    || text.localizedCaseInsensitiveContains("denied")
                    || text.localizedCaseInsensitiveContains("logon_failure")
                {
                    smbLogger.error("smbutil reported an authentication failure")
                    throw SMBServiceError.invalidCredentials
                }
                smbLogger.error("smbutil failed with status \(process.terminationStatus)")
                throw SMBServiceError.commandFailed
            }
            do {
                let shares = try SMBShareListParser.parse(text)
                smbLogger.notice("Share discovery completed with \(shares.count) disk share(s)")
                return shares
            } catch {
                smbLogger.error("smbutil returned an unrecognized share list")
                throw error
            }
        } catch let error as SMBServiceError {
            throw error
        } catch {
            smbLogger.error("Share discovery failed before parsing output")
            throw SMBServiceError.commandFailed
        }
    }

    private final class SMBProcessExecution: @unchecked Sendable {
        private let executableURL: URL
        private let arguments: [String]
        private let password: String
        private let lock = NSLock()
        private var masterFileHandle: FileHandle?
        private var processID: pid_t?
        private var status: Int32 = -1

        init(executableURL: URL, arguments: [String], password: String) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.password = password
        }

        var terminationStatus: Int32 {
            lock.lock()
            defer { lock.unlock() }
            return status
        }

        func run(timeout: Duration) async throws -> Data {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await Task.detached { [self] in
                        var master: Int32 = -1
                        let processID = forkpty(&master, nil, nil, nil)
                        guard processID >= 0 else {
                            throw SMBServiceError.commandFailed
                        }
                        if processID == 0 {
                            Self.execute(executableURL: executableURL, arguments: arguments)
                        }
                        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
                        store(master: masterHandle, processID: processID)
                        smbLogger.notice("SMB PTY created")
                        smbLogger.notice("SMB helper process started")
                        guard fcntl(master, F_SETFL, O_NONBLOCK) == 0 else {
                            throw SMBServiceError.commandFailed
                        }
                        smbLogger.notice("Waiting for SMB password prompt")
                        var data = try Self.readPTY(master, untilFirstByte: true)
                        smbLogger.notice("SMB password prompt received")
                        try masterHandle.write(contentsOf: Data((password + "\n").utf8))
                        smbLogger.notice("SMB password input submitted")
                        smbLogger.notice("Waiting for SMB helper output")
                        data.append(try Self.readPTY(master, untilFirstByte: false))
                        var waitStatus: Int32 = 0
                        waitpid(processID, &waitStatus, 0)
                        setStatus(waitStatus)
                        smbLogger.notice("SMB helper process exited")
                        try masterHandle.close()
                        clearHandle()
                        return data
                    }.value
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    smbLogger.error("SMB discovery timeout fired")
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
            lock.lock()
            let processID = self.processID
            let master = masterFileHandle
            lock.unlock()
            if let processID {
                kill(processID, SIGKILL)
                kill(-processID, SIGKILL)
            }
            try? master?.close()
        }

        private func store(master: FileHandle, processID: pid_t) {
            lock.lock()
            masterFileHandle = master
            self.processID = processID
            lock.unlock()
        }

        private func clearHandle() {
            lock.lock()
            masterFileHandle = nil
            lock.unlock()
        }

        private func setStatus(_ waitStatus: Int32) {
            lock.lock()
            if waitStatus & 0x7F == 0 {
                status = (waitStatus >> 8) & 0xFF
            } else {
                status = 128 + (waitStatus & 0x7F)
            }
            lock.unlock()
        }

        private static func execute(executableURL: URL, arguments: [String]) -> Never {
            let argumentStrings = [executableURL.path] + arguments
            var cArguments = argumentStrings.map { strdup($0) }
            cArguments.append(nil)
            execv(cArguments[0], &cArguments)
            _exit(127)
        }

        private static func readPTY(_ fileDescriptor: Int32, untilFirstByte: Bool) throws -> Data {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
                if count > 0 {
                    data.append(buffer, count: count)
                    if untilFirstByte {
                        return data
                    }
                    continue
                }
                if count == 0 {
                    return data
                }
                guard errno == EAGAIN || errno == EWOULDBLOCK else {
                    throw SMBServiceError.commandFailed
                }
                usleep(10_000)
            }
        }
    }

    public static func arguments(
        host: String,
        username: String
    ) -> [String] {
        ["view", "//\(username)@\(host)"]
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
        smbLogger.notice("Starting mount for selected SMB share")
        var components = URLComponents()
        components.scheme = "smb"
        components.host = server.host
        components.port = server.port == 445 ? nil : server.port
        components.path = "/" + share.name
        guard let remoteURL = components.url else {
            smbLogger.error("Could not construct SMB mount URL")
            throw SMBServiceError.mountFailed(-1)
        }

        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey] = kNAUIOptionNoUI
        var mountedPaths: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            remoteURL as CFURL,
            nil,
            credentials.username as CFString,
            credentials.password as CFString,
            openOptions as CFMutableDictionary,
            nil,
            &mountedPaths
        )
        smbLogger.notice("NetFS mount returned status \(status)")
        guard status == 0 else {
            throw SMBServiceError.mountFailed(Int32(status))
        }
        guard let mountedPathArray = mountedPaths?.takeRetainedValue(),
              let mountedPath = (mountedPathArray as NSArray).firstObject as? String
        else {
            smbLogger.error("NetFS reported success without returning a mount path")
            throw SMBServiceError.mountFailed(-1)
        }
        return URL(fileURLWithPath: mountedPath, isDirectory: true)
    }
}
