import Foundation
import Security

enum KeychainError: Error, Sendable {
  case unexpectedStatus(OSStatus)
}

enum Keychain {
  private static let service = "dev.sebstaq.opencode.remote"

  static func setPassword(_ password: String, for id: UUID) throws {
    try deletePassword(for: id)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
      kSecValueData as String: Data(password.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  static func password(for id: UUID) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = item as? Data else {
      throw KeychainError.unexpectedStatus(status)
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func deletePassword(for id: UUID) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}
