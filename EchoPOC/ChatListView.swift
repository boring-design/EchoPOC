import SwiftUI

struct ChatListView: View {
    @ObservedObject var telegramService: TelegramService
    @State private var isRefreshing = false

    var body: some View {
        List {
            if telegramService.chats.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Chats",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Pull to refresh or wait for chats to load.")
                    )
                }
            }

            Section("Select chats to monitor") {
                ForEach(telegramService.chats) { chat in
                    chatRow(chat: chat)
                }
            }

            if !monitoredChats.isEmpty {
                Section("Monitoring \(monitoredChats.count) chat(s)") {
                    ForEach(monitoredChats) { chat in
                        Label(chat.title, systemImage: "speaker.wave.2.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .refreshable {
            try? await telegramService.loadChats()
        }
    }

    private var monitoredChats: [TelegramChat] {
        telegramService.chats.filter { telegramService.monitoredChatIds.contains($0.id) }
    }

    private func chatRow(chat: TelegramChat) -> some View {
        Button {
            telegramService.toggleMonitored(chatId: chat.id)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(chat.title)
                        .foregroundStyle(.primary)
                }

                Spacer()

                if telegramService.monitoredChatIds.contains(chat.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
