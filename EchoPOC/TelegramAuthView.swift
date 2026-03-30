import SwiftUI

struct TelegramAuthView: View {
    @ObservedObject var telegramService: TelegramService
    @State private var phoneNumber: String = ""
    @State private var authCode: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "paperplane.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Connect to Telegram")
                .font(.title)
                .fontWeight(.bold)

            switch telegramService.authState {
            case .initializing:
                ProgressView("Initializing...")

            case .configurationMissing:
                configurationMissingView

            case .waitingPhoneNumber:
                phoneNumberForm

            case .waitingCode:
                authCodeForm

            case .waitingPassword(let hint):
                passwordForm(hint: hint)

            case .ready, .closed:
                EmptyView()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Forms

    private var configurationMissingView: some View {
        ContentUnavailableView(
            "Telegram Not Configured",
            systemImage: "key.fill",
            description: Text("Set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` in Info.plist before connecting.")
        )
    }

    private var phoneNumberForm: some View {
        VStack(spacing: 16) {
            Text("Enter your phone number")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("+86 12345678901", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)

            submitButton(title: "Send Code") {
                try await telegramService.sendPhoneNumber(phoneNumber)
            }
        }
    }

    private var authCodeForm: some View {
        VStack(spacing: 16) {
            Text("Enter the code sent to your device")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("12345", text: $authCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)

            submitButton(title: "Verify") {
                try await telegramService.sendAuthCode(authCode)
            }
        }
    }

    private func passwordForm(hint: String) -> some View {
        VStack(spacing: 16) {
            Text("Enter your 2FA password")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !hint.isEmpty {
                Text("Hint: \(hint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)

            submitButton(title: "Submit") {
                try await telegramService.sendPassword(password)
            }
        }
    }

    private func submitButton(title: String, action: @escaping () async throws -> Void) -> some View {
        Button {
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await action()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        } label: {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 40)
        .disabled(isLoading)
    }
}
