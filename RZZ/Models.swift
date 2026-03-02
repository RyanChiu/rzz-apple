import Foundation
import SwiftData

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
    var urlString: String = ""
    var useProxy: Bool = false
    var useProxyForContent: Bool = false
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

    init(title: String, urlString: String, folderName: String = "New Added") {
        self.title = title
        self.urlString = urlString
        self.folderName = folderName
        self.lastFetchedAt = nil
        self.articles = []
    }

    var url: URL? {
        URL(string: urlString)
    }

    var proxyType: FeedProxyType {
        get { FeedProxyType(rawValue: proxyTypeRaw) ?? .http }
        set { proxyTypeRaw = newValue.rawValue }
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
        let password = proxyPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        return FeedProxyConfiguration(
            type: proxyType,
            host: host,
            port: port,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
    }
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
