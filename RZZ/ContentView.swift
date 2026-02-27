import SwiftUI
import SwiftData
import WebKit

private enum SidebarSelection: Hashable {
    case all
    case starred
    case feed(PersistentIdentifier)
    case article(PersistentIdentifier)
}

private struct FeedEditDraft: Identifiable {
    let id = UUID()
    let feedID: PersistentIdentifier
    let title: String
    let urlString: String
    let useProxy: Bool
    let proxyType: FeedProxyType
    let proxyHost: String
    let proxyPort: Int?
    let proxyUsername: String
    let proxyPassword: String
}

private struct FeedFormValues {
    let title: String
    let urlString: String
    let useProxy: Bool
    let proxyType: FeedProxyType
    let proxyHost: String
    let proxyPort: Int?
    let proxyUsername: String
    let proxyPassword: String
}

private struct FeedDeletionRequest: Identifiable {
    let id = UUID()
    let feedIDs: [PersistentIdentifier]
    let message: String
    let actionTitle: String
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Feed.createdAt, order: .reverse)]) private var feeds: [Feed]
    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse), SortDescriptor(\Article.createdAt, order: .reverse)]) private var articles: [Article]

    @State private var sidebarSelection: SidebarSelection? = .all
    @State private var expandedFeedIDs: Set<PersistentIdentifier> = []
    @State private var showAddFeed = false
    @State private var editDraft: FeedEditDraft?
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var pendingDeletionRequest: FeedDeletionRequest?

    private var displayedArticles: [Article] {
        let sourceArticles = filteredArticles(articles)
        switch sidebarSelection {
        case .starred:
            return sourceArticles.sorted { lhs, rhs in
                (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
            }
        case .feed(let id):
            return sourceArticles
                .filter { $0.feed?.persistentModelID == id }
                .sorted { lhs, rhs in
                    (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
                }
        case .article(let articleID):
            guard let article = sourceArticles.first(where: { $0.persistentModelID == articleID }),
                  let feedID = article.feed?.persistentModelID else {
                return []
            }
            return sourceArticles
                .filter { $0.feed?.persistentModelID == feedID }
                .sorted { lhs, rhs in
                    (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
                }
        default:
            return sourceArticles.sorted { lhs, rhs in
                (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
            }
        }
    }

    private var selectedArticle: Article? {
        guard case .article(let articleID) = sidebarSelection else { return nil }
        return articles.first(where: { $0.persistentModelID == articleID })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("Filters") {
                    Label("All Articles", systemImage: "doc.text")
                        .tag(SidebarSelection.all)
                    Label("Starred", systemImage: "star.fill")
                        .tag(SidebarSelection.starred)
                }

                Section("Feeds") {
                    ForEach(feeds) { feed in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedFeedIDs.contains(feed.persistentModelID) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedFeedIDs.insert(feed.persistentModelID)
                                    } else {
                                        expandedFeedIDs.remove(feed.persistentModelID)
                                    }
                                }
                            )
                        ) {
                            ForEach(feedArticles(for: feed)) { article in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(article.isRead ? Color.clear : Color.blue)
                                        .frame(width: 7, height: 7)
                                    Text(article.title)
                                        .lineLimit(2)
                                        .font(.subheadline)
                                        .foregroundStyle(article.isRead ? .secondary : .primary)
                                }
                                .contentShape(Rectangle())
                                .tag(SidebarSelection.article(article.persistentModelID))
                                .onTapGesture {
                                    sidebarSelection = .article(article.persistentModelID)
                                    if !article.isRead {
                                        article.isRead = true
                                    }
                                }
                                .contextMenu {
                                    Button(article.isRead ? "Mark Unread" : "Mark Read") {
                                        article.isRead.toggle()
                                    }
                                    Button(article.isStarred ? "Unstar" : "Star") {
                                        article.isStarred.toggle()
                                    }
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.title.isEmpty ? feed.urlString : feed.title)
                                Text(feed.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                sidebarSelection = .feed(feed.persistentModelID)
                            }
                            .contextMenu {
                                Button("Edit") {
                                    beginEdit(feed: feed)
                                }
                                Button("Refresh") {
                                    Task { await refreshSingleFeed(feed) }
                                }
                                Button("Delete", role: .destructive) {
                                    requestDeleteFeed(feed)
                                }
                            }
                        }
                        .tag(SidebarSelection.feed(feed.persistentModelID))
                    }
                    .onDelete(perform: deleteFeeds)
                }
            }
            .navigationTitle("RZZ")
        } detail: {
            if let selectedArticle {
                ArticleDetailView(article: selectedArticle)
            } else if displayedArticles.isEmpty {
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "newspaper",
                    description: Text("Select a feed and article to start reading.")
                )
            } else {
                List {
                    ForEach(displayedArticles) { article in
                        ArticleRow(article: article)
                            .onTapGesture {
                                sidebarSelection = .article(article.persistentModelID)
                                if !article.isRead {
                                    article.isRead = true
                                }
                            }
                    }
                }
                .navigationTitle(navigationTitle)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showAddFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }

                Button {
                    Task { await refreshCurrentSelection() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing || feeds.isEmpty)

                if let selectedFeed {
                    Button {
                        beginEdit(feed: selectedFeed)
                    } label: {
                        Label("Edit Feed", systemImage: "pencil")
                    }
                }
            }
        }
        .onChange(of: articles.map(\.persistentModelID)) { _, newIDs in
            if case .article(let selectedID) = sidebarSelection, !newIDs.contains(selectedID) {
                sidebarSelection = .all
            }
        }
        .sheet(isPresented: $showAddFeed) {
            FeedFormView(
                modeTitle: "Add Feed",
                saveButtonTitle: "Save",
                initialTitle: "",
                initialURLString: "",
                initialUseProxy: false,
                initialProxyType: .http,
                initialProxyHost: "",
                initialProxyPort: nil,
                initialProxyUsername: "",
                initialProxyPassword: ""
            ) { values in
                Task {
                    await addFeed(values: values)
                }
            }
        }
        .sheet(item: $editDraft) { draft in
            FeedFormView(
                modeTitle: "Edit Feed",
                saveButtonTitle: "Update",
                initialTitle: draft.title,
                initialURLString: draft.urlString,
                initialUseProxy: draft.useProxy,
                initialProxyType: draft.proxyType,
                initialProxyHost: draft.proxyHost,
                initialProxyPort: draft.proxyPort,
                initialProxyUsername: draft.proxyUsername,
                initialProxyPassword: draft.proxyPassword
            ) { values in
                Task {
                    await updateFeed(feedID: draft.feedID, values: values)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isRefreshing {
                ProgressView("Refreshing feeds...")
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 12)
            }
        }
        .alert("Refresh Error", isPresented: Binding(get: {
            refreshError != nil
        }, set: { newValue in
            if !newValue { refreshError = nil }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshError ?? "Unknown error")
        }
        .confirmationDialog(
            "Delete Feed?",
            isPresented: Binding(
                get: { pendingDeletionRequest != nil },
                set: { newValue in
                    if !newValue {
                        pendingDeletionRequest = nil
                    }
                }
            ),
            presenting: pendingDeletionRequest
        ) { request in
            Button(request.actionTitle, role: .destructive) {
                performDeletion(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
    }

    private var navigationTitle: String {
        switch sidebarSelection {
        case .starred:
            return "Starred"
        case .article(let articleID):
            return articles.first(where: { $0.persistentModelID == articleID })?.feed?.title ?? "Article"
        case .feed(let id):
            return feeds.first(where: { $0.persistentModelID == id })?.title ?? "Feed"
        default:
            return "All Articles"
        }
    }

    private var selectedFeed: Feed? {
        switch sidebarSelection {
        case .feed(let id):
            return feeds.first(where: { $0.persistentModelID == id })
        case .article(let articleID):
            return articles.first(where: { $0.persistentModelID == articleID })?.feed
        default:
            return nil
        }
    }

    @MainActor
    private func addFeed(values: FeedFormValues) async {
        let trimmedURL = values.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme?.hasPrefix("http") == true else {
            refreshError = "Please input a valid http(s) feed URL."
            return
        }

        if feeds.contains(where: { $0.urlString.caseInsensitiveCompare(trimmedURL) == .orderedSame }) {
            refreshError = "This feed is already added."
            return
        }
        guard validateProxyValues(values) else { return }

        let trimmedTitle = values.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? (url.host ?? trimmedURL) : trimmedTitle

        let feed = Feed(title: displayTitle, urlString: trimmedURL)
        applyProxyValues(values, to: feed)
        modelContext.insert(feed)
        sidebarSelection = .feed(feed.persistentModelID)

        await refreshSingleFeed(feed)
    }

    @MainActor
    private func updateFeed(feedID: PersistentIdentifier, values: FeedFormValues) async {
        guard let feed = feeds.first(where: { $0.persistentModelID == feedID }) else { return }

        let trimmedURL = values.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme?.hasPrefix("http") == true else {
            refreshError = "Please input a valid http(s) feed URL."
            return
        }

        if feeds.contains(where: {
            $0.persistentModelID != feed.persistentModelID &&
            $0.urlString.caseInsensitiveCompare(trimmedURL) == .orderedSame
        }) {
            refreshError = "This feed URL is already used by another subscription."
            return
        }
        guard validateProxyValues(values) else { return }

        let trimmedTitle = values.title.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.title = trimmedTitle.isEmpty ? (url.host ?? trimmedURL) : trimmedTitle
        feed.urlString = trimmedURL
        applyProxyValues(values, to: feed)

        try? modelContext.save()
        await refreshSingleFeed(feed)
    }

    @MainActor
    private func refreshCurrentSelection() async {
        switch sidebarSelection {
        case .feed(let id):
            guard let feed = feeds.first(where: { $0.persistentModelID == id }) else { return }
            await refreshSingleFeed(feed)
        case .article(let articleID):
            guard let article = articles.first(where: { $0.persistentModelID == articleID }),
                  let feed = article.feed else { return }
            await refreshSingleFeed(feed)
        case .all, .starred, .none:
            await refreshAllFeeds()
        }
    }

    @MainActor
    private func refreshAllFeeds() async {
        guard !feeds.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for feed in feeds {
            await refreshSingleFeed(feed, showGlobalSpinner: false)
        }
    }

    @MainActor
    private func refreshSingleFeed(_ feed: Feed, showGlobalSpinner: Bool = true) async {
        guard let url = feed.url else {
            refreshError = "Invalid URL for feed: \(feed.title)"
            return
        }

        if showGlobalSpinner {
            isRefreshing = true
        }
        defer {
            if showGlobalSpinner {
                isRefreshing = false
            }
        }

        do {
            let parsedFeed = try await RSSService.fetchFeed(from: url, proxy: feed.proxyConfiguration)
            if !parsedFeed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                feed.title = parsedFeed.title
            }

            var existingKeys = Set(feed.articles.map(\.dedupeKey))
            var newArticles: [Article] = []
            newArticles.reserveCapacity(parsedFeed.items.count)

            for item in parsedFeed.items {
                let guid = item.guid.trimmingCharacters(in: .whitespacesAndNewlines)
                let link = item.link.trimmingCharacters(in: .whitespacesAndNewlines)
                let dedupeKey: String

                if !guid.isEmpty {
                    dedupeKey = "guid:\(guid)"
                } else if !link.isEmpty {
                    dedupeKey = "link:\(link)"
                } else {
                    dedupeKey = "title:\(item.title):\(item.publishedAt?.timeIntervalSince1970 ?? 0)"
                }

                if existingKeys.contains(dedupeKey) { continue }
                existingKeys.insert(dedupeKey)

                let article = Article(
                    guid: guid,
                    title: item.title,
                    summary: item.summary,
                    link: link,
                    publishedAt: item.publishedAt,
                    feed: feed
                )
                newArticles.append(article)
            }

            for article in newArticles {
                modelContext.insert(article)
            }

            feed.lastFetchedAt = Date()
            try? modelContext.save()
        } catch {
            if let urlError = error as? URLError, urlError.code == .cannotFindHost {
                refreshError = "DNS could not resolve host '\(url.host ?? "unknown")' (\(urlError.code.rawValue)). Try enabling proxy for this feed or check your network DNS settings."
            } else {
                refreshError = error.localizedDescription
            }
        }
    }

    private func deleteFeed(_ feed: Feed) {
        switch sidebarSelection {
        case .feed(let id):
            if id == feed.persistentModelID {
                sidebarSelection = .all
            }
        case .article(let articleID):
            if feed.articles.contains(where: { $0.persistentModelID == articleID }) {
                sidebarSelection = .all
            }
        default:
            break
        }
        modelContext.delete(feed)
        try? modelContext.save()
    }

    private func deleteFeeds(at offsets: IndexSet) {
        let ids = offsets.map { feeds[$0].persistentModelID }
        requestDeleteFeeds(ids: ids)
    }

    private func requestDeleteFeed(_ feed: Feed) {
        let feedName = feed.title.isEmpty ? feed.urlString : feed.title
        pendingDeletionRequest = FeedDeletionRequest(
            feedIDs: [feed.persistentModelID],
            message: "This will permanently remove '\(feedName)' and all cached articles.",
            actionTitle: "Delete"
        )
    }

    private func requestDeleteFeeds(ids: [PersistentIdentifier]) {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return }

        if uniqueIDs.count == 1,
           let feed = feeds.first(where: { $0.persistentModelID == uniqueIDs[0] }) {
            requestDeleteFeed(feed)
            return
        }

        pendingDeletionRequest = FeedDeletionRequest(
            feedIDs: uniqueIDs,
            message: "This will permanently remove \(uniqueIDs.count) feeds and all cached articles.",
            actionTitle: "Delete \(uniqueIDs.count) Feeds"
        )
    }

    private func performDeletion(_ request: FeedDeletionRequest) {
        for id in request.feedIDs {
            guard let feed = feeds.first(where: { $0.persistentModelID == id }) else { continue }
            deleteFeed(feed)
        }
        pendingDeletionRequest = nil
    }

    private func beginEdit(feed: Feed) {
        editDraft = FeedEditDraft(
            feedID: feed.persistentModelID,
            title: feed.title,
            urlString: feed.urlString,
            useProxy: feed.useProxy,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPassword
        )
    }

    private func applyProxyValues(_ values: FeedFormValues, to feed: Feed) {
        feed.useProxy = values.useProxy
        feed.proxyType = values.proxyType
        feed.proxyHost = values.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.proxyPort = values.proxyPort
        feed.proxyUsername = values.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.proxyPassword = values.proxyPassword
    }

    private func validateProxyValues(_ values: FeedFormValues) -> Bool {
        guard values.useProxy else { return true }

        if values.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshError = "Proxy is enabled. Please input proxy host."
            return false
        }

        guard let port = values.proxyPort, (1...65535).contains(port) else {
            refreshError = "Proxy is enabled. Please input a valid proxy port (1-65535)."
            return false
        }
        _ = port

        return true
    }

    private func feedArticles(for feed: Feed) -> [Article] {
        filteredArticles(feed.articles).sorted { lhs, rhs in
            (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
        }
    }

    private func filteredArticles(_ source: [Article]) -> [Article] {
        switch sidebarSelection {
        case .starred:
            return source.filter(\.isStarred)
        default:
            return source
        }
    }
}

private struct ArticleRow: View {
    @Bindable var article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 12)

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }

                if !article.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }

            if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                Text(feedTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !article.summary.isEmpty {
                Text(HTMLText.makePreview(from: article.summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ArticleDetailView: View {
    @Bindable var article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(article.title)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Button {
                    article.isRead.toggle()
                } label: {
                    Label(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "envelope.badge" : "envelope.open")
                }

                Button {
                    article.isStarred.toggle()
                } label: {
                    Label(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star")
                }

                if let url = URL(string: article.link), !article.link.isEmpty {
                    Link(destination: url) {
                        Label("Open Original", systemImage: "safari")
                    }
                }
            }
            .buttonStyle(.bordered)

            if let date = article.publishedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if article.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No summary available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ArticleHTMLView(htmlBody: article.summary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .navigationTitle("Article")
    }
}

private struct ArticleHTMLView: View {
    let htmlBody: String

    var body: some View {
        HTMLWebView(html: htmlDocument)
            .background(Color.clear)
    }

    private var htmlDocument: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light dark; }
            body {
              font: -apple-system-body;
              line-height: 1.55;
              margin: 0;
              padding: 0;
              word-break: break-word;
            }
            img, video, iframe {
              max-width: 100%;
              height: auto;
              border-radius: 8px;
            }
            pre, code {
              white-space: pre-wrap;
              word-break: break-word;
            }
            a { text-decoration: none; }
          </style>
        </head>
        <body>
        \(htmlBody)
        </body>
        </html>
        """
    }
}

#if os(macOS)
private struct HTMLWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct HTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#endif

private enum HTMLText {
    static func makePreview(from raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let unescaped = decodeEntities(withoutTags)
        let compacted = unescaped.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return compacted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

private struct FeedFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var urlString: String
    @State private var useProxy: Bool
    @State private var proxyType: FeedProxyType
    @State private var proxyHost: String
    @State private var proxyPortString: String
    @State private var proxyUsername: String
    @State private var proxyPassword: String

    let modeTitle: String
    let saveButtonTitle: String
    let initialTitle: String
    let initialURLString: String
    let initialUseProxy: Bool
    let initialProxyType: FeedProxyType
    let initialProxyHost: String
    let initialProxyPort: Int?
    let initialProxyUsername: String
    let initialProxyPassword: String
    let onSave: (FeedFormValues) -> Void

    init(
        modeTitle: String,
        saveButtonTitle: String,
        initialTitle: String,
        initialURLString: String,
        initialUseProxy: Bool,
        initialProxyType: FeedProxyType,
        initialProxyHost: String,
        initialProxyPort: Int?,
        initialProxyUsername: String,
        initialProxyPassword: String,
        onSave: @escaping (FeedFormValues) -> Void
    ) {
        self.modeTitle = modeTitle
        self.saveButtonTitle = saveButtonTitle
        self.initialTitle = initialTitle
        self.initialURLString = initialURLString
        self.initialUseProxy = initialUseProxy
        self.initialProxyType = initialProxyType
        self.initialProxyHost = initialProxyHost
        self.initialProxyPort = initialProxyPort
        self.initialProxyUsername = initialProxyUsername
        self.initialProxyPassword = initialProxyPassword
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _urlString = State(initialValue: initialURLString)
        _useProxy = State(initialValue: initialUseProxy)
        _proxyType = State(initialValue: initialProxyType)
        _proxyHost = State(initialValue: initialProxyHost)
        _proxyPortString = State(initialValue: initialProxyPort.map(String.init) ?? "")
        _proxyUsername = State(initialValue: initialProxyUsername)
        _proxyPassword = State(initialValue: initialProxyPassword)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Display Name (Optional)", text: $title)
                TextField("Feed URL", text: $urlString)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()

                Section("Network") {
                    Toggle("Use Proxy", isOn: $useProxy)

                    if useProxy {
                        Picker("Proxy Type", selection: $proxyType) {
                            ForEach(FeedProxyType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }

                        TextField("Proxy Host", text: $proxyHost)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                            .autocorrectionDisabled()

                        TextField("Proxy Port", text: $proxyPortString)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif

                        TextField("Proxy Username (Optional)", text: $proxyUsername)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                            .autocorrectionDisabled()

                        SecureField("Proxy Password (Optional)", text: $proxyPassword)
                    }
                }
            }
            .navigationTitle(modeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        onSave(
                            FeedFormValues(
                                title: title,
                                urlString: urlString,
                                useProxy: useProxy,
                                proxyType: proxyType,
                                proxyHost: proxyHost,
                                proxyPort: Int(proxyPortString),
                                proxyUsername: proxyUsername,
                                proxyPassword: proxyPassword
                            )
                        )
                        dismiss()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Feed.self, Article.self], inMemory: true)
}
