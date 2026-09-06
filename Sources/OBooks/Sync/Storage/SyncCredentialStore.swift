import Foundation
import Security

protocol SyncCredentialStorage {
    func read() throws -> String?
    func write(_ value: String) throws
    func remove() throws
}

struct SyncCredentialStore: SyncCredentialStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.obooks.app.sync",
         kSecAttrAccount as String: "refresh-token"]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw CloudSyncError.message("读取钥匙串失败: \(status)")
        }
        return token
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CloudSyncError.message("写入钥匙串失败") }
        } else if status != errSecSuccess { throw CloudSyncError.message("更新钥匙串失败: \(status)") }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw CloudSyncError.message("删除钥匙串凭据失败: \(status)") }
    }
}
