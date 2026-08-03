import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct RZZApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("app_lock_pin_hash") private var legacyAppLockPINHash = ""
    @AppStorage("app_theme_mode") private var appThemeModeRaw = ""
    #if os(macOS)
    @AppStorage("minimize_to_menu_bar_enabled") private var minimizeToMenuBarEnabled = true
    @AppStorage("menu_bar_hidden_mode_active") private var menuBarHiddenModeActive = false
    @AppStorage("main_window_zoomed") private var mainWindowZoomed = false
    @AppStorage("main_window_frame_saved") private var mainWindowFrameSaved = false
    @AppStorage("main_window_origin_x") private var mainWindowOriginX = 120.0
    @AppStorage("main_window_origin_y") private var mainWindowOriginY = 120.0
    @AppStorage("main_window_width") private var mainWindowWidth = 1320.0
    @AppStorage("main_window_height") private var mainWindowHeight = 860.0
    #endif

    private let dataStoreBootstrap = DataStoreBootstrap.bootstrap()

    @State private var appLockPINHash = ""
    @State private var isAppLocked = false
    @State private var shouldLockOnNextActive = false
    @State private var isPrivacyShieldVisible = false
    @State private var hasShownDataStoreWarning = false
    @State private var transferMessage: String?
    @State private var showThemeOnboarding = false
    @State private var showAboutSheet = false
    @State private var showHelpSheet = false
    #if os(macOS)
    @State private var didApplyMainWindowState = false
    #endif

    var body: some Scene {
        WindowGroup {
            rootWindowContent
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About RZZ") {
                    showAboutSheet = true
                }
            }
            CommandGroup(replacing: .help) {
                Button("RZZ Help") {
                    showHelpSheet = true
                }
                Divider()
                Button("Open Issue Tracker") {
                    if let url = URL(string: "https://github.com/RyanChiu/rzz-apple/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            guard dataStoreBootstrap.container != nil else { return }
            switch newPhase {
            case .inactive, .background:
                isPrivacyShieldVisible = true
                if appLockEnabled, !appLockPINHash.isEmpty {
                    shouldLockOnNextActive = true
                }
            case .active:
                if appLockEnabled, !appLockPINHash.isEmpty, shouldLockOnNextActive {
                    isAppLocked = true
                }
                shouldLockOnNextActive = false
                isPrivacyShieldVisible = false
            @unknown default:
                break
            }
        }
        .onChange(of: appLockEnabled) { _, isEnabled in
            if !isEnabled {
                isAppLocked = false
                shouldLockOnNextActive = false
            }
        }

        #if os(macOS)
        MenuBarExtra {
            Button {
                if menuBarHiddenModeActive {
                    showFromMenuBar()
                } else {
                    hideToMenuBar()
                }
            } label: {
                Label(
                    menuBarHiddenModeActive ? "Show RZZ" : "Hide RZZ",
                    systemImage: menuBarHiddenModeActive ? "eye" : "eye.slash"
                )
            }

            Divider()

            Toggle(isOn: $minimizeToMenuBarEnabled) {
                Label("Minimize To Menu Bar", systemImage: "arrow.down.forward.and.arrow.up.backward")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit RZZ", systemImage: "power")
            }
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)
        #endif
    }

    @ViewBuilder
    private var rootWindowContent: some View {
        if let container = dataStoreBootstrap.container {
            ZStack {
                ContentView(
                    isAppLocked: $isAppLocked,
                    appLockPINHash: $appLockPINHash
                )
                .privacySensitive()
                .task {
                    bootstrapAppLockPINHash()
                }

                if isPrivacyShieldVisible {
                    AppPrivacyShieldView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                guard !hasShownDataStoreWarning else { return }
                hasShownDataStoreWarning = true
                #if os(macOS)
                menuBarHiddenModeActive = false
                NSApplication.shared.setActivationPolicy(.regular)
                configureWindowButtonInterceptionIfNeeded()
                configureMainWindowRestorationIfNeeded()
                #endif
                if let warning = dataStoreBootstrap.warningMessage, !warning.isEmpty {
                    transferMessage = warning
                }
                if appThemeMode == nil {
                    showThemeOnboarding = true
                }
            }
            .onChange(of: appThemeModeRaw) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || AppThemeMode(rawValue: trimmed) == nil {
                    showThemeOnboarding = true
                } else {
                    showThemeOnboarding = false
                }
            }
            .alert("Storage Warning", isPresented: Binding(get: {
                transferMessage != nil
            }, set: { presented in
                if !presented {
                    transferMessage = nil
                }
            })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(transferMessage ?? "")
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { _ in
                guard minimizeToMenuBarEnabled else { return }
                DispatchQueue.main.async {
                    hideToMenuBar()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                configureWindowButtonInterceptionIfNeeded()
                configureMainWindowRestorationIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
                persistMainWindowState(from: notification.object as? NSWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { notification in
                persistMainWindowState(from: notification.object as? NSWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { notification in
                persistMainWindowState(from: notification.object as? NSWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { notification in
                persistMainWindowState(from: notification.object as? NSWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                let main = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) ?? NSApplication.shared.windows.first
                persistMainWindowState(from: main)
            }
            .onReceive(NotificationCenter.default.publisher(for: .rzzRequestHideToMenuBar)) { _ in
                guard minimizeToMenuBarEnabled else { return }
                hideToMenuBar()
            }
            .onChange(of: minimizeToMenuBarEnabled) { _, _ in
                configureWindowButtonInterceptionIfNeeded()
            }
            #endif
            .sheet(isPresented: $showThemeOnboarding) {
                ThemeOnboardingView { selectedMode in
                    appThemeModeRaw = selectedMode.rawValue
                    showThemeOnboarding = false
                }
                .interactiveDismissDisabled(true)
                .rzzPresentationFitted()
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutRZZView()
                .rzzPresentationFitted()
            }
            .sheet(isPresented: $showHelpSheet) {
                HelpRZZView()
                .rzzPresentationFitted()
            }
            .preferredColorScheme(appThemeMode?.colorScheme)
            .modelContainer(container)
        } else {
            DataStoreRecoveryView(message: dataStoreBootstrap.fatalMessage ?? "Unknown storage bootstrap failure.")
        }
    }

    private var appThemeMode: AppThemeMode? {
        let trimmed = appThemeModeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return AppThemeMode(rawValue: trimmed)
    }

    private func bootstrapAppLockPINHash() {
        let migration = AppLockCredentialStore.migrateLegacyPINHashIfNeeded(legacyPINHash: &legacyAppLockPINHash)
        switch migration {
        case .clearedWithoutMigration:
            appLockEnabled = false
            appLockPINHash = ""
            isAppLocked = false
            shouldLockOnNextActive = false
        case .notNeeded, .migrated:
            appLockPINHash = AppLockCredentialStore.readPINHash()
            if appLockPINHash.isEmpty {
                appLockEnabled = false
                isAppLocked = false
                shouldLockOnNextActive = false
            }
        }
    }

    #if os(macOS)
    private func hideToMenuBar() {
        menuBarHiddenModeActive = true
        NSApplication.shared.setActivationPolicy(.accessory)
        for window in NSApplication.shared.windows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderOut(nil)
        }
        NSApplication.shared.deactivate()
    }

    private func showFromMenuBar() {
        menuBarHiddenModeActive = false
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let visibleWindow = NSApplication.shared.windows.first(where: { $0.canBecomeKey }) {
            visibleWindow.makeKeyAndOrderFront(nil)
        } else {
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func configureWindowButtonInterceptionIfNeeded() {
        let interceptor = WindowButtonInterceptor.shared
        for window in NSApplication.shared.windows {
            if let closeButton = window.standardWindowButton(.closeButton) {
                if minimizeToMenuBarEnabled {
                    closeButton.target = interceptor
                    closeButton.action = #selector(WindowButtonInterceptor.handleHideButton(_:))
                } else {
                    closeButton.target = nil
                    closeButton.action = nil
                }
            }

            guard let miniaturizeButton = window.standardWindowButton(.miniaturizeButton) else { continue }
            if minimizeToMenuBarEnabled {
                miniaturizeButton.target = interceptor
                miniaturizeButton.action = #selector(WindowButtonInterceptor.handleHideButton(_:))
            } else {
                miniaturizeButton.target = nil
                miniaturizeButton.action = nil
            }
        }
    }

    private func configureMainWindowRestorationIfNeeded() {
        guard let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) ?? NSApplication.shared.windows.first else {
            return
        }

        let autosaveName = "RZZMainWindowFrame"
        if window.frameAutosaveName != autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }

        guard !didApplyMainWindowState else { return }
        didApplyMainWindowState = true

        DispatchQueue.main.async {
            guard !window.styleMask.contains(.fullScreen) else { return }

            if !self.mainWindowZoomed, self.mainWindowFrameSaved {
                let desiredFrame = NSRect(
                    x: self.mainWindowOriginX,
                    y: self.mainWindowOriginY,
                    width: max(self.mainWindowWidth, 740),
                    height: max(self.mainWindowHeight, 520)
                )
                let clampedFrame = self.clampWindowFrame(desiredFrame, for: window)
                window.setFrame(clampedFrame, display: true)
            }

            if self.mainWindowZoomed != window.isZoomed {
                window.zoom(nil)
            }
        }
    }

    private func persistMainWindowState(from window: NSWindow?) {
        guard let window else { return }
        guard window.canBecomeMain else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        mainWindowZoomed = window.isZoomed

        guard !window.isZoomed else { return }
        let frame = window.frame
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 200, frame.height > 200 else { return }
        mainWindowOriginX = frame.origin.x
        mainWindowOriginY = frame.origin.y
        mainWindowWidth = frame.size.width
        mainWindowHeight = frame.size.height
        mainWindowFrameSaved = true
    }

    private func clampWindowFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame

        var width = min(max(frame.width, 740), screenFrame.width)
        var height = min(max(frame.height, 520), screenFrame.height)
        var x = frame.origin.x
        var y = frame.origin.y

        if x < screenFrame.minX { x = screenFrame.minX }
        if y < screenFrame.minY { y = screenFrame.minY }
        if x + width > screenFrame.maxX { x = max(screenFrame.minX, screenFrame.maxX - width) }
        if y + height > screenFrame.maxY { y = max(screenFrame.minY, screenFrame.maxY - height) }

        if width > screenFrame.width { width = screenFrame.width }
        if height > screenFrame.height { height = screenFrame.height }

        return NSRect(x: x, y: y, width: width, height: height)
    }
    #endif
}

private struct ThemeOnboardingView: View {
    let onApply: (AppThemeMode) -> Void

    @State private var selectedMode: AppThemeMode = .system

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Choose Theme")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Select a theme for your reading workspace. You can change it later in Security settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Theme", selection: $selectedMode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button("Apply Theme") {
                    onApply(selectedMode)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520)
        #else
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Appearance", selection: $selectedMode) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("You can change this later in Security settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose Theme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(selectedMode)
                    }
                }
            }
        }
        #endif
    }
}

private enum RZZAppMetadata {
    static var shortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "1.0"
    }

    static var buildVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "1"
    }

    static var displayVersion: String {
        "Version \(shortVersion) (\(buildVersion))"
    }
}

