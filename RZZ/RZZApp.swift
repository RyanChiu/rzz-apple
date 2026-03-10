import SwiftUI
import SwiftData

@main
struct RZZApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("app_lock_pin_hash") private var legacyAppLockPINHash = ""

    @State private var appLockPINHash = ""
    @State private var isAppLocked = false
    @State private var shouldLockOnNextActive = false
    @State private var isPrivacyShieldVisible = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
            Tag.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
                return container
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
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
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
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
