import SwiftUI
import CryptoKit
import Combine
import CommonCrypto
import Security

enum AppLockPINMigrationResult {
    case notNeeded
    case migrated
    case clearedWithoutMigration
}

enum AppLockCredentialStore {
    private static let account = "app-lock.pin-hash"

    static func readPINHash() -> String {
        SecureSecretStore.readPassword(forAccount: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @discardableResult
    static func savePINHash(_ pinHash: String) -> Bool {
        let trimmed = pinHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SecureSecretStore.deletePassword(forAccount: account)
            return true
        }
        return SecureSecretStore.savePassword(trimmed, forAccount: account)
    }

    static func migrateLegacyPINHashIfNeeded(legacyPINHash: inout String) -> AppLockPINMigrationResult {
        let legacy = legacyPINHash.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { legacyPINHash = "" }
        guard !legacy.isEmpty else { return .notNeeded }

        if !readPINHash().isEmpty {
            return .notNeeded
        }

        guard savePINHash(legacy) else {
            return .clearedWithoutMigration
        }
        return .migrated
    }
}

enum AppLockSecurity {
    private static let pattern = "^[A-Za-z0-9]{4,6}$"
    private static let legacyPrefix = "v1:"
    private static let pbkdf2Prefix = "v2"
    private static let pbkdf2Rounds = 200_000
    private static let pbkdf2SaltByteCount = 16
    private static let pbkdf2KeyByteCount = 32

    static func isValidPIN(_ pin: String) -> Bool {
        pin.range(of: pattern, options: .regularExpression) != nil
    }

    static func hashPIN(_ pin: String) -> String? {
        makePBKDF2Hash(pin, rounds: pbkdf2Rounds)
    }

    static func verifyPINWithUpgrade(_ pin: String, storedHash: String) -> (isValid: Bool, upgradedHash: String?) {
        let normalizedStoredHash = storedHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStoredHash.isEmpty else { return (false, nil) }

        if normalizedStoredHash.hasPrefix(legacyPrefix) {
            let valid = hashLegacyPIN(pin) == normalizedStoredHash
            let upgradedHash = valid ? makePBKDF2Hash(pin, rounds: pbkdf2Rounds) : nil
            return (valid, upgradedHash)
        }

        guard let parsed = parsePBKDF2Hash(normalizedStoredHash),
              let derivedKey = derivePBKDF2Key(pin: pin, salt: parsed.salt, rounds: parsed.rounds, keyByteCount: parsed.key.count)
        else {
            return (false, nil)
        }

        let valid = constantTimeEquals(derivedKey, parsed.key)
        guard valid else { return (false, nil) }

        let needsUpgrade = parsed.rounds < pbkdf2Rounds
        let upgradedHash = needsUpgrade ? makePBKDF2Hash(pin, rounds: pbkdf2Rounds) : nil
        return (true, upgradedHash)
    }

    static func verifyPIN(_ pin: String, storedHash: String) -> Bool {
        verifyPINWithUpgrade(pin, storedHash: storedHash).isValid
    }

    private static func hashLegacyPIN(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(pin.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(legacyPrefix)\(hex)"
    }

    private static func makePBKDF2Hash(_ pin: String, rounds: Int) -> String? {
        guard let salt = makeRandomSalt(byteCount: pbkdf2SaltByteCount),
              let key = derivePBKDF2Key(pin: pin, salt: salt, rounds: rounds, keyByteCount: pbkdf2KeyByteCount)
        else {
            return nil
        }

        return "\(pbkdf2Prefix)$\(rounds)$\(salt.base64EncodedString())$\(key.base64EncodedString())"
    }

    private static func parsePBKDF2Hash(_ hash: String) -> (rounds: Int, salt: Data, key: Data)? {
        let parts = hash.split(separator: "$", omittingEmptySubsequences: false)
        guard parts.count == 4,
              String(parts[0]) == pbkdf2Prefix,
              let rounds = Int(parts[1]),
              rounds > 0,
              rounds <= 1_000_000,
              let salt = Data(base64Encoded: String(parts[2])),
              let key = Data(base64Encoded: String(parts[3])),
              !salt.isEmpty,
              !key.isEmpty
        else {
            return nil
        }
        return (rounds, salt, key)
    }

    private static func derivePBKDF2Key(pin: String, salt: Data, rounds: Int, keyByteCount: Int) -> Data? {
        guard let passwordData = pin.data(using: .utf8), !passwordData.isEmpty else { return nil }
        var keyData = Data(count: keyByteCount)
        let status: Int32 = keyData.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return keyData
    }

    private static func makeRandomSalt(byteCount: Int) -> Data? {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
        }
        guard status == errSecSuccess else { return nil }
        return data
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for index in lhs.indices {
            diff |= lhs[index] ^ rhs[index]
        }
        return diff == 0
    }
}

enum AppLockLockoutStore {
    private static let failedAttemptsKey = "app_lock_failed_attempts"
    private static let lockoutUntilEpochKey = "app_lock_lockout_until_epoch"

