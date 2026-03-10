import SwiftUI
import SwiftData

@main
struct RZZApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app_lock_enabled") private var appLockEnabled = false
    @AppStorage("app_lock_pin_hash") private var legacyAppLockPINHash = ""

    private let dataStoreBootstrap = DataStoreBootstrap.bootstrap()

    @State private var appLockPINHash = ""
    @State private var isAppLocked = false
    @State private var shouldLockOnNextActive = false
    @State private var isPrivacyShieldVisible = false
    @State private var hasShownDataStoreWarning = false

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
            .onAppear {
                guard !hasShownDataStoreWarning else { return }
                hasShownDataStoreWarning = true
                if let warning = dataStoreBootstrap.warningMessage, !warning.isEmpty {
                    transferMessage = warning
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
        }
        .modelContainer(dataStoreBootstrap.container)
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

    @State private var transferMessage: String?

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

private struct DataStoreBootstrap {
    let container: ModelContainer
    let warningMessage: String?

    static func bootstrap() -> DataStoreBootstrap {
        let schema = Schema([
            Feed.self,
            Article.self,
            Tag.self,
        ])

        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [persistent])
            return DataStoreBootstrap(container: container, warningMessage: nil)
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
                let warning = """
                RZZ could not open the local data store and started in temporary memory-only mode. \
                Your changes may not persist after app restart. Error: \(error.localizedDescription)
                """
                return DataStoreBootstrap(container: container, warningMessage: warning)
            }
            fatalError("Could not create ModelContainer: \(error)")
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
