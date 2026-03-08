import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RZZBackupSettings: Codable {
    var customFeedFolderNames: [String]
}

struct RZZBackupTag: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
}

struct RZZBackupArticle: Codable {
    var id: UUID
    var guid: String
    var title: String
    var summary: String
    var link: String
    var publishedAt: Date?
    var createdAt: Date
    var isRead: Bool
    var isStarred: Bool
    var readingScrollProgress: Double
    var offlineStatusRaw: String
    var offlineCachedHTML: String
    var offlineCachedBytes: Int
    var offlineCachedAt: Date?
    var offlineLastError: String
    var tagIDs: [UUID]
}

struct RZZBackupFeed: Codable {
    var id: UUID
    var title: String
    var isTitleManuallySet: Bool
    var urlString: String
    var offlinePolicyRaw: String
    var useProxy: Bool
    var useProxyForContent: Bool
    var allowInsecureHTTPForContent: Bool
    var proxyTypeRaw: String
    var proxyHost: String
    var proxyPort: Int?
    var proxyUsername: String
    var hasProxyPassword: Bool
    var folderName: String
    var createdAt: Date
    var lastFetchedAt: Date?
    var articles: [RZZBackupArticle]
}

struct RZZBackupPackage: Codable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var settings: RZZBackupSettings
    var tags: [RZZBackupTag]
    var feeds: [RZZBackupFeed]

    static var empty: RZZBackupPackage {
        RZZBackupPackage(
            version: currentVersion,
            exportedAt: Date(),
            settings: RZZBackupSettings(customFeedFolderNames: []),
            tags: [],
            feeds: []
        )
    }
}

enum RZZBackupCodec {
    static func encode(_ package: RZZBackupPackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }

    static func decode(_ data: Data) throws -> RZZBackupPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RZZBackupPackage.self, from: data)
    }
}

struct RZZBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var package: RZZBackupPackage

    init(package: RZZBackupPackage = .empty) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.package = try RZZBackupCodec.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try RZZBackupCodec.encode(package)
        return .init(regularFileWithContents: data)
    }
}
