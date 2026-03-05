import Foundation

struct ParsedFeed {
    var title: String
    var items: [ParsedItem]
}

struct ParsedItem {
    var guid: String
    var title: String
    var summary: String
    var link: String
    var publishedAt: Date?
}

enum RSSServiceError: LocalizedError {
    case badResponse
    case httpStatus(Int)
    case invalidData
    case parseFailed(String)
    case networkResolutionFailed(host: String, systemPath: String, directPath: String, webKitPath: String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Feed request failed."
        case .httpStatus(let code):
            return "Feed request failed with HTTP \(code)."
        case .invalidData:
            return "Feed data is invalid."
        case .parseFailed(let reason):
            return "Feed parse failed: \(reason)"
        case .networkResolutionFailed(let host, let systemPath, let directPath, let webKitPath):
            return "Cannot resolve host '\(host)'. System path: \(systemPath). Direct path: \(directPath). WebKit path: \(webKitPath)."
        }
    }
}

enum RSSService {
    private static let articleRequestTimeout: TimeInterval = 45

    static func fetchFeed(from url: URL, proxy: FeedProxyConfiguration? = nil) async throws -> ParsedFeed {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await dataAndResponse(for: request, proxy: proxy, bypassSystemProxy: false)
            return try parseHTTPResponse(data: data, response: response)
        } catch {
            // Some environments have broken system proxy/PAC DNS.
            // If no feed-level proxy is configured, retry once with proxies disabled.
            if proxy == nil, let urlError = error as? URLError, urlError.code == .cannotFindHost {
                do {
                    let (data, response) = try await dataAndResponse(for: request, proxy: nil, bypassSystemProxy: true)
                    return try parseHTTPResponse(data: data, response: response)
                } catch let directError {
                    guard shouldUseWebKitFallback else {
                        throw RSSServiceError.networkResolutionFailed(
                            host: url.host ?? "unknown",
                            systemPath: describeNetworkError(urlError),
                            directPath: describeNetworkError(directError),
                            webKitPath: "Skipped on iOS Simulator for performance."
                        )
                    }

                    do {
                        let fallbackTimeout = min(8, request.timeoutInterval)
                        let data = try await WebKitRSSFallback.fetchData(from: url, timeout: fallbackTimeout)
                        return try FeedParser.parse(data: data)
                    } catch let webKitError {
                        throw RSSServiceError.networkResolutionFailed(
                            host: url.host ?? "unknown",
                            systemPath: describeNetworkError(urlError),
                            directPath: describeNetworkError(directError),
                            webKitPath: describeNetworkError(webKitError)
                        )
                    }
                }
            }

            // If a manual proxy is configured and DNS still fails in URLSession, try WebKit once.
            if proxy != nil, let urlError = error as? URLError, urlError.code == .cannotFindHost {
                guard shouldUseWebKitFallback else {
                    throw RSSServiceError.networkResolutionFailed(
                        host: url.host ?? "unknown",
                        systemPath: describeNetworkError(urlError),
                        directPath: "N/A (manual proxy enabled)",
                        webKitPath: "Skipped on iOS Simulator for performance."
                    )
                }

                do {
                    let fallbackTimeout = min(8, request.timeoutInterval)
                    let data = try await WebKitRSSFallback.fetchData(from: url, timeout: fallbackTimeout)
                    return try FeedParser.parse(data: data)
                } catch let webKitError {
                    throw RSSServiceError.networkResolutionFailed(
                        host: url.host ?? "unknown",
                        systemPath: describeNetworkError(urlError),
                        directPath: "N/A (manual proxy enabled)",
                        webKitPath: describeNetworkError(webKitError)
                    )
                }
            }
            throw error
        }
    }

    static func fetchArticleHTML(
        from url: URL,
        proxy: FeedProxyConfiguration? = nil,
        allowInsecureHTTPInWebContent: Bool = false
    ) async throws -> String {
        do {
            return try await fetchArticleHTMLAttempt(from: url, proxy: proxy)
        } catch {
            if let urlError = error as? URLError,
               urlError.code == .appTransportSecurityRequiresSecureConnection {
                if let secureURL = upgradedHTTPSURL(from: url) {
                    do {
                        return try await fetchArticleHTMLAttempt(from: secureURL, proxy: proxy)
                    } catch {
                        if allowInsecureHTTPInWebContent, url.scheme?.lowercased() == "http" {
                            return try await WebKitRSSFallback.fetchHTML(from: url, timeout: articleRequestTimeout)
                        }
                        throw error
                    }
                }

                if allowInsecureHTTPInWebContent, url.scheme?.lowercased() == "http" {
                    return try await WebKitRSSFallback.fetchHTML(from: url, timeout: articleRequestTimeout)
                }
            }
            throw error
        }
    }

    private static func fetchArticleHTMLAttempt(from url: URL, proxy: FeedProxyConfiguration?) async throws -> String {
        let request = makeArticleRequest(url: url)
        do {
            let (data, response) = try await dataAndResponse(for: request, proxy: proxy, bypassSystemProxy: false)
            return try parseHTMLResponse(data: data, response: response)
        } catch {
            if proxy == nil, let urlError = error as? URLError, urlError.code == .cannotFindHost {
                let (data, response) = try await dataAndResponse(for: request, proxy: nil, bypassSystemProxy: true)
                return try parseHTMLResponse(data: data, response: response)
            }
            throw error
        }
    }

    private static func makeArticleRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = articleRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private static func upgradedHTTPSURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http" else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static func dataAndResponse(
        for request: URLRequest,
        proxy: FeedProxyConfiguration?,
        bypassSystemProxy: Bool
    ) async throws -> (Data, URLResponse) {
        let session = makeSession(proxy: proxy, bypassSystemProxy: bypassSystemProxy)
        return try await session.data(for: request)
    }

    private static func parseHTTPResponse(data: Data, response: URLResponse) throws -> ParsedFeed {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse {
                throw RSSServiceError.httpStatus(http.statusCode)
            }
            throw RSSServiceError.badResponse
        }
        return try FeedParser.parse(data: data)
    }

    private static func parseHTMLResponse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let http = response as? HTTPURLResponse {
                throw RSSServiceError.httpStatus(http.statusCode)
            }
            throw RSSServiceError.badResponse
        }

        if let html = String(data: data, encoding: .utf8), !html.isEmpty {
            return html
        }
        if let html = String(data: data, encoding: .unicode), !html.isEmpty {
            return html
        }
        if let html = String(data: data, encoding: .isoLatin1), !html.isEmpty {
            return html
        }
        throw RSSServiceError.invalidData
    }

    private static func describeNetworkError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "\(urlError.localizedDescription) (\(urlError.code.rawValue))"
        }
        return error.localizedDescription
    }

    private static var shouldUseWebKitFallback: Bool {
        #if os(iOS) && targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    private static func makeSession(proxy: FeedProxyConfiguration?, bypassSystemProxy: Bool) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30

        if bypassSystemProxy {
            config.connectionProxyDictionary = [
                "HTTPEnable": 0,
                "HTTPSEnable": 0,
                "SOCKSEnable": 0
            ]
            return URLSession(configuration: config)
        }

        guard let proxy else {
            return URLSession(configuration: config)
        }

        var dictionary: [AnyHashable: Any] = [:]

        switch proxy.type {
        case .http:
            dictionary["HTTPEnable"] = 1
            dictionary["HTTPProxy"] = proxy.host
            dictionary["HTTPPort"] = proxy.port
            dictionary["HTTPSEnable"] = 1
            dictionary["HTTPSProxy"] = proxy.host
            dictionary["HTTPSPort"] = proxy.port
        case .socks5:
            dictionary["SOCKSEnable"] = 1
            dictionary["SOCKSProxy"] = proxy.host
            dictionary["SOCKSPort"] = proxy.port
        }

        if let username = proxy.username, !username.isEmpty {
            dictionary["ProxyUsername"] = username
        }
        if let password = proxy.password, !password.isEmpty {
            dictionary["ProxyPassword"] = password
        }

        config.connectionProxyDictionary = dictionary
        return URLSession(configuration: config)
    }
}

