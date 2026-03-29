import SwiftUI

@main
struct EchoPOCApp: App {
    @StateObject private var telegramService = TelegramService.shared
    @StateObject private var speechManager = SpeechManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if telegramService.authState == .ready {
                    mainTabView
                } else {
                    TelegramAuthView(telegramService: telegramService)
                }
            }
            .onAppear {
                telegramService.start()
            }
        }
    }

    private var mainTabView: some View {
        TabView {
            NavigationStack {
                WalkieTalkieView(
                    telegramService: telegramService,
                    speechManager: speechManager
                )
                .navigationTitle("Walkie-Talkie")
            }
            .tabItem {
                Label("Talk", systemImage: "mic.fill")
            }

            NavigationStack {
                ChatListView(telegramService: telegramService)
            }
            .tabItem {
                Label("Chats", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationStack {
                VoiceSettingsView(speechManager: speechManager)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
