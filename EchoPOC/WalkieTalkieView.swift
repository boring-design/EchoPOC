import SwiftUI

struct WalkieTalkieView: View {
    @ObservedObject var telegramService: TelegramService
    @ObservedObject var speechManager: SpeechManager

    @State private var selectedChatId: Int64?
    @State private var isPressed = false
    @State private var permissionsGranted = false
    @State private var lastAnnouncedMessage: String = ""

    var body: some View {
        VStack(spacing: 20) {
            if !CloudflareConfig.isConfigured {
                ContentUnavailableView(
                    "API Not Configured",
                    systemImage: "key.fill",
                    description: Text("Go to Settings tab to enter your Cloudflare Account ID and API Token.")
                )
            } else if monitoredChats.isEmpty {
                ContentUnavailableView(
                    "No Monitored Chats",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Go to Chats tab and select chats to monitor.")
                )
            } else {
                chatPicker

                statusBanner

                messageDisplay

                Spacer()

                pushToTalkButton

                Spacer()
            }
        }
        .padding()
        .task {
            permissionsGranted = await speechManager.requestPermissions()
            setupMessageListener()
        }
    }

    // MARK: - Subviews

    private var chatPicker: some View {
        Picker("Send to", selection: $selectedChatId) {
            ForEach(monitoredChats) { chat in
                Text(chat.title).tag(Optional(chat.id))
            }
        }
        .pickerStyle(.segmented)
        .onAppear {
            if selectedChatId == nil {
                selectedChatId = monitoredChats.first?.id
            }
        }
    }

    private var statusBanner: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(speechManager.status.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .animation(.easeInOut, value: speechManager.status)
    }

    private var messageDisplay: some View {
        VStack(spacing: 8) {
            if !lastAnnouncedMessage.isEmpty {
                Text(lastAnnouncedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ScrollView {
                Text(
                    speechManager.transcribedText.isEmpty
                    ? "Hold the button and speak"
                    : speechManager.transcribedText
                )
                .font(.title3)
                .foregroundStyle(speechManager.transcribedText.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
            .frame(maxHeight: 150)
        }
    }

    private var pushToTalkButton: some View {
        Circle()
            .fill(buttonColor)
            .frame(width: 140, height: 140)
            .overlay {
                Image(systemName: isPressed ? "mic.fill" : "mic")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPressed ? 1.15 : 1.0)
            .shadow(color: buttonColor.opacity(0.5), radius: isPressed ? 20 : 8)
            .animation(.spring(response: 0.3), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed, permissionsGranted else { return }
                        isPressed = true
                        speechManager.startListening()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        stopAndSend()
                    }
            )
            .disabled(!permissionsGranted || speechManager.status == .speaking || speechManager.status == .processing || selectedChatId == nil)
            .opacity(permissionsGranted && selectedChatId != nil ? 1.0 : 0.4)
    }

    // MARK: - Helpers

    private var monitoredChats: [TelegramChat] {
        telegramService.chats.filter { telegramService.monitoredChatIds.contains($0.id) }
    }

    private var statusColor: Color {
        switch speechManager.status {
        case .idle: .secondary
        case .listening: .green
        case .processing: .yellow
        case .speaking: .blue
        }
    }

    private var buttonColor: Color {
        switch speechManager.status {
        case .idle: .blue
        case .listening: .red
        case .processing: .orange
        case .speaking: .gray
        }
    }

    private func stopAndSend() {
        speechManager.stopListening()
        sendWhenFinalized()
    }

    private func sendWhenFinalized() {
        Task {
            // Wait for the recognizer to finalize (up to 5 seconds)
            for _ in 0..<50 {
                if speechManager.isFinalized { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            let text = speechManager.transcribedText
            guard !text.isEmpty, let chatId = selectedChatId else { return }
            try? await telegramService.sendTextMessage(chatId: chatId, text: text)
        }
    }

    private func setupMessageListener() {
        telegramService.onNewMessage = { [speechManager] message in
            Task { @MainActor in
                lastAnnouncedMessage = "[\(message.chatTitle)] \(message.text)"
                speechManager.speakAnnouncement(message.text)
            }
        }
    }
}