private enum FeedParser {
    static func parse(data: Data) throws -> ParsedFeed {
        guard !data.isEmpty else {
            throw RSSServiceError.invalidData
        }

        let delegate = XMLFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let parserReason = parser.parserError?.localizedDescription ?? "Unknown XML parsing error"
            throw RSSServiceError.parseFailed(parserReason)
        }

        return ParsedFeed(title: delegate.feedTitle, items: delegate.items)
    }
}

private final class XMLFeedParserDelegate: NSObject, XMLParserDelegate {
    private(set) var feedTitle: String = ""
    private(set) var items: [ParsedItem] = []

    private var currentElement: String = ""
    private var currentValue: String = ""

    private var inItem = false
    private var inEntry = false

    private var itemTitle: String = ""
    private var itemGuid: String = ""
    private var itemSummary: String = ""
    private var itemLink: String = ""
    private var itemPubDate: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        currentValue = ""

        if currentElement == "item" {
            inItem = true
            resetItemBuffers()
        }

        if currentElement == "entry" {
            inEntry = true
            resetItemBuffers()
        }

        if (inItem || inEntry), currentElement == "link", let href = attributeDict["href"] {
            itemLink = href.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem || inEntry {
            switch name {
            case "title":
                if !value.isEmpty { itemTitle = value }
            case "guid", "id":
                if !value.isEmpty { itemGuid = value }
            case "description", "summary", "content":
                if !value.isEmpty && itemSummary.isEmpty { itemSummary = value }
            case "link":
                if !value.isEmpty && itemLink.isEmpty { itemLink = value }
            case "pubdate", "published", "updated":
                if !value.isEmpty && itemPubDate.isEmpty { itemPubDate = value }
            default:
                break
            }
        } else if name == "title", feedTitle.isEmpty, !value.isEmpty {
            feedTitle = value
        }

        if (name == "item" && inItem) || (name == "entry" && inEntry) {
            let parsed = ParsedItem(
                guid: itemGuid,
                title: itemTitle.isEmpty ? "(No title)" : itemTitle,
                summary: itemSummary,
                link: itemLink,
                publishedAt: DateParsing.parse(itemPubDate)
            )
            items.append(parsed)
            inItem = false
            inEntry = false
        }
    }

    private func resetItemBuffers() {
        itemTitle = ""
        itemGuid = ""
        itemSummary = ""
        itemLink = ""
        itemPubDate = ""
    }
}

private enum DateParsing {
    private static let formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: trimmed)
    }
}
