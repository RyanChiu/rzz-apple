import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers
import UserNotifications
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

private enum BackupExportMode: String, CaseIterable, Identifiable {
    case lite
    case text
    case full

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .lite:
            return "Export Lite (Default)"
        case .text:
            return "Export Text"
        case .full:
            return "Export Full"
        }
    }

    var displayName: String {
        switch self {
        case .lite:
            return "Lite"
        case .text:
            return "Text"
        case .full:
            return "Full"
        }
    }
}

private enum BackupExportStatusStyle {
    case info
    case success
    case failure
}

private enum LaunchRefreshStatusStyle {
    case info
    case success
    case failure
}

private enum FeedRefreshOutcome {
    case success(newArticleCount: Int)
    case failure(message: String)
}

private struct FeedEditDraft: Identifiable {
    let id = UUID()
    let feedID: PersistentIdentifier
    let title: String
    let urlString: String
    let useProxy: Bool
    let useProxyForContent: Bool
    let allowInsecureHTTPForContent: Bool
    let proxyType: FeedProxyType
    let proxyHost: String
    let proxyPort: Int?
    let proxyUsername: String
    let proxyPassword: String
    let offlinePolicy: FeedOfflinePolicy
    let folderName: String
    let isTitleManuallySet: Bool
}

private struct FeedFormValues {
    let title: String
    let urlString: String
    let useProxy: Bool
    let useProxyForContent: Bool
    let allowInsecureHTTPForContent: Bool
    let proxyType: FeedProxyType
    let proxyHost: String
    let proxyPort: Int?
    let proxyUsername: String
    let proxyPassword: String
    let offlinePolicy: FeedOfflinePolicy
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

private struct ArticleListFocusRequest: Equatable {
    let token: UUID = UUID()
    let articleID: PersistentIdentifier
}

private struct FolderRenameDraft: Identifiable {
    let id = UUID()
    let originalName: String
    let currentName: String
}

private struct OfflineCacheFeedUsage: Identifiable {
    let id: PersistentIdentifier
    let feedTitle: String
    let cachedCount: Int
    let cachedBytes: Int
}

private struct OfflineCacheSummary {
    let totalCachedCount: Int
    let totalCachedBytes: Int
    let feedUsages: [OfflineCacheFeedUsage]
}

struct ContentView: View {
    @Binding var isAppLocked: Bool
    @Binding var appLockPINHash: String
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Feed.createdAt, order: .reverse)]) private var feeds: [Feed]
    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse), SortDescriptor(\Article.createdAt, order: .reverse)]) private var articles: [Article]
    @Query(sort: [SortDescriptor(\Tag.name, order: .forward), SortDescriptor(\Tag.createdAt, order: .forward)]) private var tags: [Tag]
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("last_feed_scope_all") private var lastFeedScopeAll = true
    @AppStorage("last_selected_feed_uuids") private var lastSelectedFeedUUIDsCSV = ""
    @AppStorage("last_article_filter") private var lastArticleFilterRaw = ArticleFilter.all.rawValue
    @AppStorage("last_selected_article_uuid") private var lastSelectedArticleUUIDString = ""
    @AppStorage("last_selected_article_uuid_all") private var lastSelectedArticleUUIDAllString = ""
    @AppStorage("last_selected_article_uuid_starred") private var lastSelectedArticleUUIDStarredString = ""
    @AppStorage("last_selected_tag_uuid") private var lastSelectedTagUUIDString = ""
    @AppStorage("custom_feed_folder_names_json") private var customFeedFolderNamesJSON = "[]"
    @AppStorage("auto_refresh_on_launch") private var autoRefreshOnLaunch = true
    @AppStorage("last_refresh_status_summary") private var lastRefreshStatusSummary = "Never refreshed"
    @AppStorage("last_refresh_status_at") private var lastRefreshStatusAt = 0.0

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
    @State private var showOfflineStorage = false
    @State private var showExportBackup = false
    @State private var showImportBackup = false
    @State private var showImportBackupConfirmation = false
    @State private var showTagManager = false
    @State private var didRestorePersistedUIState = false
    @State private var transferMessage: String?
    @State private var exportBackupDocument = RZZBackupDocument()
    @State private var pendingBackupExportMode: BackupExportMode = .lite
    @State private var backupExportStatusMessage: String?
    @State private var backupExportStatusProgress: Double = 0
    @State private var backupExportIsRunning = false
    @State private var backupExportStatusStyle: BackupExportStatusStyle = .info
    @State private var backupExportStatusToken = UUID()
    @State private var launchRefreshStatusMessage: String?
    @State private var launchRefreshProgress: Double = 0
    @State private var launchRefreshIsRunning = false
    @State private var launchRefreshStatusStyle: LaunchRefreshStatusStyle = .info
    @State private var launchRefreshStatusToken = UUID()
    @State private var didScheduleLaunchAutoRefresh = false
    @State private var showCreateFolderSheet = false
    @State private var folderRenameDraft: FolderRenameDraft?
    @State private var collapsedFolderNames: Set<String> = []
    @State private var articleListFocusRequest: ArticleListFocusRequest?
    @State private var offlineCachingArticleIDs: Set<PersistentIdentifier> = []
    @State private var offlineCacheGeneration: Int = 0
    @State private var didMigrateLegacyProxySecrets = false
    @State private var exportBackupFilename = ""

    private let defaultFeedFolderName = "New Added"
    private let maxTagCount = 5
    private let backupTextSummaryCharacterLimit = 20_000
    private let launchAutoRefreshDelayNanoseconds: UInt64 = 1_200_000_000
    private let launchAutoRefreshMinimumInterval: TimeInterval = 15 * 60

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

    private var offlineCacheSummary: OfflineCacheSummary {
        var totalCount = 0
        var totalBytes = 0
        var usages: [OfflineCacheFeedUsage] = []

        for feed in feeds {
            let cachedArticles = feed.articles.filter(\.hasOfflineContent)
            guard !cachedArticles.isEmpty else { continue }

            let bytes = cachedArticles.reduce(0) { partialResult, article in
                partialResult + max(article.offlineCachedBytes, article.offlineCachedHTML.lengthOfBytes(using: .utf8))
            }
            let feedTitle = feed.title.isEmpty ? feed.urlString : feed.title
            usages.append(
                OfflineCacheFeedUsage(
                    id: feed.persistentModelID,
                    feedTitle: feedTitle,
                    cachedCount: cachedArticles.count,
                    cachedBytes: bytes
                )
            )
            totalCount += cachedArticles.count
            totalBytes += bytes
        }

        usages.sort { lhs, rhs in
            if lhs.cachedBytes == rhs.cachedBytes {
                return lhs.feedTitle.localizedCaseInsensitiveCompare(rhs.feedTitle) == .orderedAscending
            }
            return lhs.cachedBytes > rhs.cachedBytes
        }

        return OfflineCacheSummary(
            totalCachedCount: totalCount,
            totalCachedBytes: totalBytes,
            feedUsages: usages
        )
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
                        showOfflineStorage = true
                    } label: {
                        Label("Offline Storage", systemImage: "internaldrive")
                    }
                    .disabled(shouldShowLockScreen)

                    Button {
                        guard !shouldShowLockScreen else { return }
                        showSecuritySettings = true
                    } label: {
                        Label("Security", systemImage: "lock")
                    }
                    .disabled(shouldShowLockScreen)

                    Menu {
                        Button {
                            guard !shouldShowLockScreen else { return }
                            triggerBackupExport(.lite)
                        } label: {
                            Label(BackupExportMode.lite.menuTitle, systemImage: "square.and.arrow.up")
                        }

                        Button {
                            guard !shouldShowLockScreen else { return }
                            triggerBackupExport(.text)
                        } label: {
                            Label(BackupExportMode.text.menuTitle, systemImage: "textformat")
                        }

                        Button {
                            guard !shouldShowLockScreen else { return }
                            triggerBackupExport(.full)
                        } label: {
                            Label(BackupExportMode.full.menuTitle, systemImage: "doc.richtext")
                        }

                        Divider()
                        Button(role: .destructive) {
                            guard !shouldShowLockScreen else { return }
                            showImportBackupConfirmation = true
                        } label: {
                            #if os(macOS)
                            Label("Import Latest Backup", systemImage: "square.and.arrow.down")
                            #else
                            Label("Import Data…", systemImage: "square.and.arrow.down")
                            #endif
                        }

                        #if os(macOS)
                        Divider()
                        Button {
                            guard !shouldShowLockScreen else { return }
                            copyBackupFolderPathOnMac()
                        } label: {
                            Label("Copy Backup Folder Path", systemImage: "doc.on.doc")
                        }

                        Button {
                            guard !shouldShowLockScreen else { return }
                            revealBackupFolderOnMac()
                        } label: {
                            Label("Reveal Backups in Finder", systemImage: "folder")
                        }
                        #endif
                    } label: {
                        Label("Backup", systemImage: "archivebox")
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
                migrateLegacyProxySecretsIfNeeded()
                restorePersistedUIStateIfNeeded()
                scheduleLaunchAutoRefreshIfNeeded()
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
                migrateLegacyProxySecretsIfNeeded()
                restorePersistedUIStateIfNeeded()
                selectedTagFilterUUIDString = lastSelectedTagUUIDString
                scheduleLaunchAutoRefreshIfNeeded()
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
                    initialAllowInsecureHTTPForContent: false,
                    initialProxyType: .http,
                    initialProxyHost: "",
                    initialProxyPort: nil,
                    initialProxyUsername: "",
                    initialProxyPassword: "",
                    initialOfflinePolicy: .off,
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
                    initialTitle: draft.isTitleManuallySet ? draft.title : "",
                    initialURLString: draft.urlString,
                    initialUseProxy: draft.useProxy,
                    initialUseProxyForContent: draft.useProxyForContent,
                    initialAllowInsecureHTTPForContent: draft.allowInsecureHTTPForContent,
                    initialProxyType: draft.proxyType,
                    initialProxyHost: draft.proxyHost,
                    initialProxyPort: draft.proxyPort,
                    initialProxyUsername: draft.proxyUsername,
                    initialProxyPassword: draft.proxyPassword,
                    initialOfflinePolicy: draft.offlinePolicy,
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
            .sheet(isPresented: $showOfflineStorage) {
                OfflineStorageView(
                    totalCachedCount: offlineCacheSummary.totalCachedCount,
                    totalCachedBytes: offlineCacheSummary.totalCachedBytes,
                    feedUsages: offlineCacheSummary.feedUsages,
                    onClearAll: clearAllOfflineCache,
                    onClearFeed: clearOfflineCache(forUsage:)
                )
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
            .confirmationDialog(
                "Import Backup and Replace Current Data?",
                isPresented: $showImportBackupConfirmation,
                titleVisibility: .visible
            ) {
                Button("Import and Replace", role: .destructive) {
                    #if os(macOS)
                    importBackupOnMac()
                    #else
                    showImportBackup = true
                    #endif
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace current feeds, articles, tags, and offline cache. Proxy passwords and app lock PIN are not imported.")
            }
            #if !os(macOS)
            .fileExporter(
                isPresented: $showExportBackup,
                document: exportBackupDocument,
                contentType: .json,
                defaultFilename: exportBackupFilename
            ) { result in
                handleBackupExportResult(result)
            }
            .fileImporter(
                isPresented: $showImportBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImportResult(result)
            }
            #endif
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
            .alert("Data Transfer", isPresented: Binding(get: {
                transferMessage != nil
            }, set: { newValue in
                if !newValue { transferMessage = nil }
            })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(transferMessage ?? "")
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
                        offlinePolicy: .off,
                        allowsInsecureHTTPContent: false,
                        onSelectionTap: selectAllFeeds,
                        onTitleTap: focusFirstVisibleArticle
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
                                        offlinePolicy: feed.offlinePolicy,
                                        allowsInsecureHTTPContent: feed.allowInsecureHTTPForContent,
                                        onSelectionTap: { toggleFeedSelection(feed) },
                                        onTitleTap: { requestFocusForSelectedFeed(feed) }
                                    )
                                    .contextMenu {
                                        Button("Edit") {
                                            beginEdit(feed: feed)
                                        }
                                        Button("Refresh") {
                                            Task { _ = await refreshSingleFeed(feed) }
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
                            ForEach(groups, id: \.feed.persistentModelID) { group in
                                Section {
                                    ForEach(group.articles) { article in
                                        articleListRow(article)
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
                    .onChange(of: articleListFocusRequest?.token) { _, _ in
                        guard let request = articleListFocusRequest else { return }
                        scrollArticleIntoTop(using: scrollProxy, articleID: request.articleID)
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
                if article.feed?.offlinePolicy == .fullContent {
                    Divider()
                    Button("Retry Offline Cache") {
                        retryOfflineCaching(for: article)
                    }
                    .disabled(
                        article.offlineStatus == .caching ||
                        offlineCachingArticleIDs.contains(article.persistentModelID)
                    )
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

    private var persistentRefreshStatusText: String {
        guard lastRefreshStatusAt > 0 else {
            return lastRefreshStatusSummary
        }
        let date = Date(timeIntervalSince1970: lastRefreshStatusAt)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "\(lastRefreshStatusSummary) · \(formatter.string(from: date))"
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

            Divider()
                .frame(height: 14)
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(persistentRefreshStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

            if let backupExportStatusMessage {
                Divider()
                    .frame(height: 14)
                HStack(spacing: 6) {
                    if backupExportIsRunning {
                        ProgressView(value: backupExportStatusProgress)
                            .frame(width: 72)
                            .controlSize(.small)
                    } else {
                        Image(systemName: backupExportStatusIconName)
                            .font(.caption2)
                    }

                    Text(backupExportStatusMessage)
                        .font(.caption2)
                        .foregroundStyle(backupExportStatusColor)
                        .lineLimit(1)
                }
            }

            if let launchRefreshStatusMessage {
                Divider()
                    .frame(height: 14)
                HStack(spacing: 6) {
                    if launchRefreshIsRunning {
                        ProgressView(value: launchRefreshProgress)
                            .frame(width: 72)
                            .controlSize(.small)
                    } else {
                        Image(systemName: launchRefreshStatusIconName)
                            .font(.caption2)
                    }

                    Text(launchRefreshStatusMessage)
                        .font(.caption2)
                        .foregroundStyle(launchRefreshStatusColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var backupExportStatusColor: Color {
        switch backupExportStatusStyle {
        case .info:
            return .secondary
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    private var backupExportStatusIconName: String {
        switch backupExportStatusStyle {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    private var launchRefreshStatusColor: Color {
        switch launchRefreshStatusStyle {
        case .info:
            return .secondary
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    private var launchRefreshStatusIconName: String {
        switch launchRefreshStatusStyle {
        case .info:
            return "arrow.clockwise.circle"
        case .success:
            return "checkmark.circle"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    private var articleDetailPane: some View {
        Group {
            if let selectedArticle {
                ArticleDetailView(
                    article: selectedArticle,
                    tags: tags,
                    onToggleTag: toggleTag(_:for:),
                    onOpenTagManager: { showTagManager = true },
                    onRetryOfflineCaching: {
                        retryOfflineCaching(for: selectedArticle)
                    }
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

    private func scrollArticleIntoTop(using proxy: ScrollViewProxy, articleID: PersistentIdentifier) {
        guard displayedArticles.contains(where: { $0.persistentModelID == articleID }) else { return }

        let targetID = articleID
        let delays: [Double] = [0, 0.05, 0.12, 0.24]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.displayedArticles.contains(where: { $0.persistentModelID == targetID }) else { return }
                proxy.scrollTo(targetID, anchor: .top)
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
            folderName: normalizedFolderName(values.folderName),
            isTitleManuallySet: !trimmedTitle.isEmpty
        )
        guard applyProxyValues(values, to: feed) else {
            refreshError = "Could not save proxy password securely. Please verify Keychain is available and try again."
            return
        }
        feed.offlinePolicy = values.offlinePolicy
        modelContext.insert(feed)
        selectedFeedIDs = [feed.persistentModelID]
        isAllFeedsSelected = false

        _ = await refreshSingleFeed(feed)
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
        let previousOfflinePolicy = feed.offlinePolicy

        let previousFetchSignature = FeedFetchSignature(
            urlString: feed.urlString,
            useProxy: feed.useProxy,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPasswordValue
        )

        let trimmedTitle = values.title.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.title = trimmedTitle.isEmpty ? (url.host ?? trimmedURL) : trimmedTitle
        feed.isTitleManuallySet = !trimmedTitle.isEmpty
        feed.urlString = trimmedURL
        feed.folderName = normalizedFolderName(values.folderName)
        guard applyProxyValues(values, to: feed) else {
            refreshError = "Could not save proxy password securely. Please verify Keychain is available and try again."
            return
        }
        feed.offlinePolicy = values.offlinePolicy

        let updatedFetchSignature = FeedFetchSignature(
            urlString: feed.urlString,
            useProxy: feed.useProxy,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPasswordValue
        )

        try? modelContext.save()
        if previousFetchSignature != updatedFetchSignature {
            _ = await refreshSingleFeed(feed)
        } else if previousOfflinePolicy != feed.offlinePolicy && feed.offlinePolicy == .fullContent {
            enqueueOfflineCaching(for: feed.articles, feed: feed)
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

        var totalNew = 0
        var failedCount = 0

        for feed in selectedFeeds {
            let outcome = await refreshSingleFeed(feed, showGlobalSpinner: false)
            switch outcome {
            case .success(let newCount):
                totalNew += newCount
            case .failure:
                failedCount += 1
            }
        }

        recordRefreshSummary(
            buildRefreshSummary(
                prefix: "Manual refresh",
                totalNew: totalNew,
                failedCount: failedCount,
                feedCount: selectedFeeds.count
            )
        )
    }

    @MainActor
    private func refreshAllFeeds() async {
        guard !feeds.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var totalNew = 0
        var failedCount = 0

        for feed in feeds {
            let outcome = await refreshSingleFeed(feed, showGlobalSpinner: false)
            switch outcome {
            case .success(let newCount):
                totalNew += newCount
            case .failure:
                failedCount += 1
            }
        }

        recordRefreshSummary(
            buildRefreshSummary(
                prefix: "Manual refresh",
                totalNew: totalNew,
                failedCount: failedCount,
                feedCount: feeds.count
            )
        )
    }

    private func scheduleLaunchAutoRefreshIfNeeded() {
        guard autoRefreshOnLaunch else { return }
        guard !didScheduleLaunchAutoRefresh else { return }
        guard !feeds.isEmpty else { return }

        didScheduleLaunchAutoRefresh = true
        Task {
            try? await Task.sleep(nanoseconds: launchAutoRefreshDelayNanoseconds)
            await performLaunchAutoRefreshIfNeeded()
        }
    }

    @MainActor
    private func performLaunchAutoRefreshIfNeeded() async {
        guard autoRefreshOnLaunch else { return }
        guard !feeds.isEmpty else { return }

        let staleFeeds = feeds.filter { feed in
            guard let lastFetchedAt = feed.lastFetchedAt else { return true }
            return Date().timeIntervalSince(lastFetchedAt) >= launchAutoRefreshMinimumInterval
        }
        if staleFeeds.isEmpty {
            let summary = "Auto refresh skipped (recently updated)"
            finishLaunchRefreshStatus(summary, style: .info)
            recordRefreshSummary(summary)
            return
        }

        let orderedFeeds = orderedFeedsForLaunchRefresh()
        guard !orderedFeeds.isEmpty else { return }

        beginLaunchRefreshStatus(
            "Auto refresh: 0/\(orderedFeeds.count)",
            progress: 0
        )

        var totalNew = 0
        var failedCount = 0

        for (index, feed) in orderedFeeds.enumerated() {
            let outcome = await refreshSingleFeed(feed, showGlobalSpinner: false, reportErrors: false)
            switch outcome {
            case .success(let newCount):
                totalNew += newCount
            case .failure:
                failedCount += 1
            }

            let completed = index + 1
            updateLaunchRefreshStatus(
                "Auto refresh: \(completed)/\(orderedFeeds.count)",
                progress: Double(completed) / Double(orderedFeeds.count)
            )
        }

        if failedCount > 0 {
            let summary = "Auto refresh finished: \(totalNew) new, \(failedCount) failed"
            finishLaunchRefreshStatus(summary, style: .failure)
            recordRefreshSummary(summary)
        } else if totalNew > 0 {
            let summary = "Auto refresh: \(totalNew) new articles"
            finishLaunchRefreshStatus(summary, style: .success)
            recordRefreshSummary(summary)
            sendAutoRefreshNotificationIfAuthorized(newArticleCount: totalNew, feedCount: orderedFeeds.count)
        } else {
            let summary = "Auto refresh complete: no new articles"
            finishLaunchRefreshStatus(summary, style: .info)
            recordRefreshSummary(summary)
        }
    }

    private func orderedFeedsForLaunchRefresh() -> [Feed] {
        guard !feeds.isEmpty else { return [] }
        guard !isAllFeedsSelected, !selectedFeedIDs.isEmpty else { return feeds }

        let selected = feeds.filter { selectedFeedIDs.contains($0.persistentModelID) }
        let selectedIDSet = Set(selected.map(\.persistentModelID))
        let rest = feeds.filter { !selectedIDSet.contains($0.persistentModelID) }
        return selected + rest
    }

    @MainActor
    private func recordRefreshSummary(_ summary: String) {
        lastRefreshStatusSummary = summary
        lastRefreshStatusAt = Date().timeIntervalSince1970
    }

    private func buildRefreshSummary(
        prefix: String,
        totalNew: Int,
        failedCount: Int,
        feedCount: Int
    ) -> String {
        if failedCount > 0 {
            return "\(prefix): \(totalNew) new, \(failedCount) failed (\(feedCount) feeds)"
        }
        if totalNew > 0 {
            return "\(prefix): \(totalNew) new (\(feedCount) feeds)"
        }
        return "\(prefix): no new (\(feedCount) feeds)"
    }

    @MainActor
    private func refreshSingleFeed(
        _ feed: Feed,
        showGlobalSpinner: Bool = true,
        reportErrors: Bool = true
    ) async -> FeedRefreshOutcome {
        guard let url = feed.url else {
            let message = "Invalid URL for feed: \(feed.title)"
            if reportErrors {
                refreshError = message
            }
            return .failure(message: message)
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
            let fetchedTitle = parsedFeed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !feed.isTitleManuallySet, !fetchedTitle.isEmpty {
                feed.title = fetchedTitle
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
            enqueueOfflineCaching(for: newArticles, feed: feed)

            if feed.offlinePolicy == .fullContent {
                let retryCandidates = feed.articles
                    .sorted { lhs, rhs in
                        (lhs.publishedAt ?? lhs.createdAt) > (rhs.publishedAt ?? rhs.createdAt)
                    }
                    .filter { article in
                        !article.hasOfflineContent && article.offlineStatus != .caching
                    }
                let retryBatch = Array(retryCandidates.prefix(24))
                enqueueOfflineCaching(for: retryBatch, feed: feed)
            }
            return .success(newArticleCount: newArticles.count)
        } catch {
            let message = refreshFailureMessage(for: error, url: url)
            if reportErrors {
                refreshError = message
            }
            return .failure(message: message)
        }
    }

    private func refreshFailureMessage(for error: Error, url: URL) -> String {
        if let urlError = error as? URLError, urlError.code == .cannotFindHost {
            return "DNS could not resolve host '\(url.host ?? "unknown")' (\(urlError.code.rawValue)). Try enabling proxy for this feed or check your network DNS settings."
        }
        return error.localizedDescription
    }

    private func deleteFeed(_ feed: Feed) {
        selectedFeedIDs.remove(feed.persistentModelID)
        if selectedFeedIDs.isEmpty {
            isAllFeedsSelected = true
        }
        if let selectedArticleID, feed.articles.contains(where: { $0.persistentModelID == selectedArticleID }) {
            self.selectedArticleID = nil
        }
        feed.clearSecureProxyPassword()
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
            allowInsecureHTTPForContent: feed.allowInsecureHTTPForContent,
            proxyType: feed.proxyType,
            proxyHost: feed.proxyHost,
            proxyPort: feed.proxyPort,
            proxyUsername: feed.proxyUsername,
            proxyPassword: feed.proxyPasswordValue,
            offlinePolicy: feed.offlinePolicy,
            folderName: normalizedFolderName(feed.folderName),
            isTitleManuallySet: feed.isTitleManuallySet
        )
    }

    @discardableResult
    private func applyProxyValues(_ values: FeedFormValues, to feed: Feed) -> Bool {
        guard feed.setProxyPasswordSecurely(values.proxyPassword) else {
            return false
        }

        feed.useProxy = values.useProxy
        feed.useProxyForContent = values.useProxyForContent
        feed.allowInsecureHTTPForContent = values.allowInsecureHTTPForContent
        feed.proxyType = values.proxyType
        feed.proxyHost = values.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.proxyPort = values.proxyPort
        feed.proxyUsername = values.proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    private func migrateLegacyProxySecretsIfNeeded() {
        guard !didMigrateLegacyProxySecrets else { return }
        guard !feeds.isEmpty else { return }

        var migratedAny = false
        var clearedWithoutMigration = 0
        for feed in feeds {
            switch feed.migrateLegacyProxyPasswordIfNeeded() {
            case .notNeeded:
                break
            case .migrated:
                migratedAny = true
            case .clearedWithoutMigration:
                migratedAny = true
                clearedWithoutMigration += 1
            }
        }

        if migratedAny {
            try? modelContext.save()
        }
        if clearedWithoutMigration > 0 {
            refreshError = "For security, \(clearedWithoutMigration) legacy proxy password(s) could not be migrated to Keychain and were cleared. Please re-enter them."
        }
        didMigrateLegacyProxySecrets = true
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

    @MainActor
    private func retryOfflineCaching(for article: Article) {
        guard let feed = article.feed else { return }
        guard feed.offlinePolicy == .fullContent else { return }
        enqueueOfflineCaching(for: article, feed: feed, force: true)
    }

    @MainActor
    private func enqueueOfflineCaching(for candidates: [Article], feed: Feed, force: Bool = false) {
        guard feed.offlinePolicy == .fullContent else { return }
        for article in candidates {
            enqueueOfflineCaching(for: article, feed: feed, force: force)
        }
    }

    @MainActor
    private func enqueueOfflineCaching(for article: Article, feed: Feed, force: Bool = false) {
        guard feed.offlinePolicy == .fullContent else { return }
        if !force, article.hasOfflineContent { return }
        guard !offlineCachingArticleIDs.contains(article.persistentModelID) else { return }

        if !force, cacheOfflineFromFeedContentIfAvailable(for: article) {
            try? modelContext.save()
            return
        }

        let articleLink = article.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: articleLink), url.scheme?.hasPrefix("http") == true else {
            article.offlineStatus = .failed
            article.offlineLastError = "Invalid article URL."
            try? modelContext.save()
            return
        }

        let articleID = article.persistentModelID
        let generation = offlineCacheGeneration
        let selectedProxy: FeedProxyConfiguration? = feed.useProxyForContent ? feed.contentProxyConfiguration : nil
        let allowInsecureHTTPContent = feed.allowInsecureHTTPForContent

        offlineCachingArticleIDs.insert(articleID)
        article.offlineStatus = .caching
        article.offlineLastError = ""
        try? modelContext.save()

        Task(priority: .utility) {
            let result: Result<String, Error>
            do {
                let html = try await RSSService.fetchArticleHTML(
                    from: url,
                    proxy: selectedProxy,
                    allowInsecureHTTPInWebContent: allowInsecureHTTPContent
                )
                result = .success(html)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                applyOfflineCachingResult(
                    articleID: articleID,
                    generation: generation,
                    result: result
                )
            }
        }
    }

    @MainActor
    private func applyOfflineCachingResult(
        articleID: PersistentIdentifier,
        generation: Int,
        result: Result<String, Error>
    ) {
        offlineCachingArticleIDs.remove(articleID)
        guard generation == offlineCacheGeneration else { return }
        guard let article = articles.first(where: { $0.persistentModelID == articleID }) else { return }

        switch result {
        case .success(let html):
            let normalized = html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                article.offlineStatus = article.hasOfflineContent ? .cached : .failed
                article.offlineLastError = "Fetched HTML is empty."
                try? modelContext.save()
                return
            }
            article.offlineCachedHTML = html
            article.offlineCachedBytes = html.lengthOfBytes(using: .utf8)
            article.offlineCachedAt = Date()
            article.offlineLastError = ""
            article.offlineStatus = .cached
        case .failure(let error):
            if article.hasOfflineContent {
                article.offlineStatus = .cached
                article.offlineLastError = ""
            } else {
                article.offlineStatus = .failed
                article.offlineLastError = describeOfflineError(error)
            }
        }

        try? modelContext.save()
    }

    @MainActor
    private func cacheOfflineFromFeedContentIfAvailable(for article: Article) -> Bool {
        let summary = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return false }

        article.offlineCachedHTML = article.summary
        article.offlineCachedBytes = article.summary.lengthOfBytes(using: .utf8)
        article.offlineCachedAt = Date()
        article.offlineStatus = .cached
        article.offlineLastError = ""
        return true
    }

    @MainActor
    private func clearAllOfflineCache() {
        offlineCacheGeneration += 1
        offlineCachingArticleIDs.removeAll()
        for article in articles {
            clearOfflineCacheFields(for: article)
        }
        try? modelContext.save()
    }

    @MainActor
    private func clearOfflineCache(forUsage usage: OfflineCacheFeedUsage) {
        guard let feed = feeds.first(where: { $0.persistentModelID == usage.id }) else { return }

        offlineCacheGeneration += 1
        for article in feed.articles {
            offlineCachingArticleIDs.remove(article.persistentModelID)
            clearOfflineCacheFields(for: article)
        }
        try? modelContext.save()
    }

    private func clearOfflineCacheFields(for article: Article) {
        let hadCachedData = article.hasOfflineContent || article.offlineCachedBytes > 0 || !article.offlineCachedHTML.isEmpty
        article.offlineCachedHTML = ""
        article.offlineCachedBytes = 0
        article.offlineCachedAt = nil
        article.offlineLastError = ""
        article.offlineStatus = hadCachedData ? .evicted : .notCached
    }

    private func describeOfflineError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            if urlError.code == .appTransportSecurityRequiresSecureConnection {
                return "\(urlError.localizedDescription) (\(urlError.code.rawValue)). This article may be HTTP-only. Enable 'Allow Insecure HTTP Content (Per Feed)' in feed settings if you trust the source."
            }
            if urlError.code == .timedOut {
                return "\(urlError.localizedDescription) (\(urlError.code.rawValue)). The source may be slow or blocking automated fetches. Try Retry Offline again, or open the original URL in browser to verify reachability."
            }
            return "\(urlError.localizedDescription) (\(urlError.code.rawValue))"
        }
        return error.localizedDescription
    }

    private func backupDefaultFilename(for mode: BackupExportMode) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "RZZ-Backup-\(mode.displayName)-\(formatter.string(from: Date())).json"
    }

    private func triggerBackupExport(_ mode: BackupExportMode) {
        pendingBackupExportMode = mode
        #if os(macOS)
        exportBackupOnMac(mode: mode)
        #else
        prepareBackupExport(mode: mode)
        #endif
    }

    #if os(macOS)
    private func exportBackupOnMac(mode: BackupExportMode = .lite) {
        beginBackupExportStatus("Preparing \(mode.displayName) backup…", progress: 0.12)

        Task(priority: .utility) {
            do {
                let package = await MainActor.run {
                    buildBackupPackage(mode: mode)
                }
                await MainActor.run {
                    updateBackupExportStatus("Encoding \(mode.displayName) backup…", progress: 0.56)
                }

                let data = try RZZBackupCodec.encode(package)
                let fileURL = try await MainActor.run { () -> URL in
                    let folderURL = try macBackupDirectoryURL()
                    return folderURL.appendingPathComponent(backupDefaultFilename(for: mode))
                }
                await MainActor.run {
                    updateBackupExportStatus("Writing \(mode.displayName) backup…", progress: 0.84)
                }
                try data.write(to: fileURL, options: .atomic)

                await MainActor.run {
                    finishBackupExportStatus("\(mode.displayName) backup exported", style: .success)
                }
                sendBackupCompletionNotificationIfAuthorized(
                    title: "RZZ Backup Exported",
                    body: fileURL.lastPathComponent
                )
            } catch {
                await MainActor.run {
                    finishBackupExportStatus("Export failed: \(error.localizedDescription)", style: .failure)
                }
            }
        }
    }

    private func importBackupOnMac() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                importBackupOnMac()
            }
            return
        }

        do {
            let folderURL = try macBackupDirectoryURL()
            guard let latest = try latestBackupFileURL(in: folderURL) else {
                transferMessage = "No backup JSON found in backup folder."
                return
            }
            performBackupImport(from: latest)
        } catch {
            transferMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func copyBackupFolderPathOnMac() {
        do {
            let folderURL = try macBackupDirectoryURL()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(folderURL.path, forType: .string)
            transferMessage = "Backup folder path copied:\n\(folderURL.path)"
        } catch {
            transferMessage = "Failed to copy backup folder path: \(error.localizedDescription)"
        }
    }

    private func revealBackupFolderOnMac() {
        do {
            let folderURL = try macBackupDirectoryURL()
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        } catch {
            transferMessage = "Failed to open backup folder: \(error.localizedDescription)"
        }
    }

    private func macBackupDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "sivaz.RZZ"
        let folderURL = appSupportURL
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)

        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return folderURL
    }

    private func latestBackupFileURL(in folderURL: URL) throws -> URL? {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }

        return files.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }
    #endif

    private func prepareBackupExport(mode: BackupExportMode = .lite) {
        beginBackupExportStatus("Preparing \(mode.displayName) backup…", progress: 0.18)
        exportBackupDocument = RZZBackupDocument(package: buildBackupPackage(mode: mode))
        exportBackupFilename = backupDefaultFilename(for: mode)
        showExportBackup = true
        updateBackupExportStatus("Select where to save \(mode.displayName) backup…", progress: 0.38)
    }

    private func buildBackupPackage(mode: BackupExportMode = .full) -> RZZBackupPackage {
        let sortedTags = tags.sorted {
            if $0.name.caseInsensitiveCompare($1.name) == .orderedSame {
                return $0.createdAt < $1.createdAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let tagBackups = sortedTags.map { tag in
            RZZBackupTag(
                id: tag.id,
                name: tag.name,
                createdAt: tag.createdAt
            )
        }

        let feedBackups = feeds
            .sorted { $0.createdAt < $1.createdAt }
            .map { feed in
                let articleBackups = feed.articles
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { article in
                        let textOnlySummary = normalizedTextSummary(from: article.summary)
                        let summaryForBackup: String
                        let offlineStatusForBackup: String
                        let offlineHTMLForBackup: String
                        let offlineBytesForBackup: Int
                        let offlineCachedAtForBackup: Date?
                        let offlineErrorForBackup: String

                        switch mode {
                        case .lite:
                            summaryForBackup = ""
                            offlineStatusForBackup = ArticleOfflineStatus.notCached.rawValue
                            offlineHTMLForBackup = ""
                            offlineBytesForBackup = 0
                            offlineCachedAtForBackup = nil
                            offlineErrorForBackup = ""
                        case .text:
                            summaryForBackup = textOnlySummary
                            offlineStatusForBackup = ArticleOfflineStatus.notCached.rawValue
                            offlineHTMLForBackup = ""
                            offlineBytesForBackup = 0
                            offlineCachedAtForBackup = nil
                            offlineErrorForBackup = ""
                        case .full:
                            summaryForBackup = article.summary
                            offlineStatusForBackup = article.offlineStatusRaw
                            offlineHTMLForBackup = article.offlineCachedHTML
                            offlineBytesForBackup = article.offlineCachedBytes
                            offlineCachedAtForBackup = article.offlineCachedAt
                            offlineErrorForBackup = article.offlineLastError
                        }

                        return RZZBackupArticle(
                            id: article.id,
                            guid: article.guid,
                            title: article.title,
                            summary: summaryForBackup,
                            link: article.link,
                            publishedAt: article.publishedAt,
                            createdAt: article.createdAt,
                            isRead: article.isRead,
                            isStarred: article.isStarred,
                            readingScrollProgress: sanitizedProgress(article.readingScrollProgress),
                            offlineStatusRaw: offlineStatusForBackup,
                            offlineCachedHTML: offlineHTMLForBackup,
                            offlineCachedBytes: offlineBytesForBackup,
                            offlineCachedAt: offlineCachedAtForBackup,
                            offlineLastError: offlineErrorForBackup,
                            tagIDs: article.tags.map(\.id)
                        )
                    }

                return RZZBackupFeed(
                    id: feed.id,
                    title: feed.title,
                    isTitleManuallySet: feed.isTitleManuallySet,
                    urlString: feed.urlString,
                    offlinePolicyRaw: feed.offlinePolicyRaw,
                    useProxy: feed.useProxy,
                    useProxyForContent: feed.useProxyForContent,
                    allowInsecureHTTPForContent: feed.allowInsecureHTTPForContent,
                    proxyTypeRaw: feed.proxyTypeRaw,
                    proxyHost: feed.proxyHost,
                    proxyPort: feed.proxyPort,
                    proxyUsername: feed.proxyUsername,
                    hasProxyPassword: !feed.proxyPasswordValue.isEmpty,
                    folderName: normalizedFolderName(feed.folderName),
                    createdAt: feed.createdAt,
                    lastFetchedAt: feed.lastFetchedAt,
                    articles: articleBackups
                )
            }

        return RZZBackupPackage(
            version: RZZBackupPackage.currentVersion,
            exportedAt: Date(),
            settings: RZZBackupSettings(customFeedFolderNames: customFolderNames),
            tags: tagBackups,
            feeds: feedBackups
        )
    }

    private func normalizedTextSummary(from raw: String) -> String {
        let text = HTMLText.makePreview(from: raw)
        guard !text.isEmpty else { return "" }
        if text.count <= backupTextSummaryCharacterLimit {
            return text
        }
        return String(text.prefix(backupTextSummaryCharacterLimit))
    }

    @MainActor
    private func beginBackupExportStatus(_ message: String, progress: Double) {
        backupExportStatusToken = UUID()
        backupExportStatusMessage = message
        backupExportStatusProgress = min(max(progress, 0), 1)
        backupExportStatusStyle = .info
        backupExportIsRunning = true
    }

    @MainActor
    private func updateBackupExportStatus(_ message: String, progress: Double) {
        backupExportStatusMessage = message
        backupExportStatusProgress = min(max(progress, 0), 1)
        backupExportStatusStyle = .info
        backupExportIsRunning = true
    }

    @MainActor
    private func finishBackupExportStatus(_ message: String, style: BackupExportStatusStyle) {
        backupExportStatusToken = UUID()
        let token = backupExportStatusToken
        backupExportStatusMessage = message
        backupExportStatusStyle = style
        backupExportIsRunning = false
        if style == .success {
            backupExportStatusProgress = 1
        }

        let delaySeconds: Double = style == .failure ? 12 : 7
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await MainActor.run {
                guard token == backupExportStatusToken else { return }
                guard !backupExportIsRunning else { return }
                backupExportStatusMessage = nil
                backupExportStatusProgress = 0
                backupExportStatusStyle = .info
            }
        }
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func sendBackupCompletionNotificationIfAuthorized(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: "rzz-backup-export-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    @MainActor
    private func beginLaunchRefreshStatus(_ message: String, progress: Double) {
        launchRefreshStatusToken = UUID()
        launchRefreshStatusMessage = message
        launchRefreshProgress = min(max(progress, 0), 1)
        launchRefreshStatusStyle = .info
        launchRefreshIsRunning = true
    }

    @MainActor
    private func updateLaunchRefreshStatus(_ message: String, progress: Double) {
        launchRefreshStatusMessage = message
        launchRefreshProgress = min(max(progress, 0), 1)
        launchRefreshStatusStyle = .info
        launchRefreshIsRunning = true
    }

    @MainActor
    private func finishLaunchRefreshStatus(_ message: String, style: LaunchRefreshStatusStyle) {
        launchRefreshStatusToken = UUID()
        let token = launchRefreshStatusToken
        launchRefreshStatusMessage = message
        launchRefreshStatusStyle = style
        launchRefreshIsRunning = false
        if style == .success {
            launchRefreshProgress = 1
        }

        let delaySeconds: Double = style == .failure ? 12 : 8
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await MainActor.run {
                guard token == launchRefreshStatusToken else { return }
                guard !launchRefreshIsRunning else { return }
                launchRefreshStatusMessage = nil
                launchRefreshProgress = 0
                launchRefreshStatusStyle = .info
            }
        }
    }

    private func sendAutoRefreshNotificationIfAuthorized(newArticleCount: Int, feedCount: Int) {
        guard newArticleCount > 0 else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "RZZ Auto Refresh"
            content.body = "\(newArticleCount) new articles from \(feedCount) feeds."
            let request = UNNotificationRequest(
                identifier: "rzz-auto-refresh-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func handleBackupExportResult(_ result: Result<URL, Error>) {
        let mode = pendingBackupExportMode
        switch result {
        case .success(let url):
            finishBackupExportStatus("\(mode.displayName) backup exported", style: .success)
            sendBackupCompletionNotificationIfAuthorized(
                title: "RZZ Backup Exported",
                body: url.lastPathComponent
            )
        case .failure(let error):
            if isUserCancelled(error) {
                finishBackupExportStatus("Export canceled", style: .info)
            } else {
                finishBackupExportStatus("Export failed: \(error.localizedDescription)", style: .failure)
            }
        }
    }

    private func handleBackupImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            performBackupImport(from: url)
        case .failure(let error):
            transferMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func performBackupImport(from url: URL) {
        do {
            let data = try loadBackupData(from: url)
            let package = try RZZBackupCodec.decode(data)
            try importBackupPackage(package)

            let importedFeedCount = package.feeds.count
            let importedArticleCount = package.feeds.reduce(0) { $0 + $1.articles.count }
            let importedTagCount = package.tags.count
            transferMessage = "Import complete: \(importedFeedCount) feeds, \(importedArticleCount) articles, \(importedTagCount) tags."
        } catch {
            transferMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func loadBackupData(from url: URL) throws -> Data {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    @MainActor
    private func importBackupPackage(_ package: RZZBackupPackage) throws {
        guard package.version == RZZBackupPackage.currentVersion else {
            throw NSError(
                domain: "RZZBackup",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported backup version \(package.version)."]
            )
        }

        // Import is replace-all by design to keep restoration deterministic.
        for feed in feeds {
            feed.clearSecureProxyPassword()
            modelContext.delete(feed)
        }
        for tag in tags {
            modelContext.delete(tag)
        }
        for article in articles where article.feed == nil {
            modelContext.delete(article)
        }

        offlineCacheGeneration += 1
        offlineCachingArticleIDs.removeAll()
        selectedArticleID = nil
        selectedFeedIDs.removeAll()
        isAllFeedsSelected = true
        selectedTagFilterUUIDString = ""

        saveCustomFolderNames(Set(package.settings.customFeedFolderNames.map(normalizedFolderName(_:))))

        var tagByID: [UUID: Tag] = [:]
        for backupTag in package.tags.sorted(by: { $0.createdAt < $1.createdAt }) {
            let tag = Tag(name: backupTag.name)
            tag.id = backupTag.id
            tag.createdAt = backupTag.createdAt
            modelContext.insert(tag)
            tagByID[backupTag.id] = tag
        }

        for backupFeed in package.feeds.sorted(by: { $0.createdAt < $1.createdAt }) {
            let feed = Feed(
                title: backupFeed.title,
                urlString: backupFeed.urlString,
                folderName: normalizedFolderName(backupFeed.folderName),
                isTitleManuallySet: backupFeed.isTitleManuallySet
            )
            feed.id = backupFeed.id
            feed.offlinePolicyRaw = backupFeed.offlinePolicyRaw
            feed.useProxy = backupFeed.useProxy
            feed.useProxyForContent = backupFeed.useProxyForContent
            feed.allowInsecureHTTPForContent = backupFeed.allowInsecureHTTPForContent
            feed.proxyTypeRaw = backupFeed.proxyTypeRaw
            feed.proxyHost = backupFeed.proxyHost
            feed.proxyPort = backupFeed.proxyPort
            feed.proxyUsername = backupFeed.proxyUsername
            feed.proxyPassword = ""
            feed.createdAt = backupFeed.createdAt
            feed.lastFetchedAt = backupFeed.lastFetchedAt
            modelContext.insert(feed)

            for backupArticle in backupFeed.articles.sorted(by: { $0.createdAt < $1.createdAt }) {
                let article = Article(
                    guid: backupArticle.guid,
                    title: backupArticle.title,
                    summary: backupArticle.summary,
                    link: backupArticle.link,
                    publishedAt: backupArticle.publishedAt,
                    feed: feed
                )
                article.id = backupArticle.id
                article.createdAt = backupArticle.createdAt
                article.isRead = backupArticle.isRead
                article.isStarred = backupArticle.isStarred
                article.readingScrollProgress = sanitizedProgress(backupArticle.readingScrollProgress)
                article.offlineStatusRaw = backupArticle.offlineStatusRaw
                article.offlineCachedHTML = backupArticle.offlineCachedHTML
                article.offlineCachedBytes = backupArticle.offlineCachedBytes
                article.offlineCachedAt = backupArticle.offlineCachedAt
                article.offlineLastError = backupArticle.offlineLastError
                article.tags = backupArticle.tagIDs.compactMap { tagByID[$0] }
                modelContext.insert(article)
            }
        }

        try modelContext.save()
    }

    private func sanitizedProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
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

    private func requestFocusForSelectedFeed(_ feed: Feed) {
        guard !isAllFeedsSelected else { return }
        guard selectedFeedIDs.contains(feed.persistentModelID) else { return }
        guard let firstArticle = groupedDisplayedArticles
            .first(where: { $0.feed.persistentModelID == feed.persistentModelID })?
            .articles
            .first else { return }

        articleListFocusRequest = ArticleListFocusRequest(articleID: firstArticle.persistentModelID)
    }

    private func focusFirstVisibleArticle() {
        guard let first = displayedArticles.first else { return }
        articleListFocusRequest = ArticleListFocusRequest(articleID: first.persistentModelID)
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
    let offlinePolicy: FeedOfflinePolicy
    let allowsInsecureHTTPContent: Bool
    let onSelectionTap: () -> Void
    var onTitleTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelectionTap) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
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
            .contentShape(Rectangle())
            .onTapGesture {
                onTitleTap?()
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
            if offlinePolicy == .fullContent {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Offline full content enabled")
            } else if offlinePolicy == .metadataOnly {
                Image(systemName: "text.justify")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Offline metadata mode")
            }
            if allowsInsecureHTTPContent {
                Image(systemName: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Insecure HTTP content allowed for this feed")
            }
        }
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

                if let indicator = offlineIndicator {
                    Image(systemName: indicator.symbol)
                        .foregroundStyle(indicator.color)
                        .font(.caption)
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

    private var offlineIndicator: (symbol: String, color: Color)? {
        switch article.offlineStatus {
        case .cached:
            return ("arrow.down.circle.fill", .green)
        case .caching:
            return ("arrow.triangle.2.circlepath", .secondary)
        case .failed:
            return ("exclamationmark.triangle.fill", .orange)
        case .evicted:
            return ("tray.and.arrow.up", .secondary)
        case .notCached:
            return nil
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let tags: [Tag]
    let onToggleTag: (Tag, Article) -> Void
    let onOpenTagManager: () -> Void
    let onRetryOfflineCaching: () -> Void
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

                if article.feed?.offlinePolicy == .fullContent {
                    Button {
                        onRetryOfflineCaching()
                    } label: {
                        Label(
                            article.offlineStatus == .cached ? "Refresh Cache" : "Retry Offline",
                            systemImage: "arrow.clockwise.circle"
                        )
                    }
                    .disabled(article.offlineStatus == .caching)
                }

                if let url = URL(string: article.link), !article.link.isEmpty {
                    Menu {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        Button {
                            copyToClipboard(article.link)
                        } label: {
                            Label("Copy Original URL", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Label("Original", systemImage: "safari")
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
                offlineStatusPill
                if article.feed?.allowInsecureHTTPForContent == true {
                    statusPill(title: "HTTP", value: "Allowed", icon: "exclamationmark.shield")
                }
                if contentLoadState == .fallbackSummary {
                    statusPill(title: "Fallback", value: "Summary", icon: "arrow.uturn.backward.circle")
                }
            }

            if shouldShowOfflineFailureMessage {
                Text("Offline cache failed: \(article.offlineLastError)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
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
                            sourceURL: URL(string: article.link),
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
        let allowInsecureHTTPContent = article.feed?.allowInsecureHTTPForContent ?? false
        let offlinePolicy = article.feed?.offlinePolicy ?? .off
        let cachedHTML = article.offlineCachedHTML
        let hasCachedHTML = article.hasOfflineContent
        let hasFallbackHTML = !fallbackHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldPrimeWithFallback = offlinePolicy == .fullContent && !hasCachedHTML && hasFallbackHTML

        withAnimation(.easeInOut(duration: 0.12)) {
            contentPathUsesProxy = shouldUseProxyForContent
            if shouldPrimeWithFallback {
                contentLoadState = .fallbackSummary
                bodyHTML = fallbackHTML
                isBodyLoading = false
                showSkeleton = false
            } else {
                contentLoadState = .loading
                bodyHTML = ""
                isBodyLoading = true
                showSkeleton = true
            }
        }
        lastSavedScrollProgress = article.readingScrollProgress

        if hasCachedHTML {
            withAnimation(.easeInOut(duration: 0.12)) {
                contentLoadState = .loaded
                bodyHTML = cachedHTML
                isBodyLoading = false
                showSkeleton = false
            }
            if offlinePolicy == .fullContent {
                return
            }
        }

        guard let url = URL(string: articleLink), url.scheme?.hasPrefix("http") == true else {
            withAnimation(.easeInOut(duration: 0.12)) {
                contentLoadState = hasCachedHTML ? .loaded : .fallbackSummary
                bodyHTML = hasCachedHTML ? cachedHTML : fallbackHTML
                isBodyLoading = false
                showSkeleton = false
            }
            return
        }

        bodyLoadTask = Task {
            let selectedProxy: FeedProxyConfiguration? = shouldUseProxyForContent ? proxy : nil
            let result: Result<String, Error>
            do {
                let fetched = try await RSSService.fetchArticleHTML(
                    from: url,
                    proxy: selectedProxy,
                    allowInsecureHTTPInWebContent: allowInsecureHTTPContent
                )
                result = .success(fetched)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                guard activeBodyLoadID == loadID else { return }
                guard !Task.isCancelled else { return }

                switch result {
                case .success(let fetchedHTML):
                    if offlinePolicy == .fullContent {
                        setOfflineCacheFromFetchedHTML(fetchedHTML)
                    } else if article.offlineStatus == .failed {
                        article.offlineStatus = .notCached
                        article.offlineLastError = ""
                        try? modelContext.save()
                    }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        contentLoadState = .loaded
                        bodyHTML = fetchedHTML
                        isBodyLoading = false
                        showSkeleton = false
                    }
                case .failure(let error):
                    if offlinePolicy == .fullContent {
                        updateOfflineFailureState(error)
                    }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        if article.hasOfflineContent {
                            contentLoadState = .loaded
                            bodyHTML = article.offlineCachedHTML
                        } else {
                            contentLoadState = .fallbackSummary
                            bodyHTML = fallbackHTML
                        }
                        isBodyLoading = false
                        showSkeleton = false
                    }
                }
            }
        }
    }

    private var shouldShowOfflineFailureMessage: Bool {
        let policy = article.feed?.offlinePolicy ?? .off
        guard policy == .fullContent else { return false }
        guard article.offlineStatus == .failed else { return false }
        guard !article.offlineLastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func persistReadingProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        guard abs(clamped - lastSavedScrollProgress) >= 0.01 else { return }
        lastSavedScrollProgress = clamped
        article.readingScrollProgress = clamped
    }

    @ViewBuilder
    private var offlineStatusPill: some View {
        let policy = article.feed?.offlinePolicy ?? .off

        switch policy {
        case .off:
            statusPill(title: "Offline", value: "Off", icon: "icloud")
        case .metadataOnly:
            statusPill(title: "Offline", value: "Meta", icon: "doc.text")
        case .fullContent:
            switch article.offlineStatus {
            case .cached:
                statusPill(title: "Offline", value: "Cached", icon: "arrow.down.circle")
            case .caching:
                statusPill(title: "Offline", value: "Caching", icon: "arrow.triangle.2.circlepath")
            case .failed:
                statusPill(title: "Offline", value: "Failed", icon: "exclamationmark.triangle")
            case .evicted:
                statusPill(title: "Offline", value: "Evicted", icon: "tray.and.arrow.up")
            case .notCached:
                statusPill(title: "Offline", value: "Pending", icon: "clock")
            }
        }
    }

    private func setOfflineCacheFromFetchedHTML(_ html: String) {
        let normalized = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        article.offlineCachedHTML = html
        article.offlineCachedBytes = html.lengthOfBytes(using: .utf8)
        article.offlineCachedAt = Date()
        article.offlineStatus = .cached
        article.offlineLastError = ""
        try? modelContext.save()
    }

    private func updateOfflineFailureState(_ error: Error) {
        let hasVisibleContent = !bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if article.hasOfflineContent {
            article.offlineStatus = .cached
        } else if hasVisibleContent {
            article.offlineStatus = .notCached
            article.offlineLastError = ""
            try? modelContext.save()
            return
        } else {
            article.offlineStatus = .failed
        }

        if let urlError = error as? URLError {
            if urlError.code == .appTransportSecurityRequiresSecureConnection {
                article.offlineLastError = "\(urlError.localizedDescription) (\(urlError.code.rawValue)). This article may be HTTP-only. Enable 'Allow Insecure HTTP Content (Per Feed)' in feed settings if you trust the source."
                try? modelContext.save()
                return
            }
            if urlError.code == .timedOut {
                article.offlineLastError = "\(urlError.localizedDescription) (\(urlError.code.rawValue)). The source may be slow or blocking automated fetches. Try Retry Offline again, or open the original URL in browser to verify reachability."
                try? modelContext.save()
                return
            }
            article.offlineLastError = "\(urlError.localizedDescription) (\(urlError.code.rawValue))"
        } else {
            article.offlineLastError = error.localizedDescription
        }
        try? modelContext.save()
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
    var sourceURL: URL? = nil
    var initialScrollProgress: Double = 0
    var onScrollProgressChange: (Double) -> Void = { _ in }
    var onLoadingStateChange: (Bool) -> Void = { _ in }

    var body: some View {
        HTMLWebView(
            html: htmlDocument,
            baseURL: sourceURL,
            initialScrollProgress: initialScrollProgress,
            onScrollProgressChange: onScrollProgressChange,
            onLoadingStateChange: onLoadingStateChange
        )
            .background(Color.clear)
    }

    private var htmlDocument: String {
        applyReaderOverrides(to: htmlBody)
    }

    private func applyReaderOverrides(to html: String) -> String {
        let extracted = extractPrimaryContent(from: html)
        let sanitized = sanitizeContentMarkup(extracted)

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root { color-scheme: light dark; }
        html { -webkit-text-size-adjust: 100% !important; }
        body {
          margin: 0;
          padding: 12px;
          font: -apple-system-body;
          font-size: 17px;
          line-height: 1.6;
          word-break: break-word;
          overflow-x: hidden;
        }
        article.rzz-reader {
          max-width: 100%;
          margin: 0 auto;
        }
        h1, h2, h3, h4, h5, h6 {
          line-height: 1.3;
          margin: 0.9em 0 0.45em;
        }
        h1 { font-size: 1.55em; }
        h2 { font-size: 1.35em; }
        h3 { font-size: 1.2em; }
        img, video, iframe, svg, canvas {
          max-width: 100% !important;
          height: auto !important;
          border-radius: 8px;
        }
        table, pre, code {
          max-width: 100% !important;
          white-space: pre-wrap;
          word-break: break-word;
        }
        a { text-decoration: none; }
        </style>
        <script>
        (function() {
          function normalizeURL(value) {
            if (!value) return "";
            var trimmed = String(value).trim();
            if (!trimmed) return "";
            if (trimmed.startsWith("//")) return "https:" + trimmed;
            return trimmed;
          }

          function firstAttr(el, names) {
            for (var i = 0; i < names.length; i++) {
              var v = el.getAttribute(names[i]);
              if (v && String(v).trim()) return v;
            }
            return "";
          }

          function normalizeMedia() {
            var imgs = document.querySelectorAll("img");
            imgs.forEach(function(img) {
              var src = firstAttr(img, ["src", "data-src", "data-original", "data-url", "data-lazy-src", "data-ks-lazyload"]);
              if ((!img.getAttribute("src") || !String(img.getAttribute("src")).trim()) && src) {
                img.setAttribute("src", normalizeURL(src));
              }
              if (!img.getAttribute("srcset")) {
                var srcset = firstAttr(img, ["data-srcset", "srcset"]);
                if (srcset) img.setAttribute("srcset", srcset);
              }
            });
          }

          function normalizeLinks() {
            var anchors = document.querySelectorAll("a");
            anchors.forEach(function(a) {
              var href = firstAttr(a, ["href", "data-href", "data-url", "data-link"]);
              if ((!a.getAttribute("href") || !String(a.getAttribute("href")).trim()) && href) {
                a.setAttribute("href", normalizeURL(href));
              }
            });
          }

          function run() {
            normalizeMedia();
            normalizeLinks();
          }

          document.addEventListener("DOMContentLoaded", run);
          window.addEventListener("load", run);
          setTimeout(run, 0);
          setTimeout(run, 120);
        })();
        </script>
        </head>
        <body>
        <article class="rzz-reader">
        \(sanitized)
        </article>
        </body>
        </html>
        """
    }

    private func extractPrimaryContent(from html: String) -> String {
        if let article = firstCapturedGroup(in: html, pattern: "<article\\b[^>]*>([\\s\\S]*?)</article>") {
            return article
        }
        if let main = firstCapturedGroup(in: html, pattern: "<main\\b[^>]*>([\\s\\S]*?)</main>") {
            return main
        }
        if let body = firstCapturedGroup(in: html, pattern: "<body\\b[^>]*>([\\s\\S]*?)</body>") {
            return body
        }
        return html
    }

    private func firstCapturedGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func sanitizeContentMarkup(_ input: String) -> String {
        var output = input
        let patterns: [String] = [
            "<script\\b[^>]*>[\\s\\S]*?</script>",
            "<style\\b[^>]*>[\\s\\S]*?</style>",
            "<noscript\\b[^>]*>[\\s\\S]*?</noscript>",
            "<meta\\b[^>]*>",
            "<link\\b[^>]*>",
            "<(?:header|nav|aside|footer|form)\\b[^>]*>[\\s\\S]*?</(?:header|nav|aside|footer|form)>"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }

        let attributePatterns: [String] = [
            "\\sstyle\\s*=\\s*(\"[^\"]*\"|'[^']*')",
            "\\s(?:width|height)\\s*=\\s*(\"[^\"]*\"|'[^']*'|\\S+)",
            "\\son\\w+\\s*=\\s*(\"[^\"]*\"|'[^']*')"
        ]

        for pattern in attributePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
        }

        return output
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
    @State private var allowInsecureHTTPForContent: Bool
    @State private var proxyType: FeedProxyType
    @State private var proxyHost: String
    @State private var proxyPortString: String
    @State private var proxyUsername: String
    @State private var proxyPassword: String
    @State private var offlinePolicy: FeedOfflinePolicy
    @State private var selectedFolderName: String

    let modeTitle: String
    let saveButtonTitle: String
    let initialTitle: String
    let initialURLString: String
    let initialUseProxy: Bool
    let initialUseProxyForContent: Bool
    let initialAllowInsecureHTTPForContent: Bool
    let initialProxyType: FeedProxyType
    let initialProxyHost: String
    let initialProxyPort: Int?
    let initialProxyUsername: String
    let initialProxyPassword: String
    let initialOfflinePolicy: FeedOfflinePolicy
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
        initialAllowInsecureHTTPForContent: Bool,
        initialProxyType: FeedProxyType,
        initialProxyHost: String,
        initialProxyPort: Int?,
        initialProxyUsername: String,
        initialProxyPassword: String,
        initialOfflinePolicy: FeedOfflinePolicy,
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
        self.initialAllowInsecureHTTPForContent = initialAllowInsecureHTTPForContent
        self.initialProxyType = initialProxyType
        self.initialProxyHost = initialProxyHost
        self.initialProxyPort = initialProxyPort
        self.initialProxyUsername = initialProxyUsername
        self.initialProxyPassword = initialProxyPassword
        self.initialOfflinePolicy = initialOfflinePolicy
        self.initialFolderName = initialFolderName
        self.availableFolderNames = availableFolderNames
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _urlString = State(initialValue: initialURLString)
        _useProxy = State(initialValue: initialUseProxy)
        _useProxyForContent = State(initialValue: initialUseProxyForContent)
        _allowInsecureHTTPForContent = State(initialValue: initialAllowInsecureHTTPForContent)
        _proxyType = State(initialValue: initialProxyType)
        _proxyHost = State(initialValue: initialProxyHost)
        _proxyPortString = State(initialValue: initialProxyPort.map(String.init) ?? "")
        _proxyUsername = State(initialValue: initialProxyUsername)
        _proxyPassword = State(initialValue: initialProxyPassword)
        _offlinePolicy = State(initialValue: initialOfflinePolicy)
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

            Section("Offline Reading") {
                Picker("Mode", selection: $offlinePolicy) {
                    ForEach(FeedOfflinePolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                Toggle("Allow Insecure HTTP Content (Per Feed)", isOn: $allowInsecureHTTPForContent)

                Text("Full Content preloads article pages for offline reading. Metadata Only keeps feed metadata only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("When enabled, HTTP article pages for this feed can be loaded via Web content fallback. This is less secure than HTTPS.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                allowInsecureHTTPForContent: allowInsecureHTTPForContent,
                proxyType: proxyType,
                proxyHost: proxyHost,
                proxyPort: Int(proxyPortString),
                proxyUsername: proxyUsername,
                proxyPassword: proxyPassword,
                offlinePolicy: offlinePolicy,
                folderName: selectedFolderName
            )
        )
        dismiss()
    }
}

private struct OfflineStorageView: View {
    @Environment(\.dismiss) private var dismiss
    let totalCachedCount: Int
    let totalCachedBytes: Int
    let feedUsages: [OfflineCacheFeedUsage]
    let onClearAll: () -> Void
    let onClearFeed: (OfflineCacheFeedUsage) -> Void

    private var totalBytesLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalCachedBytes), countStyle: .file)
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Offline Storage")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Label("\(totalCachedCount) cached articles", systemImage: "doc.text")
                    Label(totalBytesLabel, systemImage: "internaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if feedUsages.isEmpty {
                    ContentUnavailableView(
                        "No Offline Cache",
                        systemImage: "internaldrive",
                        description: Text("Set a feed to Full Content and refresh to cache article pages.")
                    )
                } else {
                    List {
                        ForEach(feedUsages) { usage in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(usage.feedTitle)
                                        .lineLimit(1)
                                    Text("\(usage.cachedCount) articles · \(ByteCountFormatter.string(fromByteCount: Int64(usage.cachedBytes), countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button("Clear") {
                                    onClearFeed(usage)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .frame(minHeight: 250)
                }
            }
            .padding(12)

            Divider()
            HStack {
                Button("Clear All Cache", role: .destructive) {
                    onClearAll()
                }
                .disabled(feedUsages.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 430)
        #else
        NavigationStack {
            List {
                Section("Summary") {
                    Label("\(totalCachedCount) cached articles", systemImage: "doc.text")
                    Label(totalBytesLabel, systemImage: "internaldrive")
                }

                if feedUsages.isEmpty {
                    Section {
                        Text("No offline cache yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Per Feed") {
                        ForEach(feedUsages) { usage in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(usage.feedTitle)
                                        .lineLimit(1)
                                    Text("\(usage.cachedCount) · \(ByteCountFormatter.string(fromByteCount: Int64(usage.cachedBytes), countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button("Clear") {
                                    onClearFeed(usage)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Offline Storage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear All", role: .destructive) {
                        onClearAll()
                    }
                    .disabled(feedUsages.isEmpty)
                }
            }
        }
        #endif
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
    ContentView(
        isAppLocked: .constant(false),
        appLockPINHash: .constant("")
    )
        .modelContainer(for: [Feed.self, Article.self, Tag.self], inMemory: true)
}
