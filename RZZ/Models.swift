import Foundation
import SwiftData

enum ProxyPasswordMigrationResult {
    case notNeeded
    case migrated
    case clearedWithoutMigration
}

enum FeedOfflinePolicy: String, CaseIterable, Codable, Identifiable {
    case off
    case metadataOnly
    case fullContent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .metadataOnly:
            return "Metadata Only"
        case .fullContent:
            return "Full Content"
        }
    }
}

enum ArticleOfflineStatus: String, Codable {
    case notCached
    case caching
    case cached
    case failed
    case evicted
}

enum FeedProxyType: String, CaseIterable, Codable, Identifiable {
    case http
    case socks5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .http:
            return "HTTP(S)"
        case .socks5:
            return "SOCKS5"
        }
    }
}

struct FeedProxyConfiguration {
    let type: FeedProxyType
    let host: String
    let port: Int
    let username: String?
    let password: String?
}

@Model
final class Feed {
    var id: UUID = UUID()
    var title: String = ""
    var isTitleManuallySet: Bool = true
    var urlString: String = ""
    var offlinePolicyRaw: String = FeedOfflinePolicy.off.rawValue
    var useProxy: Bool = false
    var useProxyForContent: Bool = false
    var allowInsecureHTTPForContent: Bool = false
    var proxyTypeRaw: String = FeedProxyType.http.rawValue
    var proxyHost: String = ""
    var proxyPort: Int? = nil
    var proxyUsername: String = ""
    var proxyPassword: String = ""
    var folderName: String = "New Added"
    var createdAt: Date = Date()
    var lastFetchedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article]

    init(
        title: String,
        urlString: String,
        folderName: String = "New Added",
        isTitleManuallySet: Bool = true
    ) {
        self.title = title
        self.isTitleManuallySet = isTitleManuallySet
        self.urlString = urlString
        self.folderName = folderName
        self.lastFetchedAt = nil
        self.articles = []
    }

    var url: URL? {
        parseSupportedWebURL(urlString)
    }

    var proxyType: FeedProxyType {
        get { FeedProxyType(rawValue: proxyTypeRaw) ?? .http }
        set { proxyTypeRaw = newValue.rawValue }
    }

    var offlinePolicy: FeedOfflinePolicy {
        get { FeedOfflinePolicy(rawValue: offlinePolicyRaw) ?? .off }
        set { offlinePolicyRaw = newValue.rawValue }
    }

    var proxyConfiguration: FeedProxyConfiguration? {
        guard useProxy else { return nil }
        return makeProxyConfiguration()
    }

    var contentProxyConfiguration: FeedProxyConfiguration? {
        guard useProxyForContent else { return nil }
        return makeProxyConfiguration()
    }

    private func makeProxyConfiguration() -> FeedProxyConfiguration? {
        let host = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        guard let port = proxyPort, (1...65535).contains(port) else { return nil }

        let username = proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = proxyPasswordValue

        return FeedProxyConfiguration(
            type: proxyType,
            host: host,
            port: port,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
    }

    var proxyPasswordValue: String {
        if let secure = SecureSecretStore.readPassword(forAccount: proxyPasswordAccount), !secure.isEmpty {
            return secure
        }
        return proxyPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func migrateLegacyProxyPasswordIfNeeded() -> ProxyPasswordMigrationResult {
        let legacy = proxyPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else { return .notNeeded }

        if SecureSecretStore.readPassword(forAccount: proxyPasswordAccount) == nil {
            guard SecureSecretStore.savePassword(legacy, forAccount: proxyPasswordAccount) else {
                // Strict mode: do not retain plaintext fallback.
                proxyPassword = ""
                return .clearedWithoutMigration
            }
        }

        proxyPassword = ""
        return .migrated
    }

    @discardableResult
    func setProxyPasswordSecurely(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            SecureSecretStore.deletePassword(forAccount: proxyPasswordAccount)
            proxyPassword = ""
            return true
        }

        if SecureSecretStore.savePassword(trimmed, forAccount: proxyPasswordAccount) {
            proxyPassword = ""
            return true
        }

        return false
    }

    func clearSecureProxyPassword() {
        SecureSecretStore.deletePassword(forAccount: proxyPasswordAccount)
        proxyPassword = ""
    }

    private var proxyPasswordAccount: String {
        "feed-proxy-password.\(id.uuidString.lowercased())"
    }
}

private func parseSupportedWebURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
    guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return nil }
    return url
}

@Model
final class Article {
    var id: UUID = UUID()
    var guid: String = ""
    var title: String = ""
    var summary: String = ""
    var link: String = ""
    var publishedAt: Date?
    var createdAt: Date = Date()
    var isRead: Bool = false
    var isStarred: Bool = false
    var readingScrollProgress: Double = 0
    var offlineStatusRaw: String = ArticleOfflineStatus.notCached.rawValue
    var offlineCachedHTML: String = ""
    var offlineCachedBytes: Int = 0
    var offlineCachedAt: Date?
    var offlineLastError: String = ""
    @Relationship(inverse: \Tag.articles)
    var tags: [Tag] = []

    var feed: Feed?

    init(
        guid: String,
        title: String,
        summary: String,
        link: String,
        publishedAt: Date?,
        feed: Feed
    ) {
        self.guid = guid
        self.title = title
        self.summary = summary
        self.link = link
        self.publishedAt = publishedAt
        self.feed = feed
        self.tags = []
    }

    var dedupeKey: String {
        if !guid.isEmpty { return "guid:\(guid)" }
        if !link.isEmpty { return "link:\(link)" }
        return "title:\(title):\(publishedAt?.timeIntervalSince1970 ?? 0)"
    }

    var offlineStatus: ArticleOfflineStatus {
        get { ArticleOfflineStatus(rawValue: offlineStatusRaw) ?? .notCached }
        set { offlineStatusRaw = newValue.rawValue }
    }

    var hasOfflineContent: Bool {
        offlineStatus == .cached && !offlineCachedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship
    var articles: [Article] = []

    init(name: String) {
        self.name = name
        self.createdAt = Date()
        self.articles = []
    }
}