private struct AboutRZZView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("About RZZ")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 12) {
                appIconView

                Text("RZZ")
                    .font(.title3.weight(.semibold))
                Text(RZZAppMetadata.displayVersion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Lightweight RSS reader for macOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420)
    }

    @ViewBuilder
    private var appIconView: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        #else
        if let icon = UIImage(named: "AppIcon") {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: "newspaper")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        #endif
    }
}

private struct HelpRZZView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RZZ Help")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Start")
                        .font(.subheadline.weight(.semibold))
                    Text("1. Click + to add feed URL.\n2. Click Refresh to fetch new articles.\n3. Use star/tag/filter to organize reading.\n4. Open Settings (gear) for lock/theme/security options.")
                        .font(.callout)

                    Divider()

                    Text("Need More Help?")
                        .font(.subheadline.weight(.semibold))
                    Text("Use the Issue Tracker to report bugs or request features.")
                        .font(.callout)

                    Button {
                        #if os(macOS)
                        if let url = URL(string: "https://github.com/RyanChiu/rzz-apple/issues") {
                            NSWorkspace.shared.open(url)
                        }
                        #endif
                    } label: {
                        Label("Open Issue Tracker", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 360)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

#if os(macOS)
private extension Notification.Name {
    static let rzzRequestHideToMenuBar = Notification.Name("rzzRequestHideToMenuBar")
}

private final class WindowButtonInterceptor: NSObject {
    static let shared = WindowButtonInterceptor()

    @objc func handleHideButton(_ sender: Any?) {
        NotificationCenter.default.post(name: .rzzRequestHideToMenuBar, object: sender)
    }
}
#endif

private struct DataStoreBootstrap {
    let container: ModelContainer?
    let warningMessage: String?
    let fatalMessage: String?

    static func bootstrap() -> DataStoreBootstrap {
        let schema = Schema([
            Feed.self,
            Article.self,
            Tag.self,
            ProxyProfile.self,
        ])

        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [persistent])
            return DataStoreBootstrap(container: container, warningMessage: nil, fatalMessage: nil)
        } catch let persistentError {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: schema, configurations: [fallback])
                let warning = """
                RZZ could not open the local data store and started in temporary memory-only mode. \
                Your changes may not persist after app restart. Error: \(persistentError.localizedDescription)
                """
                return DataStoreBootstrap(container: container, warningMessage: warning, fatalMessage: nil)
            } catch let fallbackError {
                let fatalMessage = """
                RZZ could not initialize any storage mode.

                Persistent mode error:
                \(persistentError.localizedDescription)

                Safe mode (in-memory) error:
                \(fallbackError.localizedDescription)
                """
                return DataStoreBootstrap(container: nil, warningMessage: nil, fatalMessage: fatalMessage)
            }
        }
    }
}

private struct AppPrivacyShieldView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.18, blue: 0.30), Color(red: 0.05, green: 0.30, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("RZZ")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                Text("Protected")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .allowsHitTesting(true)
    }
}

private struct DataStoreRecoveryView: View {
    let message: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.12, blue: 0.14), Color(red: 0.06, green: 0.09, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Label("Storage Recovery Needed", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("RZZ cannot start the data store safely right now. You can copy the diagnostics below, restart the app, and restore data from backup if needed.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))

                ScrollView {
                    Text(message)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(minHeight: 160, maxHeight: 260)

                HStack {
                    Button {
                        copyToClipboard(message)
                    } label: {
                        Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    #if os(macOS)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    #endif
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(18)
        }
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
