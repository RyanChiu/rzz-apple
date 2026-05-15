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
    var proxySourceModeRaw: String
    var contentProxySourceModeRaw: String
    var proxyProfileID: UUID?
    var contentProxyProfileID: UUID?
    var proxyTypeRaw: String
    var proxyHost: String
    var proxyPort: Int?
    var proxyUsername: String
    var hasProxyPassword: Bool
    var folderName: String
    var createdAt: Date
    var lastFetchedAt: Date?
    var articles: [RZZBackupArticle]

    init(
        id: UUID,
        title: String,
        isTitleManuallySet: Bool,
        urlString: String,
        offlinePolicyRaw: String,
        useProxy: Bool,
        useProxyForContent: Bool,
        allowInsecureHTTPForContent: Bool,
        proxySourceModeRaw: String,
        contentProxySourceModeRaw: String,
        proxyProfileID: UUID?,
        contentProxyProfileID: UUID?,
        proxyTypeRaw: String,
        proxyHost: String,
        proxyPort: Int?,
        proxyUsername: String,
        hasProxyPassword: Bool,
        folderName: String,
        createdAt: Date,
        lastFetchedAt: Date?,
        articles: [RZZBackupArticle]
    ) {
        self.id = id
        self.title = title
        self.isTitleManuallySet = isTitleManuallySet
        self.urlString = urlString
        self.offlinePolicyRaw = offlinePolicyRaw
        self.useProxy = useProxy
        self.useProxyForContent = useProxyForContent
        self.allowInsecureHTTPForContent = allowInsecureHTTPForContent
        self.proxySourceModeRaw = proxySourceModeRaw
        self.contentProxySourceModeRaw = contentProxySourceModeRaw
        self.proxyProfileID = proxyProfileID
        self.contentProxyProfileID = contentProxyProfileID
        self.proxyTypeRaw = proxyTypeRaw
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername
        self.hasProxyPassword = hasProxyPassword
        self.folderName = folderName
        self.createdAt = createdAt
        self.lastFetchedAt = lastFetchedAt
        self.articles = articles
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isTitleManuallySet
        case urlString
        case offlinePolicyRaw
        case useProxy
        case useProxyForContent
        case allowInsecureHTTPForContent
        case proxySourceModeRaw
        case contentProxySourceModeRaw
        case proxyProfileID
        case contentProxyProfileID
        case proxyTypeRaw
        case proxyHost
        case proxyPort
        case proxyUsername
        case hasProxyPassword
        case folderName
        case createdAt
        case lastFetchedAt
        case articles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isTitleManuallySet = try container.decode(Bool.self, forKey: .isTitleManuallySet)
        urlString = try container.decode(String.self, forKey: .urlString)
        offlinePolicyRaw = try container.decode(String.self, forKey: .offlinePolicyRaw)
        useProxy = try container.decode(Bool.self, forKey: .useProxy)
        useProxyForContent = try container.decode(Bool.self, forKey: .useProxyForContent)
        allowInsecureHTTPForContent = try container.decode(Bool.self, forKey: .allowInsecureHTTPForContent)
        proxySourceModeRaw = try container.decodeIfPresent(String.self, forKey: .proxySourceModeRaw) ?? FeedProxySourceMode.custom.rawValue
        contentProxySourceModeRaw = try container.decodeIfPresent(String.self, forKey: .contentProxySourceModeRaw) ?? FeedProxySourceMode.custom.rawValue
        proxyProfileID = try container.decodeIfPresent(UUID.self, forKey: .proxyProfileID)
        contentProxyProfileID = try container.decodeIfPresent(UUID.self, forKey: .contentProxyProfileID)
        proxyTypeRaw = try container.decode(String.self, forKey: .proxyTypeRaw)
        proxyHost = try container.decode(String.self, forKey: .proxyHost)
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort)
        proxyUsername = try container.decode(String.self, forKey: .proxyUsername)
        hasProxyPassword = try container.decode(Bool.self, forKey: .hasProxyPassword)
        folderName = try container.decode(String.self, forKey: .folderName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastFetchedAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        articles = try container.decode([RZZBackupArticle].self, forKey: .articles)
    }
}

struct RZZBackupProxyProfile: Codable {
    var id: UUID
    var name: String
    var proxyTypeRaw: String
    var proxyHost: String
    var proxyPort: Int?
    var proxyUsername: String
    var hasProxyPassword: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct RZZBackupPackage: Codable {
    static let currentVersion = 2
    static let minimumSupportedVersion = 1

    var version: Int
    var exportedAt: Date
    var settings: RZZBackupSettings
    var tags: [RZZBackupTag]
    var proxyProfiles: [RZZBackupProxyProfile]
    var feeds: [RZZBackupFeed]

    enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case settings
        case tags
        case proxyProfiles
        case feeds
    }

    init(
        version: Int,
        exportedAt: Date,
        settings: RZZBackupSettings,
        tags: [RZZBackupTag],
        proxyProfiles: [RZZBackupProxyProfile],
        feeds: [RZZBackupFeed]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.tags = tags
        self.proxyProfiles = proxyProfiles
        self.feeds = feeds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(RZZBackupSettings.self, forKey: .settings)
        tags = try container.decode([RZZBackupTag].self, forKey: .tags)
        proxyProfiles = try container.decodeIfPresent([RZZBackupProxyProfile].self, forKey: .proxyProfiles) ?? []
        feeds = try container.decode([RZZBackupFeed].self, forKey: .feeds)
    }

    static var empty: RZZBackupPackage {
        RZZBackupPackage(
            version: currentVersion,
            exportedAt: Date(),
            settings: RZZBackupSettings(customFeedFolderNames: []),
            tags: [],
            proxyProfiles: [],
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
