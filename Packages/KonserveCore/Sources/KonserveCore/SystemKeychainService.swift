import Foundation
import Security

public enum KeychainServiceError: Error {
    case operationFailed(OSStatus)
    case invalidPasswordEncoding
}

public struct SystemKeychainService: KeychainService {
    public init() {}

    public func save(_ credentials: SMBCredentials, for server: SMBServer) throws {
        guard let data = credentials.password.data(using: .utf8) else {
            throw KeychainServiceError.invalidPasswordEncoding
        }
        let query = baseQuery(server: server, username: credentials.username)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.operationFailed(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainServiceError.operationFailed(status)
        }
    }

    public func credentials(for server: SMBServer, username: String) throws -> SMBCredentials? {
        var query = baseQuery(server: server, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.operationFailed(status)
        }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.invalidPasswordEncoding
        }
        return SMBCredentials(username: username, password: password)
    }

    public func firstCredentials(for server: SMBServer) throws -> SMBCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: server),
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.operationFailed(status)
        }
        guard let item = result as? [String: Any],
              let username = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw KeychainServiceError.invalidPasswordEncoding
        }
        return SMBCredentials(username: username, password: password)
    }

    public func deleteCredentials(for server: SMBServer, username: String) throws {
        let status = SecItemDelete(baseQuery(server: server, username: username) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.operationFailed(status)
        }
    }

    private func baseQuery(server: SMBServer, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: server),
            kSecAttrAccount as String: username
        ]
    }

    private func service(for server: SMBServer) -> String {
        "Konserve.credentials.v2/\(server.id)"
    }
}
