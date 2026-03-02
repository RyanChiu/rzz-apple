import SwiftUI
import SwiftData
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum ArticleFilter: String, CaseIterable, Identifiable {
    case all
    case starred

    var id: String { rawValue }
}

private struct FeedEditDraft: Identifiable {
    let id = UUID()
    let feedID: PersistentIdentifier
    let title: String
    let urlString: String
    let useProxy: Bool
    let useProxyForContent: Bool
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
    let useProxyForContent: Bool
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
    @Binding var isAppLocked: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Feed.createdAt, order: .reverse)]) private var feeds: [Feed]
    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse), SortDescriptor(\Article.createdAt, order: .reverse)]) private var articles: [Article]
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("app_lock_pin_hash") private var appLockPINHash = ""

    @State private var isAllFeedsSelected = true
    @State private var selectedFeedIDs: Set<PersistentIdentifier> = []
    @State private var isFeedsExpanded = true
    @State private var articleFilter: ArticleFilter = .all
    @State private var selectedArticleID: PersistentIdentifier?
    @State private var showAddFeed = false
    @State private var editDraft: FeedEditDraft?
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var pendingDeletionRequest: FeedDeletionRequest?
    @State private var showSecuritySettings = false

    private var displayedArticles: [Article] {
        var scoped = articles

        if let feedIDs = effectiveSelectedFeedIDs {
            scoped = scoped.filter { article in
                guard let feedID = article.feed?.persistentModelID else { return false }
                return feedIDs.contains(feedID)
            }
        }

        if articleFilter == .starred {
            scoped = scoped.filter(\.isStarred)
        }

        return scoped.sorted { lhs, rhs in
            (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
        }
    }

    private var effectiveSelectedFeedIDs: Set<PersistentIdentifier>? {
        guard !isAllFeedsSelected, !selectedFeedIDs.isEmpty else { return nil }
        return selectedFeedIDs
    }

    private var selectedFeeds: [Feed] {
        feeds.filter { selectedFeedIDs.contains($0.persistentModelID) }
    }

    private var hasCustomFeedSelection: Bool {
        !isAllFeedsSelected && !selectedFeedIDs.isEmpty
    }

    private var feedScopeSummary: String {
        if isAllFeedsSelected || selectedFeedIDs.isEmpty {
            return "All feeds selected"
        }

        if selectedFeeds.count == 1, let feed = selectedFeeds.first {
            return "Selected: \(feed.title)"
        }

        return "Selected: \(selectedFeeds.count) feeds"
    }

    private var selectedArticle: Article? {
        guard let selectedArticleID else { return nil }
        guard displayedArticles.contains(where: { $0.persistentModelID == selectedArticleID }) else { return nil }
        return articles.first(where: { $0.persistentModelID == selectedArticleID })
    }

    var body: some View {
        bodyWithLockLifecycle
    }

    private var baseLayout: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebarPane
            } content: {
                articleListPane
            } detail: {
                articleDetailPane
            }

            Divider()
            scopeStatusBar
        }
    }

    private var bodyWithToolbar: some View {
        baseLayout
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        guard !shouldShowLockScreen else { return }
                        showAddFeed = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                    .disabled(shouldShowLockScreen)

                    Button {
                        guard !shouldShowLockScreen else { return }
                        Task { await refreshCurrentSelection() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(shouldShowLockScreen || isRefreshing || feeds.isEmpty)

                    if let selectedFeedForEditing {
                        Button {
                            guard !shouldShowLockScreen else { return }
                            beginEdit(feed: selectedFeedForEditing)
                        } label: {
                            Label("Edit Feed", systemImage: "pencil")
                        }
                        .disabled(shouldShowLockScreen)
                    }

                    Button {
                        guard !shouldShowLockScreen else { return }
                        showSecuritySettings = true
                    } label: {
                        Label("Security", systemImage: "lock")
                    }
                    .disabled(shouldShowLockScreen)
                }
            }
    }

    private var bodyWithSelectionObservers: some View {
        bodyWithToolbar
            .onChange(of: articles.map(\.persistentModelID)) { _, newIDs in
                if let selectedArticleID, !newIDs.contains(selectedArticleID) {
                    self.selectedArticleID = nil
                }
            }
            .onChange(of: feeds.map(\.persistentModelID)) { _, newFeedIDs in
                selectedFeedIDs = selectedFeedIDs.intersection(Set(newFeedIDs))
                if selectedFeedIDs.isEmpty {
                    isAllFeedsSelected = true
                }
            }
            .onChange(of: displayedArticles.map(\.persistentModelID)) { _, visibleArticleIDs in
                if let selectedArticleID, !visibleArticleIDs.contains(selectedArticleID) {
                    self.selectedArticleID = nil
                }
            }
    }

    private var bodyWithSheets: some View {
        bodyWithSelectionObservers
            .sheet(isPresented: $showAddFeed) {
                FeedFormView(
                    modeTitle: "Add Feed",
                    saveButtonTitle: "Save",
                    initialTitle: "",
                    initialURLString: "",
                    initialUseProxy: false,
                    initialUseProxyForContent: false,
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
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
            .sheet(item: $editDraft) { draft in
                FeedFormView(
                    modeTitle: "Edit Feed",
                    saveButtonTitle: "Update",
                    initialTitle: draft.title,
                    initialURLString: draft.urlString,
                    initialUseProxy: draft.useProxy,
                    initialUseProxyForContent: draft.useProxyForContent,
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
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
            .sheet(isPresented: $showSecuritySettings) {
                AppLockSettingsView(
                    isEnabled: $appLockEnabled,
                    pinHash: $appLockPINHash
                )
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
    }

    private var bodyWithOverlays: some View {
        bodyWithSheets
            .overlay(alignment: .bottom) {
                if isRefreshing {
                    ProgressView("Refreshing feeds...")
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 12)
                }
            }
            .overlay {
                if shouldShowLockScreen {
                    AppLockScreenView { pin in
                        unlockIfValid(pin)
                    }
                }
            }
    }

    private var bodyWithAlerts: some View {
        bodyWithOverlays
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

    private var bodyWithLockLifecycle: some View {
        bodyWithAlerts
            .onChange(of: appLockEnabled) { _, newValue in
                if !newValue {
                    isAppLocked = false
                }
            }
            .onChange(of: appLockPINHash) { _, newValue in
                if newValue.isEmpty {
                    isAppLocked = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: appWillResignActiveNotification)) { _ in
                guard appLockEnabled, !appLockPINHash.isEmpty else { return }
                isAppLocked = true
            }
    }

    private var shouldShowLockScreen: Bool {
        appLockEnabled && !appLockPINHash.isEmpty && isAppLocked
    }

    private func unlockIfValid(_ pin: String) -> Bool {
        guard AppLockSecurity.verifyPIN(pin, storedHash: appLockPINHash) else { return false }
        isAppLocked = false
        return true
    }

    private var appWillResignActiveNotification: Notification.Name {
        #if os(macOS)
        NSApplication.willResignActiveNotification
        #else
        UIApplication.willResignActiveNotification
        #endif
    }

    private var sidebarPane: some View {
        VStack(spacing: 0) {
            List {
                Section("Feeds") {
                    DisclosureGroup(isExpanded: $isFeedsExpanded) {
                        ForEach(feeds) { feed in
                            FeedScopeRow(
                                title: feed.title.isEmpty ? feed.urlString : feed.title,
                                subtitle: feed.urlString,
                                isSelected: selectedFeedIDs.contains(feed.persistentModelID) && !isAllFeedsSelected,
                                systemImage: "dot.radiowaves.left.and.right",
                                sourceProxyEnabled: feed.useProxy,
                                contentProxyEnabled: feed.useProxyForContent,
                                onTap: { toggleFeedSelection(feed) }
                            )
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
                    } label: {
                        FeedScopeRow(
                            title: "All",
                            subtitle: "All feeds",
                            isSelected: isAllFeedsSelected || selectedFeedIDs.isEmpty,
                            systemImage: "tray.full",
                            sourceProxyEnabled: false,
                            contentProxyEnabled: false,
                            onTap: selectAllFeeds
                        )
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Picker("Article Filter", selection: $articleFilter) {
                    Image(systemName: "doc.text")
                        .tag(ArticleFilter.all)
                        .help("Show all articles in the selected feeds")
                    Image(systemName: "star.fill")
                        .tag(ArticleFilter.starred)
                        .help("Show only starred articles in the selected feeds")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 96)
                .accessibilityLabel("Article Filter")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .navigationTitle("RZZ")
    }

    private var articleListPane: some View {
        Group {
            if displayedArticles.isEmpty {
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "newspaper",
                    description: Text("Select All, one feed, or multiple feeds to view articles.")
                )
            } else {
                List(selection: $selectedArticleID) {
                    ForEach(displayedArticles) { article in
                        ArticleRow(
                            article: article,
                            isSelected: selectedArticleID == article.persistentModelID
                        )
                            .contentShape(Rectangle())
                            .tag(article.persistentModelID)
                            .contextMenu {
                                Button(article.isRead ? "Mark Unread" : "Mark Read") {
                                    article.isRead.toggle()
                                }
                                Button(article.isStarred ? "Unstar" : "Star") {
                                    article.isStarred.toggle()
                                }
                            }
                            .listRowBackground(
                                (selectedArticleID == article.persistentModelID)
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                            )
                    }
                }
                .navigationTitle(navigationTitle)
                .onChange(of: selectedArticleID) { _, newSelection in
                    guard let newSelection else { return }
                    guard let article = articles.first(where: { $0.persistentModelID == newSelection }) else { return }
                    if !article.isRead {
                        article.isRead = true
                    }
                }
            }
        }
    }

    private var activeFeedStats: (feedTitle: String, readCount: Int, unreadCount: Int, allCount: Int)? {
        guard let feed = selectedArticle?.feed else { return nil }
        let feedID = feed.persistentModelID
        let feedArticles = articles.filter { $0.feed?.persistentModelID == feedID }
        guard !feedArticles.isEmpty else { return nil }

        let readCount = feedArticles.filter(\.isRead).count
        let allCount = feedArticles.count
        let unreadCount = allCount - readCount
        let title = feed.title.isEmpty ? feed.urlString : feed.title

        return (title, readCount, unreadCount, allCount)
    }

    private var shouldShowFeedTitleInTitleStats: Bool {
        let activeFeedScopeCount: Int = {
            if isAllFeedsSelected || selectedFeedIDs.isEmpty {
                return feeds.count
            }
            return selectedFeeds.count
        }()
        return activeFeedScopeCount > 1
    }

    private var scopeStatusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: hasCustomFeedSelection ? "line.3.horizontal.decrease.circle.fill" : "tray.full.fill")
                .foregroundStyle(hasCustomFeedSelection ? Color.accentColor : .secondary)
            Text(feedScopeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if hasCustomFeedSelection {
                Button("Reset to All") {
                    selectAllFeeds()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let stats = activeFeedStats {
                Divider()
                    .frame(height: 14)
                Text("R \(stats.readCount) · U \(stats.unreadCount) · A \(stats.allCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var articleDetailPane: some View {
        Group {
            if let selectedArticle {
                ArticleDetailView(article: selectedArticle)
            } else {
                ContentUnavailableView(
                    "No Article Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose an article from the list to read.")
                )
            }
        }
    }

    private var navigationTitle: String {
        let filterTitle = articleFilter == .starred ? "Starred" : "Articles"

        if isAllFeedsSelected || selectedFeedIDs.isEmpty {
            return "All · \(filterTitle)"
        }

        if selectedFeeds.count == 1, let feed = selectedFeeds.first {
            return "\(feed.title) · \(filterTitle)"
        }

        return "\(selectedFeeds.count) Feeds · \(filterTitle)"
    }

    private var selectedFeedForEditing: Feed? {
        guard !isAllFeedsSelected, selectedFeeds.count == 1 else { return nil }
        return selectedFeeds.first
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
        selectedFeedIDs = [feed.persistentModelID]
        isAllFeedsSelected = false

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
        guard let feedIDs = effectiveSelectedFeedIDs else {
            await refreshAllFeeds()
            return
        }

        let selectedFeeds = feeds.filter { feedIDs.contains($0.persistentModelID) }
        guard !selectedFeeds.isEmpty else {
            await refreshAllFeeds()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        for feed in selectedFeeds {
            await refreshSingleFeed(feed, showGlobalSpinner: false)
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
        selectedFeedIDs.remove(feed.persistentModelID)
        if selectedFeedIDs.isEmpty {
            isAllFeedsSelected = true
        }
        if let selectedArticleID, feed.articles.contains(where: { $0.persistentModelID == selectedArticleID }) {
            self.selectedArticleID = nil
        }
        modelContext.delete(feed)
        try? modelContext.save()
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
            useProxyForContent: feed.useProxyForContent,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPassword
        )
    }

    private func applyProxyValues(_ values: FeedFormValues, to feed: Feed) {
        feed.useProxy = values.useProxy
        feed.useProxyForContent = values.useProxyForContent
        feed.proxyType = values.proxyType
        feed.proxyHost = values.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.proxyPort = values.proxyPort
        feed.proxyUsername = values.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.proxyPassword = values.proxyPassword
    }

    private func validateProxyValues(_ values: FeedFormValues) -> Bool {
        guard values.useProxy || values.useProxyForContent else { return true }

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

    private func toggleFeedSelection(_ feed: Feed) {
        if isAllFeedsSelected {
            isAllFeedsSelected = false
            selectedFeedIDs = [feed.persistentModelID]
            selectedArticleID = nil
            return
        }

        if selectedFeedIDs.contains(feed.persistentModelID) {
            selectedFeedIDs.remove(feed.persistentModelID)
        } else {
            selectedFeedIDs.insert(feed.persistentModelID)
        }

        if selectedFeedIDs.isEmpty {
            isAllFeedsSelected = true
        }
        selectedArticleID = nil
    }

    private func selectAllFeeds() {
        isAllFeedsSelected = true
        selectedFeedIDs.removeAll()
        selectedArticleID = nil
    }
}

private struct FeedScopeRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let systemImage: String
    let sourceProxyEnabled: Bool
    let contentProxyEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if sourceProxyEnabled {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Feed access uses proxy")
            }
            if contentProxyEnabled {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Content access uses proxy")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct ArticleRow: View {
    @Bindable var article: Article
    let isSelected: Bool

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
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
        }
    }
}

private struct ArticleDetailView: View {
    private enum ContentLoadState {
        case loading
        case loaded
        case fallbackSummary
    }

    @Bindable var article: Article
    @State private var isBodyLoading = false
    @State private var showSkeleton = true
    @State private var bodyHTML: String = ""
    @State private var bodyLoadTask: Task<Void, Never>?
    @State private var activeBodyLoadID = UUID()
    @State private var contentPathUsesProxy = false
    @State private var contentLoadState: ContentLoadState = .loading

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

            HStack(spacing: 8) {
                proxyStatusPill(
                    title: "Feed",
                    usesProxy: article.feed?.useProxy ?? false
                )
                proxyStatusPill(
                    title: "Content",
                    usesProxy: contentPathUsesProxy
                )
                if contentLoadState == .fallbackSummary {
                    statusPill(title: "Fallback", value: "Summary", icon: "arrow.uturn.backward.circle")
                }
            }

            Divider()

            if bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if isBodyLoading {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading content…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ArticleContentSkeleton()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("No content available.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if isBodyLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading content…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        ArticleHTMLView(htmlBody: bodyHTML)
                        .opacity(showSkeleton ? 0.06 : 1.0)
                        .animation(.easeInOut(duration: 0.18), value: showSkeleton)

                        if showSkeleton {
                            ArticleContentSkeleton()
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .navigationTitle("Article")
        .onAppear {
            reloadBodyHTML()
        }
        .onChange(of: article.persistentModelID) { _, _ in
            reloadBodyHTML()
        }
        .onDisappear {
            bodyLoadTask?.cancel()
        }
    }

    private func reloadBodyHTML() {
        bodyLoadTask?.cancel()
        let loadID = UUID()
        activeBodyLoadID = loadID

        let summary = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackHTML = summary.isEmpty ? "<p>No summary available.</p>" : article.summary
        let articleLink = article.link.trimmingCharacters(in: .whitespacesAndNewlines)
        let proxy = article.feed?.contentProxyConfiguration
        let shouldUseProxyForContent = article.feed?.useProxyForContent ?? false

        withAnimation(.easeInOut(duration: 0.12)) {
            contentPathUsesProxy = shouldUseProxyForContent
            contentLoadState = .loading
            bodyHTML = ""
            isBodyLoading = true
            showSkeleton = true
        }

        guard let url = URL(string: articleLink), url.scheme?.hasPrefix("http") == true else {
            withAnimation(.easeInOut(duration: 0.12)) {
                contentLoadState = .fallbackSummary
                bodyHTML = fallbackHTML
                isBodyLoading = false
                showSkeleton = false
            }
            return
        }

        bodyLoadTask = Task {
            let selectedProxy: FeedProxyConfiguration? = shouldUseProxyForContent ? proxy : nil
            let fetchedHTML = (try? await RSSService.fetchArticleHTML(from: url, proxy: selectedProxy))

            await MainActor.run {
                guard activeBodyLoadID == loadID else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    contentLoadState = fetchedHTML == nil ? .fallbackSummary : .loaded
                    bodyHTML = fetchedHTML ?? fallbackHTML
                    isBodyLoading = false
                    showSkeleton = false
                }
            }
        }
    }

    @ViewBuilder
    private func proxyStatusPill(title: String, usesProxy: Bool) -> some View {
        statusPill(
            title: title,
            value: usesProxy ? "Proxy" : "Direct",
            icon: usesProxy ? "network.badge.shield.half.filled" : "network"
        )
    }

    private func statusPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(title): \(value)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct ArticleContentSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.14))
                .frame(height: 16)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)
                .frame(maxWidth: 260, alignment: .leading)

            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 170)
                .padding(.top, 6)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 14)
                .frame(maxWidth: 220, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.trailing, 10)
    }
}

private struct ArticleHTMLView: View {
    let htmlBody: String
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    var body: some View {
        HTMLWebView(html: htmlDocument, onLoadingStateChange: onLoadingStateChange)
            .background(Color.clear)
    }

    private var htmlDocument: String {
        let lowercased = htmlBody.lowercased()
        if lowercased.contains("<html") || lowercased.contains("<!doctype html") {
            return htmlBody
        }

        return """
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
    var baseURL: URL? = nil
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadingStateChange: onLoadingStateChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            onLoadingStateChange(true)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        let onLoadingStateChange: (Bool) -> Void

        init(onLoadingStateChange: @escaping (Bool) -> Void) {
            self.onLoadingStateChange = onLoadingStateChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }
    }
}
#else
private struct HTMLWebView: UIViewRepresentable {
    let html: String
    var baseURL: URL? = nil
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadingStateChange: onLoadingStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            onLoadingStateChange(true)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
        let onLoadingStateChange: (Bool) -> Void

        init(onLoadingStateChange: @escaping (Bool) -> Void) {
            self.onLoadingStateChange = onLoadingStateChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }
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
    @State private var useProxyForContent: Bool
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
    let initialUseProxyForContent: Bool
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
        initialUseProxyForContent: Bool,
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
        self.initialUseProxyForContent = initialUseProxyForContent
        self.initialProxyType = initialProxyType
        self.initialProxyHost = initialProxyHost
        self.initialProxyPort = initialProxyPort
        self.initialProxyUsername = initialProxyUsername
        self.initialProxyPassword = initialProxyPassword
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _urlString = State(initialValue: initialURLString)
        _useProxy = State(initialValue: initialUseProxy)
        _useProxyForContent = State(initialValue: initialUseProxyForContent)
        _proxyType = State(initialValue: initialProxyType)
        _proxyHost = State(initialValue: initialProxyHost)
        _proxyPortString = State(initialValue: initialProxyPort.map(String.init) ?? "")
        _proxyUsername = State(initialValue: initialProxyUsername)
        _proxyPassword = State(initialValue: initialProxyPassword)
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text(modeTitle)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
            formContent
                .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(saveButtonTitle) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 620)
        #else
        NavigationStack {
            formContent
                .navigationTitle(modeTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveButtonTitle) {
                            saveAndDismiss()
                        }
                        .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        #endif
    }

    private var formContent: some View {
        Form {
            TextField("Display Name (Optional)", text: $title)
            TextField("Feed URL", text: $urlString)
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
                .autocorrectionDisabled()

            Section("Network") {
                Toggle("Use Proxy for Feed URL Access", isOn: $useProxy)
                Toggle("Use Proxy for Content Access", isOn: $useProxyForContent)

                if useProxy || useProxyForContent {
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
    }

    private func saveAndDismiss() {
        onSave(
            FeedFormValues(
                title: title,
                urlString: urlString,
                useProxy: useProxy,
                useProxyForContent: useProxyForContent,
                proxyType: proxyType,
                proxyHost: proxyHost,
                proxyPort: Int(proxyPortString),
                proxyUsername: proxyUsername,
                proxyPassword: proxyPassword
            )
        )
        dismiss()
    }
}

#Preview {
    ContentView(isAppLocked: .constant(false))
        .modelContainer(for: [Feed.self, Article.self], inMemory: true)
}