    static func loadState() -> (failedAttempts: Int, lockoutUntil: Date?) {
        let defaults = UserDefaults.standard
        let attempts = max(defaults.integer(forKey: failedAttemptsKey), 0)
        let epoch = defaults.double(forKey: lockoutUntilEpochKey)
        let lockoutDate = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
        return (attempts, lockoutDate)
    }

    static func saveState(failedAttempts: Int, lockoutUntil: Date?) {
        let defaults = UserDefaults.standard
        defaults.set(max(failedAttempts, 0), forKey: failedAttemptsKey)
        if let lockoutUntil {
            defaults.set(lockoutUntil.timeIntervalSince1970, forKey: lockoutUntilEpochKey)
        } else {
            defaults.removeObject(forKey: lockoutUntilEpochKey)
        }
    }

    static func clearState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: failedAttemptsKey)
        defaults.removeObject(forKey: lockoutUntilEpochKey)
    }
}

struct AppLockSettingsView: View {
    @Binding var isEnabled: Bool
    @Binding var pinHash: String

    @Environment(\.dismiss) private var dismiss

    @State private var draftIsEnabled: Bool
    @State private var draftPINHash: String
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var message: String?
    @State private var isErrorMessage = false

    init(isEnabled: Binding<Bool>, pinHash: Binding<String>) {
        _isEnabled = isEnabled
        _pinHash = pinHash
        _draftIsEnabled = State(initialValue: isEnabled.wrappedValue)
        _draftPINHash = State(initialValue: pinHash.wrappedValue)
    }

    private var hasExistingPIN: Bool {
        !draftPINHash.isEmpty
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Security")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
            settingsForm
                .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Done") {
                    applyDraftAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560)
        #else
        NavigationStack {
            settingsForm
                .navigationTitle("Security")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            applyDraftAndDismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 430, minHeight: 360)
        #endif
    }

    private var settingsForm: some View {
        Form {
            Section("App Lock") {
                Toggle("Enable lock when re-entering app", isOn: $draftIsEnabled)
                Text("When enabled, re-entering RZZ requires a 4-6 character PIN (letters or digits).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(hasExistingPIN ? "Change PIN" : "Create PIN") {
                if hasExistingPIN {
                    SecureField("Current PIN", text: $currentPIN)
                        .textContentType(.password)
                }

                SecureField("New PIN (4-6 chars)", text: $newPIN)
                    .textContentType(.password)
                SecureField("Confirm New PIN", text: $confirmPIN)
                    .textContentType(.password)

                Button(hasExistingPIN ? "Update PIN" : "Save PIN") {
                    savePIN()
                }
                .disabled(!canSavePIN)
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(isErrorMessage ? .red : .secondary)
                }
            }
        }
    }

    private func applyDraftAndDismiss() {
        guard !draftIsEnabled || !draftPINHash.isEmpty else {
            setMessage("Create a PIN before enabling app lock.", error: true)
            return
        }

        if draftPINHash != pinHash {
            guard AppLockCredentialStore.savePINHash(draftPINHash) else {
                setMessage("Could not save PIN securely. Please check Keychain and try again.", error: true)
                return
            }
            pinHash = draftPINHash
            AppLockLockoutStore.clearState()
        }
        isEnabled = draftIsEnabled
        if !draftIsEnabled {
            AppLockLockoutStore.clearState()
        }
        dismiss()
    }

    private var canSavePIN: Bool {
        if hasExistingPIN && currentPIN.isEmpty {
            return false
        }
        return !newPIN.isEmpty && !confirmPIN.isEmpty
    }

    private func savePIN() {
        guard AppLockSecurity.isValidPIN(newPIN) else {
            setMessage("PIN must be 4-6 letters or digits.", error: true)
            return
        }
        guard newPIN == confirmPIN else {
            setMessage("New PIN and confirmation do not match.", error: true)
            return
        }
        if hasExistingPIN && !AppLockSecurity.verifyPIN(currentPIN, storedHash: draftPINHash) {
            setMessage("Current PIN is incorrect.", error: true)
            return
        }

        guard let hashedPIN = AppLockSecurity.hashPIN(newPIN) else {
            setMessage("Could not generate a secure PIN hash. Please try again.", error: true)
            return
        }
        draftPINHash = hashedPIN
        setMessage("PIN updated. Click Done to apply.", error: false)
        currentPIN = ""
        newPIN = ""
        confirmPIN = ""
    }

    private func setMessage(_ value: String, error: Bool) {
        message = value
        isErrorMessage = error
    }
}

