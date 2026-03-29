import AVFoundation
import Speech

enum SpeechStatus: String {
    case idle = "Idle"
    case listening = "Listening..."
    case speaking = "Speaking..."
}

struct TTSVoiceOption: Identifiable, Equatable {
    let id: String
    let identifier: String?
    let name: String
    let languageCode: String
    let languageName: String
    let qualityLabel: String
    let isInstalled: Bool

    var subtitle: String {
        [languageName, qualityLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

@MainActor
final class SpeechManager: NSObject, ObservableObject {
    private static let selectedVoiceIdentifierKey = "selectedTTSVoiceIdentifier"

    @Published var transcribedText: String = ""
    @Published var status: SpeechStatus = .idle
    @Published var selectedVoiceIdentifier: String? {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: Self.selectedVoiceIdentifierKey)
        }
    }
    @Published private(set) var availableVoiceRefreshToken = UUID()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))!
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var availableVoicesObserver: NSObjectProtocol?

    override init() {
        selectedVoiceIdentifier = UserDefaults.standard.string(forKey: Self.selectedVoiceIdentifierKey)
        super.init()
        synthesizer.delegate = self
        availableVoicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailableVoices()
            }
        }
    }

    deinit {
        if let availableVoicesObserver {
            NotificationCenter.default.removeObserver(availableVoicesObserver)
        }
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus == .authorized)
            }
        }

        let micAuthorized: Bool
        if #available(iOS 17.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechAuthorized && micAuthorized
    }

    // MARK: - Recording

    func startListening() {
        guard !audioEngine.isRunning else { return }

        transcribedText = ""
        status = .listening

        do {
            try startRecognition()
        } catch {
            print("Failed to start recognition: \(error)")
            status = .idle
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        if !transcribedText.isEmpty {
            speak(transcribedText)
        } else {
            status = .idle
        }
    }

    // MARK: - STT

    private func startRecognition() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = [
            "Echo",
            "Yue",
            "Ava"
        ]
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                Task { @MainActor in
                    if self.status == .listening {
                        self.status = .idle
                    }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - TTS

    private func speak(_ text: String) {
        status = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice(for: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    var ttsVoiceOptions: [TTSVoiceOption] {
        let autoOption = TTSVoiceOption(
            id: "auto",
            identifier: nil,
            name: "Auto",
            languageCode: "",
            languageName: "Follow text language",
            qualityLabel: "",
            isInstalled: true
        )

        let preferredLanguageCodes = ["zh-CN", "zh-Hans", "yue-HK", "zh-HK", "en-US", "en-GB"]
        let currentLocale = Locale.current

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                (supportedTTSLanguageCodes.contains(voice.language) || recommendedVoiceIdentifiers.contains(voice.identifier))
                    && shouldDisplayVoice(voice)
            }
            .sorted { lhs, rhs in
                let lhsRank = preferredLanguageCodes.firstIndex(of: lhs.language) ?? preferredLanguageCodes.count
                let rhsRank = preferredLanguageCodes.firstIndex(of: rhs.language) ?? preferredLanguageCodes.count
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { voice in
                TTSVoiceOption(
                    id: voice.identifier,
                    identifier: voice.identifier,
                    name: voice.name,
                    languageCode: voice.language,
                    languageName: currentLocale.localizedString(forIdentifier: voice.language) ?? voice.language,
                    qualityLabel: qualityLabel(for: voice.quality),
                    isInstalled: true
                )
            }

        return [autoOption] + voices
    }

    var installedChineseVoiceOptions: [TTSVoiceOption] {
        ttsVoiceOptions.filter { $0.identifier != nil && chineseTTSLanguageCodes.contains($0.languageCode) }
    }

    var installedEnglishVoiceOptions: [TTSVoiceOption] {
        ttsVoiceOptions.filter { $0.identifier != nil && englishTTSLanguageCodes.contains($0.languageCode) }
    }

    var downloadableVoiceOptions: [TTSVoiceOption] {
        let currentLocale = Locale.current

        return recommendedDownloadableVoices.compactMap { recommended in
            guard AVSpeechSynthesisVoice(identifier: recommended.identifier) == nil else {
                return nil
            }

            return TTSVoiceOption(
                id: "downloadable-\(recommended.identifier)",
                identifier: recommended.identifier,
                name: recommended.name,
                languageCode: recommended.languageCode,
                languageName: currentLocale.localizedString(forIdentifier: recommended.languageCode) ?? recommended.languageCode,
                qualityLabel: recommended.qualityLabel,
                isInstalled: false
            )
        }
    }

    func selectedVoiceOption(for text: String = "") -> TTSVoiceOption? {
        if let selectedVoiceIdentifier,
           let option = ttsVoiceOptions.first(where: { $0.identifier == selectedVoiceIdentifier }) {
            return option
        }

        let voice = preferredVoice(for: text.isEmpty ? "中文" : text)
        return ttsVoiceOptions.first(where: { $0.identifier == voice?.identifier }) ?? ttsVoiceOptions.first
    }

    private func preferredVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let containsChinese = text.contains(where: \.isChineseCharacter)
        let preferredLanguage = containsChinese ? "zh-CN" : "en-US"

        return AVSpeechSynthesisVoice(language: preferredLanguage)
            ?? AVSpeechSynthesisVoice(language: containsChinese ? "zh-Hans" : "en-US")
            ?? AVSpeechSynthesisVoice()
    }

    private func selectedVoice(for text: String) -> AVSpeechSynthesisVoice? {
        if let selectedVoiceIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            return selectedVoice
        }

        return preferredVoice(for: text)
    }

    private func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:
            return "Premium"
        case .enhanced:
            return "Enhanced"
        default:
            return "Default"
        }
    }

    private func shouldDisplayVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.quality == .premium || voice.quality == .enhanced || isSiriVoice(voice)
    }

    private func isSiriVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.name.localizedCaseInsensitiveContains("siri")
            || voice.identifier.localizedCaseInsensitiveContains(".siri")
    }

    func refreshAvailableVoices() {
        availableVoiceRefreshToken = UUID()
    }

    private let chineseTTSLanguageCodes: Set<String> = ["zh-CN", "zh-Hans", "zh-HK", "yue-HK"]
    private let englishTTSLanguageCodes: Set<String> = ["en-US", "en-GB"]

    private var supportedTTSLanguageCodes: Set<String> {
        chineseTTSLanguageCodes.union(englishTTSLanguageCodes)
    }

    private let recommendedVoiceIdentifiers: Set<String> = [
        "com.apple.voice.premium.zh-CN.Yue",
        "com.apple.voice.premium.en-US.Ava"
    ]

    private let recommendedDownloadableVoices: [RecommendedVoice] = [
        RecommendedVoice(
            identifier: "com.apple.voice.premium.zh-CN.Yue",
            name: "Yue",
            languageCode: "zh-CN",
            qualityLabel: "Premium"
        ),
        RecommendedVoice(
            identifier: "com.apple.voice.premium.en-US.Ava",
            name: "Ava",
            languageCode: "en-US",
            qualityLabel: "Premium"
        )
    ]
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.status = .idle
        }
    }
}

private extension Character {
    var isChineseCharacter: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
                return true
            default:
                return false
            }
        }
    }
}

private struct RecommendedVoice {
    let identifier: String
    let name: String
    let languageCode: String
    let qualityLabel: String
}
