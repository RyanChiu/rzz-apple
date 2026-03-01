import SwiftUI
import CryptoKit

enum AppLockSecurity {
    private static let pattern = "^[A-Za-z0-9]{4,6}$"

    static func isValidPIN(_ pin: String) -> Bool {
        pin.range(of: pattern, options: .regularExpression) != nil
    }

    static func hashPIN(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(pin.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "v1:\(hex)"
    }

    static func verifyPIN(_ pin: String, storedHash: String) -> Bool {
        hashPIN(pin) == storedHash
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
        isEnabled = draftIsEnabled
        pinHash = draftPINHash
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

        draftPINHash = AppLockSecurity.hashPIN(newPIN)
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
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.95))
                    }

                    Button("Unlock", action: tryUnlock)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(pinInput.isEmpty)
                }
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 360)
            }
            .padding(24)
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

    private func tryUnlock() {
        guard onUnlock(pinInput) else {
            errorMessage = "Invalid PIN."
            return
        }
        errorMessage = nil
        pinInput = ""
    }
}