struct AppLockScreenView: View {
    let onUnlock: (String) -> Bool

    @State private var pinInput = ""
    @State private var errorMessage: String?
    @State private var failedAttempts = 0
    @State private var lockoutUntil: Date?
    @State private var now = Date()

    // Use a higher-frequency ticker with low tolerance so lockout countdown feels stable.
    private let lockoutTicker = Timer.publish(every: 0.2, tolerance: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.17, blue: 0.30), Color(red: 0.03, green: 0.36, blue: 0.45), Color(red: 0.10, green: 0.57, blue: 0.67)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            waveBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("RZZ")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.96), .cyan.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Unlock")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))

                    SecureField("Enter PIN", text: $pinInput)
                        .textContentType(.password)
                        .onSubmit(tryUnlock)
                        .disabled(isLockedOut)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    if let message = displayedMessage {
                        Text(message)
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.95))
                    }

                    Button("Unlock", action: tryUnlock)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(pinInput.isEmpty || isLockedOut)
                }
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 360)
            }
            .padding(24)
        }
        .onReceive(lockoutTicker) { tick in
            now = tick
            if let lockoutUntil, tick >= lockoutUntil {
                self.lockoutUntil = nil
                persistLockoutState()
            }
        }
        .onAppear {
            let persisted = AppLockLockoutStore.loadState()
            failedAttempts = persisted.failedAttempts
            now = Date()
            if let persistedLockout = persisted.lockoutUntil, persistedLockout > now {
                lockoutUntil = persistedLockout
            } else {
                lockoutUntil = nil
                persistLockoutState()
            }
        }
    }

    private var waveBackground: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 520, height: 520)
                .offset(x: -240, y: 220)
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 420, height: 420)
                .offset(x: 240, y: 160)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 300, height: 300)
                .offset(x: 140, y: -220)
        }
        .blur(radius: 2)
    }

    private var isLockedOut: Bool {
        guard let lockoutUntil else { return false }
        return lockoutUntil > now
    }

    private var displayedMessage: String? {
        if isLockedOut {
            return "Too many attempts. Try again in \(lockoutRemainingSeconds)s."
        }
        return errorMessage
    }

    private func tryUnlock() {
        if isLockedOut {
            return
        }

        guard onUnlock(pinInput) else {
            failedAttempts += 1
            if failedAttempts >= 3 {
                let power = min(failedAttempts - 3, 5)
                let cooldownSeconds = Int(pow(2.0, Double(power + 1)))
                now = Date()
                lockoutUntil = now.addingTimeInterval(Double(cooldownSeconds))
                errorMessage = nil
            } else {
                errorMessage = "Invalid PIN."
            }
            persistLockoutState()
            return
        }
        failedAttempts = 0
        lockoutUntil = nil
        errorMessage = nil
        pinInput = ""
        AppLockLockoutStore.clearState()
    }

    private var lockoutRemainingSeconds: Int {
        guard let lockoutUntil else { return 0 }
        return max(1, Int(ceil(lockoutUntil.timeIntervalSince(now))))
    }

    private func persistLockoutState() {
        AppLockLockoutStore.saveState(failedAttempts: failedAttempts, lockoutUntil: lockoutUntil)
    }
}
