import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PerformanceDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isEnabled: Bool
    let samples: [PerformanceSample]
    let onClear: () -> Void

    private var renderSampleCount: Int {
        samples.filter { $0.kind == .render }.count
    }

    private var offlineWriteCount: Int {
        samples.filter { $0.kind == .offlineWrite }.count
    }

    private var scrollBridgeCount: Int {
        samples.filter { $0.kind == .scrollBridge }.count
    }

    private var progressCommitCount: Int {
        samples.filter { $0.kind == .progressCommit }.count
    }

    private var mainThreadLagCount: Int {
        samples.filter { $0.kind == .mainThreadLag }.count
    }

    private var articleListScrollCount: Int {
        samples.filter { $0.kind == .articleListScroll }.count
    }

    private var articleListMainLagCount: Int {
        samples.filter { $0.kind == .articleListMainLag }.count
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Performance Diagnostics")
                    .font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Label("\(renderSampleCount) render", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Label("\(offlineWriteCount) offline write", systemImage: "internaldrive")
                        .foregroundStyle(.secondary)
                    Label("\(scrollBridgeCount) scroll bridge", systemImage: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                    Label("\(progressCommitCount) progress commit", systemImage: "bookmark")
                        .foregroundStyle(.secondary)
                    Label("\(mainThreadLagCount) main lag", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Label("\(articleListScrollCount) list scroll", systemImage: "list.bullet")
                        .foregroundStyle(.secondary)
                    Label("\(articleListMainLagCount) list lag", systemImage: "bolt.horizontal.circle")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if samples.isEmpty {
                    ContentUnavailableView(
                        "No Diagnostics Yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Enable diagnostics, then open and scroll some articles.")
                    )
                } else {
                    List(samples) { sample in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(sample.kind.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f ms", sample.durationMs))
                                    .font(.caption2)
                                    .monospacedDigit()
                                if let htmlBytes = sample.htmlBytes {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(htmlBytes), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sample.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(sample.articleTitle)
                                .lineLimit(1)
                            Text(sample.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 260)
                }
            }
            .padding(12)

            Divider()
            HStack {
                Button("Clear", role: .destructive) { onClear() }
                    .disabled(samples.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 480)
        #else
        NavigationStack {
            List {
                Section("Controls") {
                    Toggle("Enable Diagnostics", isOn: $isEnabled)
                }
                Section("Summary") {
                    Label("\(renderSampleCount) render", systemImage: "clock")
                    Label("\(offlineWriteCount) offline write", systemImage: "internaldrive")
                    Label("\(scrollBridgeCount) scroll bridge", systemImage: "arrow.left.arrow.right")
                    Label("\(progressCommitCount) progress commit", systemImage: "bookmark")
                    Label("\(mainThreadLagCount) main lag", systemImage: "exclamationmark.triangle")
                    Label("\(articleListScrollCount) list scroll", systemImage: "list.bullet")
                    Label("\(articleListMainLagCount) list lag", systemImage: "bolt.horizontal.circle")
                }
                Section("Samples") {
                    if samples.isEmpty {
                        Text("No diagnostics yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(samples) { sample in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(sample.kind.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.2f ms", sample.durationMs))
                                        .font(.caption2)
                                        .monospacedDigit()
                                    if let htmlBytes = sample.htmlBytes {
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(htmlBytes), countStyle: .file))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(sample.articleTitle)
                                    .lineLimit(1)
                                Text(sample.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear", role: .destructive) { onClear() }
                        .disabled(samples.isEmpty)
                }
            }
        }
        #endif
    }
}

struct RefreshDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let timestamp: Date?
    let details: [FeedRefreshDetail]
    let onRetryFailedOnly: (() -> Void)?

    private var failedCount: Int {
        details.filter(\.isFailure).count
    }

    private var succeededCount: Int {
        details.count - failedCount
    }

    private var timestampLabel: String? {
        guard let timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let timestampLabel {
                        Text(timestampLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Label("\(succeededCount) success", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Label("\(failedCount) failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(failedCount > 0 ? .red : .secondary)
                }
                .font(.caption)

                if details.isEmpty {
                    ContentUnavailableView(
                        "No Details",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Run a refresh to see per-feed results.")
                    )
                } else {
                    List(details) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isFailure ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(item.isFailure ? .red : .green)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.feedTitle)
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(item.isFailure ? .red : .secondary)
                                    .lineLimit(2)
                                if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                                    Text(sourceURL)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                                Button {
                                    copyToClipboard(sourceURL)
                                } label: {
                                    Label("Copy URL", systemImage: "doc.on.doc")
                                }
                            }
                            Button {
                                copyToClipboard("\(item.feedTitle)\n\(item.detail)")
                            } label: {
                                Label("Copy Detail", systemImage: "text.quote")
                            }
                        }
                    }
                    .frame(minHeight: 260)
                }
            }
            .padding(12)

            Divider()
            HStack {
                if let onRetryFailedOnly {
                    Button("Retry Failed Only") {
                        onRetryFailedOnly()
                    }
                    .disabled(failedCount == 0)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 620, height: 470)
        #else
        NavigationStack {
            List {
                Section("Summary") {
                    Label("\(succeededCount) success", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Label("\(failedCount) failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(failedCount > 0 ? .red : .secondary)
                    if let timestampLabel {
                        Text(timestampLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Feeds") {
                    if details.isEmpty {
                        Text("No details yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(details) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: item.isFailure ? "xmark.circle.fill" : "checkmark.circle.fill")
                                        .foregroundStyle(item.isFailure ? .red : .green)
                                        .font(.caption)
                                    Text(item.feedTitle)
                                        .lineLimit(1)
                                }
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(item.isFailure ? .red : .secondary)
                                if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                                    Text(sourceURL)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let onRetryFailedOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Retry Failed") {
                            onRetryFailedOnly()
                        }
                        .disabled(failedCount == 0)
                    }
                }
            }
        }
        #endif
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

struct OfflineStorageView: View {
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

struct TagRenameDraft: Identifiable {
    let id = UUID()
    let tagID: PersistentIdentifier
    let currentName: String
}

struct TagManagerView: View {
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

struct FolderFormView: View {
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

