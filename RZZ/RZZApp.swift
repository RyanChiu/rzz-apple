import SwiftUI
import SwiftData

@main
struct RZZApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("app_lock_pin_hash") private var appLockPINHash = ""

    @State private var isAppLocked = false
    @State private var shouldLockOnNextActive = false

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
            ContentView(isAppLocked: $isAppLocked)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard appLockEnabled, !appLockPINHash.isEmpty else { return }

            switch newPhase {
            case .inactive, .background:
                shouldLockOnNextActive = true
            case .active:
                if shouldLockOnNextActive {
                    isAppLocked = true
                }
                shouldLockOnNextActive = false
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
}
