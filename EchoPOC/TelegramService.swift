import Foundation
import TDLibKit

enum TelegramAuthState: Equatable {
    case initializing
    case waitingPhoneNumber
    case waitingCode
    case waitingPassword(hint: String)
    case ready
    case closed
}

struct TelegramChat: Identifiable, Equatable {
    let id: Int64
    let title: String
}

struct TelegramMessage: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let chatTitle: String
    let senderName: String
    let text: String
    let date: Foundation.Date
    let isOutgoing: Bool
}

@MainActor
final class TelegramService: ObservableObject {
    static let shared = TelegramService()

    @Published var authState: TelegramAuthState = .initializing
    @Published var chats: [TelegramChat] = []
    @Published var monitoredChatIds: Set<Int64> = [] {
        didSet {
            persistMonitoredChatIds()
        }
    }

    var onNewMessage: ((TelegramMessage) -> Void)?

    private let clientManager = TDLibClientManager()
    private var client: TDLibClient?
    private let decoder = JSONDecoder()

    private static let monitoredChatIdsKey = "monitoredTelegramChatIds"

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        loadMonitoredChatIds()
    }

    // MARK: - Lifecycle

    func start() {
        guard client == nil else { return }
        client = clientManager.createClient { [weak self] data, client in
            self?.handleUpdate(data: data, client: client)
        }
    }

    // MARK: - Auth Actions

    func sendPhoneNumber(_ phone: String) async throws {
        guard let client else { return }
        try await client.setAuthenticationPhoneNumber(
            phoneNumber: phone,
            settings: nil
        )
    }

    func sendAuthCode(_ code: String) async throws {
        guard let client else { return }
        try await client.checkAuthenticationCode(code: code)
    }

    func sendPassword(_ password: String) async throws {
        guard let client else { return }
        try await client.checkAuthenticationPassword(password: password)
    }

    // MARK: - Chat Operations

    func loadChats() async throws {
        guard let client else { return }
        try await client.loadChats(chatList: .chatListMain, limit: 20)
        let result = try await client.getChats(chatList: .chatListMain, limit: 20)
        var loaded: [TelegramChat] = []
        for chatId in result.chatIds {
            let chat = try await client.getChat(chatId: chatId)
            loaded.append(TelegramChat(id: chat.id, title: chat.title))
        }
        await MainActor.run {
            self.chats = loaded
        }
    }

    func toggleMonitored(chatId: Int64) {
        if monitoredChatIds.contains(chatId) {
            monitoredChatIds.remove(chatId)
        } else {
            monitoredChatIds.insert(chatId)
        }
    }

    // MARK: - Send Message

    func sendTextMessage(chatId: Int64, text: String) async throws {
        guard let client else { return }
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )
        _ = try await client.sendMessage(
            chatId: chatId,
            inputMessageContent: content,
            options: nil,
            replyMarkup: nil,
            replyTo: nil,
            topicId: nil
        )
    }

    // MARK: - Update Handler (runs on TDLib's serial queue)

    private func handleUpdate(data: Data, client: TDLibClient) {
        guard let update = try? decoder.decode(Update.self, from: data) else {
            return
        }

        Task { @MainActor [weak self] in
            self?.processUpdate(update, client: client)
        }
    }

    private func processUpdate(_ update: Update, client: TDLibClient) {
        switch update {
        case .updateAuthorizationState(let authUpdate):
            handleAuthState(authUpdate.authorizationState, client: client)

        case .updateNewMessage(let msgUpdate):
            handleNewMessage(msgUpdate.message)

        default:
            break
        }
    }

    // MARK: - Auth State Machine

    private func handleAuthState(_ state: AuthorizationState, client: TDLibClient) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            configureTdlib(client: client)

        case .authorizationStateWaitPhoneNumber:
            authState = .waitingPhoneNumber

        case .authorizationStateWaitCode:
            authState = .waitingCode

        case .authorizationStateWaitPassword(let info):
            authState = .waitingPassword(hint: info.passwordHint)

        case .authorizationStateReady:
            authState = .ready
            Task {
                try? await loadChats()
            }

        case .authorizationStateClosed:
            authState = .closed

        default:
            break
        }
    }

    private func configureTdlib(client: TDLibClient) {
        let dbPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tdlib")
            .path

        Task {
            try? await client.setTdlibParameters(
                apiHash: TelegramConfig.apiHash,
                apiId: TelegramConfig.apiId,
                applicationVersion: TelegramConfig.appVersion,
                databaseDirectory: dbPath,
                databaseEncryptionKey: Data(),
                deviceModel: TelegramConfig.deviceModel,
                filesDirectory: nil,
                systemLanguageCode: TelegramConfig.languageCode,
                systemVersion: nil,
                useChatInfoDatabase: true,
                useFileDatabase: false,
                useMessageDatabase: false,
                useSecretChats: false,
                useTestDc: false
            )
        }
    }

    // MARK: - Message Handler

    private func handleNewMessage(_ message: Message) {
        guard monitoredChatIds.contains(message.chatId) else { return }
        guard !message.isOutgoing else { return }

        guard case .messageText(let textContent) = message.content else {
            return
        }

        let chatTitle = chats.first(where: { $0.id == message.chatId })?.title ?? "Unknown"

        let telegramMessage = TelegramMessage(
            id: message.id,
            chatId: message.chatId,
            chatTitle: chatTitle,
            senderName: chatTitle,
            text: textContent.text.text,
            date: Foundation.Date(timeIntervalSince1970: TimeInterval(message.date)),
            isOutgoing: false
        )

        onNewMessage?(telegramMessage)
    }

    // MARK: - Persistence

    private func persistMonitoredChatIds() {
        let ids = Array(monitoredChatIds)
        UserDefaults.standard.set(ids, forKey: Self.monitoredChatIdsKey)
    }

    private func loadMonitoredChatIds() {
        let ids = UserDefaults.standard.array(forKey: Self.monitoredChatIdsKey) as? [Int64] ?? []
        monitoredChatIds = Set(ids)
    }
}
