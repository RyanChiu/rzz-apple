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
    let folderName: String
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
    let folderName: String
}

private struct FeedDeletionRequest: Identifiable {
    let id = UUID()
    let feedIDs: [PersistentIdentifier]
    let message: String
    let actionTitle: String
}

private struct FeedFolderGroup: Identifiable {
    let id: String
    let name: String
    let feeds: [Feed]
}

private struct FolderRenameDraft: Identifiable {
    let id = UUID()
    let originalName: String
    let currentName: String
}

struct ContentView: View {
    @Binding var isAppLocked: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Feed.createdAt, order: .reverse)]) private var feeds: [Feed]
    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse), SortDescriptor(\Article.createdAt, order: .reverse)]) private var articles: [Article]
    @Query(sort: [SortDescriptor(\Tag.name, order: .forward), SortDescriptor(\Tag.createdAt, order: .forward)]) private var tags: [Tag]
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("app_lock_pin_hash") private var appLockPINHash = ""
    @AppStorage("last_feed_scope_all") private var lastFeedScopeAll = true
    @AppStorage("last_selected_feed_uuids") private var lastSelectedFeedUUIDsCSV = ""
    @AppStorage("last_article_filter") private var lastArticleFilterRaw = ArticleFilter.all.rawValue
    @AppStorage("last_selected_article_uuid") private var lastSelectedArticleUUIDString = ""
    @AppStorage("last_selected_article_uuid_all") private var lastSelectedArticleUUIDAllString = ""
    @AppStorage("last_selected_article_uuid_starred") private var lastSelectedArticleUUIDStarredString = ""
    @AppStorage("last_selected_tag_uuid") private var lastSelectedTagUUIDString = ""
    @AppStorage("custom_feed_folder_names_json") private var customFeedFolderNamesJSON = "[]"

    @State private var isAllFeedsSelected = true
    @State private var selectedFeedIDs: Set<PersistentIdentifier> = []
    @State private var articleFilter: ArticleFilter = .all
    @State private var selectedTagFilterUUIDString = ""
    @State private var selectedArticleID: PersistentIdentifier?
    @State private var showAddFeed = false
    @State private var editDraft: FeedEditDraft?
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var pendingDeletionRequest: FeedDeletionRequest?
    @State private var showSecuritySettings = false
    @State private var showTagManager = false
    @State private var didRestorePersistedUIState = false
    @State private var showCreateFolderSheet = false
    @State private var folderRenameDraft: FolderRenameDraft?
    @State private var collapsedFolderNames: Set<String> = []

    private let defaultFeedFolderName = "New Added"
    private let maxTagCount = 5

    private var selectedTagFilter: Tag? {
        guard let uuid = UUID(uuidString: selectedTagFilterUUIDString) else { return nil }
        return tags.first(where: { $0.id == uuid })
    }

    private var displayedArticles: [Article] {
        groupedDisplayedArticles.flatMap(\.articles)
    }

    private var effectiveSelectedFeedIDs: Set<PersistentIdentifier>? {
        guard !isAllFeedsSelected, !selectedFeedIDs.isEmpty else { return nil }
        return selectedFeedIDs
    }

    private var selectedFeeds: [Feed] {
        feeds.filter { selectedFeedIDs.contains($0.persistentModelID) }
    }

    private var customFolderNames: [String] {
        guard let data = customFeedFolderNamesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var allFolderNames: [String] {
        let feedFolders = feeds.map { normalizedFolderName($0.folderName) }
        let customFolders = customFolderNames.map(normalizedFolderName(_:))
        let names = Set(feedFolders + customFolders + [defaultFeedFolderName])
        return names.sorted { lhs, rhs in
            if lhs == defaultFeedFolderName { return true }
            if rhs == defaultFeedFolderName { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var folderGroups: [FeedFolderGroup] {
        let allFeedsByFolder = Dictionary(grouping: feeds) { normalizedFolderName($0.folderName) }
        return allFolderNames.map { folderName in
            FeedFolderGroup(
                id: folderName,
                name: folderName,
                feeds: allFeedsByFolder[folderName] ?? []
            )
        }
    }

    private var orderedActiveFeeds: [Feed] {
        if isAllFeedsSelected || selectedFeedIDs.isEmpty {
            return feeds
        }
        return feeds.filter { selectedFeedIDs.contains($0.persistentModelID) }
    }

    private var groupedDisplayedArticles: [(feed: Feed, articles: [Article])] {
        orderedActiveFeeds.compactMap { feed in
            var items = feed.articles
            if articleFilter == .starred {
                items = items.filter(\.isStarred)
            }
            if let selectedTagFilter {
                let selectedTagID = selectedTagFilter.persistentModelID
                items = items.filter { article in
                    article.tags.contains(where: { $0.persistentModelID == selectedTagID })
                }
            }
            items.sort { lhs, rhs in
                (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
            }
            return items.isEmpty ? nil : (feed, items)
        }
    }

    private var shouldGroupArticleListByFeed: Bool {
        isAllFeedsSelected || selectedFeeds.count > 1
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
                restorePersistedUIStateIfNeeded()
            }
            .onChange(of: feeds.map(\.persistentModelID)) { _, newFeedIDs in
                selectedFeedIDs = selectedFeedIDs.intersection(Set(newFeedIDs))
                if selectedFeedIDs.isEmpty {
                    isAllFeedsSelected = true
                }
                restorePersistedUIStateIfNeeded()
            }
            .onChange(of: displayedArticles.map(\.persistentModelID)) { _, visibleArticleIDs in
                if let selectedArticleID, !visibleArticleIDs.contains(selectedArticleID) {
                    self.selectedArticleID = nil
                }
            }
            .onChange(of: tags.map(\.persistentModelID)) { _, newTagIDs in
                if let selectedTagFilter,
                   !newTagIDs.contains(selectedTagFilter.persistentModelID) {
                    selectedTagFilterUUIDString = ""
                }
            }
            .onChange(of: isAllFeedsSelected) { _, _ in
                persistFeedScopeSelection()
            }
            .onChange(of: selectedFeedIDs) { _, _ in
                persistFeedScopeSelection()
            }
            .onChange(of: selectedTagFilterUUIDString) { _, newValue in
                lastSelectedTagUUIDString = newValue
                handleArticleSelectionAfterFilterChange()
            }
            .onChange(of: articleFilter) { _, _ in
                persistArticleFilterSelection()
                handleArticleSelectionAfterFilterChange()
            }
            .onAppear {
                restorePersistedUIStateIfNeeded()
                selectedTagFilterUUIDString = lastSelectedTagUUIDString
            }
    }

    private var bodyWithSheets: some View {
        bodyWithSelectionObservers
            .sheet(isPresented: $showTagManager) {
                TagManagerView(
                    tags: tags,
                    maxTagCount: maxTagCount,
                    onCreate: createTag(named:),
                    onRename: renameTag(_:to:),
                    onDelete: deleteTag(_:)
                )
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
            .sheet(isPresented: $showCreateFolderSheet) {
                FolderFormView { folderName in
                    addCustomFolder(named: folderName)
                }
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
            .sheet(item: $folderRenameDraft) { draft in
                FolderFormView(
                    modeTitle: "Rename Folder",
                    saveButtonTitle: "Save",
                    initialFolderName: draft.currentName
                ) { newName in
                    renameFolder(from: draft.originalName, to: newName)
                }
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
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
                    initialProxyPassword: "",
                    initialFolderName: defaultFeedFolderName,
                    availableFolderNames: allFolderNames
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
                    initialProxyPassword: draft.proxyPassword,
                    initialFolderName: draft.folderName,
                    availableFolderNames: allFolderNames
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
                    Button {
                        showCreateFolderSheet = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }

                    FeedScopeRow(
                        title: "All",
                        subtitle: "All feeds",
                        isSelected: isAllFeedsSelected || selectedFeedIDs.isEmpty,
                        systemImage: "tray.full",
                        sourceProxyEnabled: false,
                        contentProxyEnabled: false,
                        onTap: selectAllFeeds
                    )

                    ForEach(folderGroups) { group in
                        DisclosureGroup(
                            isExpanded: bindingForFolderExpansion(named: group.name)
                        ) {
                            if group.feeds.isEmpty {
                                Text("No feeds")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(group.feeds) { feed in
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
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(group.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(group.feeds.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("New Folder") {
                                    showCreateFolderSheet = true
                                }

                                Button("Rename Folder") {
                                    folderRenameDraft = FolderRenameDraft(
                                        originalName: group.name,
                                        currentName: group.name
                                    )
                                }
                                .disabled(group.name == defaultFeedFolderName)

                                Button("Delete Folder", role: .destructive) {
                                    deleteFolder(named: group.name)
                                }
                                .disabled(group.name == defaultFeedFolderName)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
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
                    .frame(width: 96)
                    .accessibilityLabel("Article Filter")

                    Menu {
                        Button("Any Tag") {
                            selectedTagFilterUUIDString = ""
                        }
                        ForEach(tags) { tag in
                            Button {
                                selectedTagFilterUUIDString = tag.id.uuidString
                            } label: {
                                Label(
                                    tag.name,
                                    systemImage: selectedTagFilterUUIDString == tag.id.uuidString
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                            }
                        }
                        Divider()
                        Button("Manage Tags…") {
                            showTagManager = true
                        }
                    } label: {
                        Image(systemName: "tag")
                            .font(.body)
                            .foregroundStyle(selectedTagFilter == nil ? .secondary : Color.accentColor)
                            .frame(width: 34, height: 28)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .accessibilityLabel("Tag Filter")
                }
                .frame(maxWidth: .infinity, alignment: .center)
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
                ScrollViewReader { scrollProxy in
                    List(selection: $selectedArticleID) {
                        if shouldGroupArticleListByFeed {
                            let groups = groupedDisplayedArticles
                            ForEach(Array(groups.enumerated()), id: \.element.feed.persistentModelID) { index, group in
                                Section {
                                    ForEach(group.articles) { article in
                                        articleListRow(article)
                                    }
                                    if index < groups.count - 1 {
                                        Divider()
                                            .padding(.vertical, 6)
                                    }
                                } header: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(group.feed.title.isEmpty ? group.feed.urlString : group.feed.title)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("\(group.articles.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 4)
                                    .textCase(nil)
                                }
                            }
                        } else {
                            ForEach(displayedArticles) { article in
                                articleListRow(article)
                            }
                        }
                    }
                    .navigationTitle(navigationTitle)
                    .onAppear {
                        scrollSelectedArticleIntoView(using: scrollProxy)
                    }
                    .onChange(of: articleFilter) { _, _ in
                        scrollSelectedArticleIntoView(using: scrollProxy)
                    }
                    .onChange(of: displayedArticles.map(\.persistentModelID)) { _, _ in
                        scrollSelectedArticleIntoView(using: scrollProxy)
                    }
                    .onChange(of: selectedArticleID) { _, newSelection in
                    if let newSelection,
                       let article = articles.first(where: { $0.persistentModelID == newSelection }) {
                        lastSelectedArticleUUIDString = article.id.uuidString
                        persistArticleSelectionForCurrentFilter(articleID: article.id)
                    } else {
                        // Keep previous per-filter selection so switching filters can restore context.
                    }

                        guard let newSelection else { return }
                        guard let article = articles.first(where: { $0.persistentModelID == newSelection }) else { return }
                        if !article.isRead {
                            article.isRead = true
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func articleListRow(_ article: Article) -> some View {
        ArticleRow(
            article: article,
            isSelected: selectedArticleID == article.persistentModelID
        )
            .contentShape(Rectangle())
            .id(article.persistentModelID)
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
                ArticleDetailView(
                    article: selectedArticle,
                    tags: tags,
                    onToggleTag: toggleTag(_:for:),
                    onOpenTagManager: { showTagManager = true }
                )
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
        let tagTitle = selectedTagFilter.map { " #\($0.name)" } ?? ""

        if isAllFeedsSelected || selectedFeedIDs.isEmpty {
            return "All · \(filterTitle)\(tagTitle)"
        }

        if selectedFeeds.count == 1, let feed = selectedFeeds.first {
            return "\(feed.title) · \(filterTitle)\(tagTitle)"
        }

        return "\(selectedFeeds.count) Feeds · \(filterTitle)\(tagTitle)"
    }

    private var selectedFeedForEditing: Feed? {
        guard !isAllFeedsSelected, selectedFeeds.count == 1 else { return nil }
        return selectedFeeds.first
    }

    private func restoreLastSelectedArticleIfPossible() {
        guard selectedArticleID == nil else { return }
        let candidate = selectedArticleUUIDForCurrentFilter()
        guard let uuid = UUID(uuidString: candidate) else { return }
        guard let article = articles.first(where: { $0.id == uuid }) else { return }
        guard displayedArticles.contains(where: { $0.persistentModelID == article.persistentModelID }) else { return }
        selectedArticleID = article.persistentModelID
    }

    private func restorePersistedUIStateIfNeeded() {
        guard !didRestorePersistedUIState else { return }
        guard !feeds.isEmpty else { return }

        restoreArticleFilterSelectionIfPossible()
        restoreFeedScopeSelectionIfPossible()
        restoreLastSelectedArticleIfPossible()
        didRestorePersistedUIState = true
    }

    private func persistFeedScopeSelection() {
        lastFeedScopeAll = isAllFeedsSelected || selectedFeedIDs.isEmpty
        if lastFeedScopeAll {
            lastSelectedFeedUUIDsCSV = ""
            return
        }

        let selectedUUIDs = feeds
            .filter { selectedFeedIDs.contains($0.persistentModelID) }
            .map(\.id.uuidString)
        lastSelectedFeedUUIDsCSV = selectedUUIDs.joined(separator: ",")
    }

    private func restoreFeedScopeSelectionIfPossible() {
        guard !lastFeedScopeAll else {
            isAllFeedsSelected = true
            selectedFeedIDs.removeAll()
            return
        }

        let raw = lastSelectedFeedUUIDsCSV.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            isAllFeedsSelected = true
            selectedFeedIDs.removeAll()
            return
        }

        let targetUUIDs = Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        guard !targetUUIDs.isEmpty else {
            isAllFeedsSelected = true
            selectedFeedIDs.removeAll()
            return
        }

        let restoredIDs = Set(
            feeds
                .filter { targetUUIDs.contains($0.id) }
                .map(\.persistentModelID)
        )

        if restoredIDs.isEmpty {
            isAllFeedsSelected = true
            selectedFeedIDs.removeAll()
        } else {
            isAllFeedsSelected = false
            selectedFeedIDs = restoredIDs
        }
    }

    private func persistArticleFilterSelection() {
        lastArticleFilterRaw = articleFilter.rawValue
    }

    private func restoreArticleFilterSelectionIfPossible() {
        articleFilter = ArticleFilter(rawValue: lastArticleFilterRaw) ?? .all
    }

    private func persistArticleSelectionForCurrentFilter(articleID: UUID) {
        switch articleFilter {
        case .all:
            lastSelectedArticleUUIDAllString = articleID.uuidString
        case .starred:
            lastSelectedArticleUUIDStarredString = articleID.uuidString
        }
    }

    private func selectedArticleUUIDForCurrentFilter() -> String {
        switch articleFilter {
        case .all:
            return !lastSelectedArticleUUIDAllString.isEmpty ? lastSelectedArticleUUIDAllString : lastSelectedArticleUUIDString
        case .starred:
            return !lastSelectedArticleUUIDStarredString.isEmpty ? lastSelectedArticleUUIDStarredString : lastSelectedArticleUUIDString
        }
    }

    private func restoreArticleSelectionForCurrentFilterIfPossible() {
        if let currentID = selectedArticleID,
           displayedArticles.contains(where: { $0.persistentModelID == currentID }) {
            return
        }

        selectedArticleID = nil
        restoreLastSelectedArticleIfPossible()
    }

    private func handleArticleSelectionAfterFilterChange() {
        switch articleFilter {
        case .all:
            restoreArticleSelectionForCurrentFilterIfPossible()
        case .starred:
            // Do not auto-select when entering Starred.
            if let currentID = selectedArticleID,
               displayedArticles.contains(where: { $0.persistentModelID == currentID }) {
                return
            }
            selectedArticleID = nil
        }
    }

    private func scrollSelectedArticleIntoView(using proxy: ScrollViewProxy) {
        guard let selectedArticleID else { return }
        guard displayedArticles.contains(where: { $0.persistentModelID == selectedArticleID }) else { return }

        let targetID = selectedArticleID
        let delays: [Double] = [0, 0.05, 0.12, 0.24]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.selectedArticleID == targetID else { return }
                guard self.displayedArticles.contains(where: { $0.persistentModelID == targetID }) else { return }
                proxy.scrollTo(targetID, anchor: .center)
            }
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

        let feed = Feed(
            title: displayTitle,
            urlString: trimmedURL,
            folderName: normalizedFolderName(values.folderName)
        )
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

        let previousFetchSignature = FeedFetchSignature(
            urlString: feed.urlString,
            useProxy: feed.useProxy,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPassword
        )

        let trimmedTitle = values.title.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.title = trimmedTitle.isEmpty ? (url.host ?? trimmedURL) : trimmedTitle
        feed.urlString = trimmedURL
        feed.folderName = normalizedFolderName(values.folderName)
        applyProxyValues(values, to: feed)

        let updatedFetchSignature = FeedFetchSignature(
            urlString: feed.urlString,
            useProxy: feed.useProxy,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPassword
        )

        try? modelContext.save()
        if previousFetchSignature != updatedFetchSignature {
            await refreshSingleFeed(feed)
        }
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
            proxyPassword: feed.proxyPassword,
            folderName: normalizedFolderName(feed.folderName)
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

    private func normalizedFolderName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultFeedFolderName : trimmed
    }

    private func addCustomFolder(named rawName: String) {
        let normalized = normalizedFolderName(rawName)
        saveCustomFolderNames(Set(customFolderNames + [normalized]))
    }

    private func saveCustomFolderNames(_ names: Set<String>) {
        let normalizedSet = Set(names.map(normalizedFolderName(_:)))
        let sorted = normalizedSet.sorted { lhs, rhs in
            if lhs == defaultFeedFolderName { return true }
            if rhs == defaultFeedFolderName { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        guard let data = try? JSONEncoder().encode(sorted),
              let json = String(data: data, encoding: .utf8) else { return }

        customFeedFolderNamesJSON = json
    }

    private func renameFolder(from oldRawName: String, to newRawName: String) {
        let oldName = normalizedFolderName(oldRawName)
        let newName = normalizedFolderName(newRawName)
        guard oldName != defaultFeedFolderName else { return }
        guard oldName != newName else { return }

        for feed in feeds where normalizedFolderName(feed.folderName) == oldName {
            feed.folderName = newName
        }
        try? modelContext.save()

        var names = Set(customFolderNames.map(normalizedFolderName(_:)))
        names.remove(oldName)
        names.insert(newName)
        saveCustomFolderNames(names)
    }

    private func deleteFolder(named rawName: String) {
        let name = normalizedFolderName(rawName)
        guard name != defaultFeedFolderName else { return }

        for feed in feeds where normalizedFolderName(feed.folderName) == name {
            feed.folderName = defaultFeedFolderName
        }
        try? modelContext.save()

        var names = Set(customFolderNames.map(normalizedFolderName(_:)))
        names.remove(name)
        saveCustomFolderNames(names)
        collapsedFolderNames.remove(name)
    }

    private func normalizedTagName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTag(named rawName: String) {
        let normalized = normalizedTagName(rawName)
        guard !normalized.isEmpty else { return }
        guard tags.count < maxTagCount else { return }
        guard !tags.contains(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) else { return }

        let tag = Tag(name: normalized)
        modelContext.insert(tag)
        try? modelContext.save()
    }

    private func renameTag(_ tag: Tag, to rawName: String) {
        let normalized = normalizedTagName(rawName)
        guard !normalized.isEmpty else { return }

        if tags.contains(where: {
            $0.persistentModelID != tag.persistentModelID &&
            $0.name.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return
        }

        tag.name = normalized
        try? modelContext.save()
    }

    private func deleteTag(_ tag: Tag) {
        if selectedTagFilterUUIDString == tag.id.uuidString {
            selectedTagFilterUUIDString = ""
        }
        modelContext.delete(tag)
        try? modelContext.save()
    }

    private func toggleTag(_ tag: Tag, for article: Article) {
        if let index = article.tags.firstIndex(where: { $0.persistentModelID == tag.persistentModelID }) {
            article.tags.remove(at: index)
        } else {
            article.tags.append(tag)
        }
        try? modelContext.save()
    }

    private func bindingForFolderExpansion(named name: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolderNames.contains(name) },
            set: { isExpanded in
                if isExpanded {
                    collapsedFolderNames.remove(name)
                } else {
                    collapsedFolderNames.insert(name)
                }
            }
        )
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

private struct FeedFetchSignature: Equatable {
    let urlString: String
    let useProxy: Bool
    let proxyType: FeedProxyType
    let proxyHost: String
    let proxyPort: Int?
    let proxyUsername: String
    let proxyPassword: String

    init(
        urlString: String,
        useProxy: Bool,
        proxyType: FeedProxyType,
        proxyHost: String,
        proxyPort: Int?,
        proxyUsername: String,
        proxyPassword: String
    ) {
        self.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.useProxy = useProxy
        self.proxyType = proxyType
        self.proxyHost = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.proxyPort = proxyPort
        self.proxyUsername = proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        self.proxyPassword = proxyPassword
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
    let tags: [Tag]
    let onToggleTag: (Tag, Article) -> Void
    let onOpenTagManager: () -> Void
    @State private var isBodyLoading = false
    @State private var showSkeleton = true
    @State private var bodyHTML: String = ""
    @State private var bodyLoadTask: Task<Void, Never>?
    @State private var activeBodyLoadID = UUID()
    @State private var contentPathUsesProxy = false
    @State private var contentLoadState: ContentLoadState = .loading
    @State private var lastSavedScrollProgress: Double = -1

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

                Menu {
                    if tags.isEmpty {
                        Text("No tags yet")
                    } else {
                        ForEach(tags) { tag in
                            Button {
                                onToggleTag(tag, article)
                            } label: {
                                Label(
                                    tag.name,
                                    systemImage: article.tags.contains(where: { $0.persistentModelID == tag.persistentModelID })
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                            }
                        }
                    }
                    Divider()
                    Button("Manage Tags…") {
                        onOpenTagManager()
                    }
                } label: {
                    Label("Tags", systemImage: "tag")
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

            if !article.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(article.tags.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })) { tag in
                            Text("#\(tag.name)")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
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
                        ArticleHTMLView(
                            htmlBody: bodyHTML,
                            initialScrollProgress: article.readingScrollProgress,
                            onScrollProgressChange: persistReadingProgress
                        )
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
        lastSavedScrollProgress = article.readingScrollProgress

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

    private func persistReadingProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        guard abs(clamped - lastSavedScrollProgress) >= 0.01 else { return }
        lastSavedScrollProgress = clamped
        article.readingScrollProgress = clamped
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
    var initialScrollProgress: Double = 0
    var onScrollProgressChange: (Double) -> Void = { _ in }
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    var body: some View {
        HTMLWebView(
            html: htmlDocument,
            initialScrollProgress: initialScrollProgress,
            onScrollProgressChange: onScrollProgressChange,
            onLoadingStateChange: onLoadingStateChange
        )
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
    var initialScrollProgress: Double = 0
    var onScrollProgressChange: (Double) -> Void = { _ in }
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialScrollProgress: initialScrollProgress,
            onScrollProgressChange: onScrollProgressChange,
            onLoadingStateChange: onLoadingStateChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = context.coordinator.makeUserContentController()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.initialScrollProgress = initialScrollProgress
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.shouldRestoreOnNextFinish = true
            onLoadingStateChange(true)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.scrollMessageHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let scrollMessageHandlerName = "rzzScrollProgress"
        var lastHTML: String = ""
        var shouldRestoreOnNextFinish = false
        var initialScrollProgress: Double
        let onScrollProgressChange: (Double) -> Void
        let onLoadingStateChange: (Bool) -> Void

        init(
            initialScrollProgress: Double,
            onScrollProgressChange: @escaping (Double) -> Void,
            onLoadingStateChange: @escaping (Bool) -> Void
        ) {
            self.initialScrollProgress = initialScrollProgress
            self.onScrollProgressChange = onScrollProgressChange
            self.onLoadingStateChange = onLoadingStateChange
        }

        func makeUserContentController() -> WKUserContentController {
            let controller = WKUserContentController()
            controller.add(self, name: Self.scrollMessageHandlerName)

            let source = """
            (function() {
              function computeProgress() {
                var doc = document.documentElement;
                var body = document.body;
                var fullHeight = Math.max(doc.scrollHeight, body ? body.scrollHeight : 0);
                var viewport = window.innerHeight || doc.clientHeight || 0;
                var maxScroll = Math.max(fullHeight - viewport, 0);
                var y = window.scrollY || doc.scrollTop || 0;
                var progress = maxScroll > 0 ? (y / maxScroll) : 0;
                return Math.max(0, Math.min(1, progress));
              }
              function publish() {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(Self.scrollMessageHandlerName)) {
                  window.webkit.messageHandlers.\(Self.scrollMessageHandlerName).postMessage(computeProgress());
                }
              }
              window.addEventListener('scroll', publish, { passive: true });
              window.addEventListener('resize', publish);
              document.addEventListener('readystatechange', publish);
              setTimeout(publish, 0);
            })();
            """
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            controller.addUserScript(script)
            return controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if shouldRestoreOnNextFinish {
                shouldRestoreOnNextFinish = false
                let clamped = min(max(initialScrollProgress, 0), 1)
                let js = "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(clamped));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.scrollMessageHandlerName else { return }
            guard let value = message.body as? Double else { return }
            onScrollProgressChange(value)
        }
    }
}
#else
private struct HTMLWebView: UIViewRepresentable {
    let html: String
    var baseURL: URL? = nil
    var initialScrollProgress: Double = 0
    var onScrollProgressChange: (Double) -> Void = { _ in }
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialScrollProgress: initialScrollProgress,
            onScrollProgressChange: onScrollProgressChange,
            onLoadingStateChange: onLoadingStateChange
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = context.coordinator.makeUserContentController()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.initialScrollProgress = initialScrollProgress
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.shouldRestoreOnNextFinish = true
            onLoadingStateChange(true)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.scrollMessageHandlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let scrollMessageHandlerName = "rzzScrollProgress"
        var lastHTML: String = ""
        var shouldRestoreOnNextFinish = false
        var initialScrollProgress: Double
        let onScrollProgressChange: (Double) -> Void
        let onLoadingStateChange: (Bool) -> Void

        init(
            initialScrollProgress: Double,
            onScrollProgressChange: @escaping (Double) -> Void,
            onLoadingStateChange: @escaping (Bool) -> Void
        ) {
            self.initialScrollProgress = initialScrollProgress
            self.onScrollProgressChange = onScrollProgressChange
            self.onLoadingStateChange = onLoadingStateChange
        }

        func makeUserContentController() -> WKUserContentController {
            let controller = WKUserContentController()
            controller.add(self, name: Self.scrollMessageHandlerName)

            let source = """
            (function() {
              function computeProgress() {
                var doc = document.documentElement;
                var body = document.body;
                var fullHeight = Math.max(doc.scrollHeight, body ? body.scrollHeight : 0);
                var viewport = window.innerHeight || doc.clientHeight || 0;
                var maxScroll = Math.max(fullHeight - viewport, 0);
                var y = window.scrollY || doc.scrollTop || 0;
                var progress = maxScroll > 0 ? (y / maxScroll) : 0;
                return Math.max(0, Math.min(1, progress));
              }
              function publish() {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(Self.scrollMessageHandlerName)) {
                  window.webkit.messageHandlers.\(Self.scrollMessageHandlerName).postMessage(computeProgress());
                }
              }
              window.addEventListener('scroll', publish, { passive: true });
              window.addEventListener('resize', publish);
              document.addEventListener('readystatechange', publish);
              setTimeout(publish, 0);
            })();
            """
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            controller.addUserScript(script)
            return controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if shouldRestoreOnNextFinish {
                shouldRestoreOnNextFinish = false
                let clamped = min(max(initialScrollProgress, 0), 1)
                let js = "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(clamped));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingStateChange(false)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.scrollMessageHandlerName else { return }
            guard let value = message.body as? Double else { return }
            onScrollProgressChange(value)
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
    @State private var selectedFolderName: String

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
    let initialFolderName: String
    let availableFolderNames: [String]
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
        initialFolderName: String,
        availableFolderNames: [String],
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
        self.initialFolderName = initialFolderName
        self.availableFolderNames = availableFolderNames
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
        _selectedFolderName = State(initialValue: initialFolderName)
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

            Section("Folder") {
                Picker("Folder", selection: $selectedFolderName) {
                    ForEach(availableFolderNames, id: \.self) { folderName in
                        Text(folderName).tag(folderName)
                    }
                }
            }

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
                proxyPassword: proxyPassword,
                folderName: selectedFolderName
            )
        )
        dismiss()
    }
}

private struct TagRenameDraft: Identifiable {
    let id = UUID()
    let tagID: PersistentIdentifier
    let currentName: String
}

private struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    let tags: [Tag]
    let maxTagCount: Int
    let onCreate: (String) -> Void
    let onRename: (Tag, String) -> Void
    let onDelete: (Tag) -> Void

    @State private var newTagName = ""
    @State private var renameDraft: TagRenameDraft?

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Tags")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 10) {
                Text("Up to \(maxTagCount) tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    TextField("New tag name", text: $newTagName)
                    Button("Add") {
                        onCreate(newTagName)
                        newTagName = ""
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tags.count >= maxTagCount)
                }

                List {
                    ForEach(tags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer(minLength: 8)
                            Button("Rename") {
                                renameDraft = TagRenameDraft(tagID: tag.persistentModelID, currentName: tag.name)
                            }
                            .buttonStyle(.borderless)
                            Button("Delete", role: .destructive) {
                                onDelete(tag)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 220)
            }
            .padding(12)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 380)
        .sheet(item: $renameDraft) { draft in
            FolderFormView(
                modeTitle: "Rename Tag",
                saveButtonTitle: "Save",
                nameFieldTitle: "Tag Name",
                initialFolderName: draft.currentName
            ) { newName in
                guard let tag = tags.first(where: { $0.persistentModelID == draft.tagID }) else { return }
                onRename(tag, newName)
            }
            #if os(macOS)
            .presentationSizing(.fitted)
            #endif
        }
        #else
        NavigationStack {
            List {
                Section("Create") {
                    Text("Up to \(maxTagCount) tags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("New tag name", text: $newTagName)
                        Button("Add") {
                            onCreate(newTagName)
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tags.count >= maxTagCount)
                    }
                }

                Section("All Tags") {
                    ForEach(tags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer(minLength: 8)
                            Button("Rename") {
                                renameDraft = TagRenameDraft(tagID: tag.persistentModelID, currentName: tag.name)
                            }
                            Button("Delete", role: .destructive) {
                                onDelete(tag)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $renameDraft) { draft in
                FolderFormView(
                    modeTitle: "Rename Tag",
                    saveButtonTitle: "Save",
                    nameFieldTitle: "Tag Name",
                    initialFolderName: draft.currentName
                ) { newName in
                    guard let tag = tags.first(where: { $0.persistentModelID == draft.tagID }) else { return }
                    onRename(tag, newName)
                }
            }
        }
        #endif
    }
}

private struct FolderFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var folderName: String
    let modeTitle: String
    let saveButtonTitle: String
    let nameFieldTitle: String
    let onSave: (String) -> Void

    init(
        modeTitle: String = "New Folder",
        saveButtonTitle: String = "Create",
        nameFieldTitle: String = "Folder Name",
        initialFolderName: String = "",
        onSave: @escaping (String) -> Void
    ) {
        self.modeTitle = modeTitle
        self.saveButtonTitle = saveButtonTitle
        self.nameFieldTitle = nameFieldTitle
        self.onSave = onSave
        _folderName = State(initialValue: initialFolderName)
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

            Form {
                TextField(nameFieldTitle, text: $folderName)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(saveButtonTitle) {
                    onSave(folderName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 420)
        #else
        NavigationStack {
            Form {
                TextField(nameFieldTitle, text: $folderName)
            }
            .navigationTitle(modeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        onSave(folderName)
                        dismiss()
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #endif
    }
}

#Preview {
    ContentView(isAppLocked: .constant(false))
        .modelContainer(for: [Feed.self, Article.self, Tag.self], inMemory: true)
}
