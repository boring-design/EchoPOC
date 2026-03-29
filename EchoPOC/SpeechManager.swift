import AVFoundation

enum SpeechStatus: String {
    case idle = "Idle"
    case listening = "Listening..."
    case processing = "Processing..."
    case speaking = "Speaking..."
}

@MainActor
final class SpeechManager: NSObject, ObservableObject {
    private static let selectedVoiceKey = "selectedEdgeTTSVoice"
    private static let ttsRateKey = "edgeTTSRate"

    @Published var transcribedText: String = ""
    @Published var status: SpeechStatus = .idle
    @Published var isFinalized: Bool = false
    @Published var selectedVoiceId: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceId, forKey: Self.selectedVoiceKey)
        }
    }
    @Published var ttsRate: String {
        didSet {
            UserDefaults.standard.set(ttsRate, forKey: Self.ttsRateKey)
        }
    }

    private let cloudflareService = CloudflareAIService()
    private let edgeTTS = EdgeTTSService()
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var isRecording = false

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("echo_recording.wav")
    }

    override init() {
        selectedVoiceId = UserDefaults.standard.string(forKey: Self.selectedVoiceKey)
            ?? EdgeTTSVoice.defaultVoice.id
        ttsRate = UserDefaults.standard.string(forKey: Self.ttsRateKey)
            ?? "+50%"
        super.init()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Recording

    func startListening() {
        guard !isRecording else { return }

        transcribedText = ""
        status = .listening
        isFinalized = false
        isRecording = true

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
        } catch {
            print("Failed to start recording: \(error)")
            status = .idle
            isRecording = false
        }
    }

    func stopListening() {
        guard isRecording else { return }
        isRecording = false

        audioRecorder?.stop()
        audioRecorder = nil

        status = .processing

        Task {
            await transcribeRecordedAudio()
            isFinalized = true
            status = .idle
        }
    }

    // MARK: - Transcription (Cloudflare Whisper)

    private func transcribeRecordedAudio() async {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            print("Recording file not found")
            return
        }

        do {
            let audioData = try Data(contentsOf: recordingURL)
            guard audioData.count > 1000 else {
                print("Audio too short, skipping transcription")
                return
            }

            let result = try await cloudflareService.transcribe(audioData: audioData)
            transcribedText = result.text
            print("[STT] Transcription: \(result.text) (lang: \(result.language ?? "unknown"))")
        } catch {
            print("[STT] Transcription error: \(error)")
        }

        try? FileManager.default.removeItem(at: recordingURL)
    }

    // MARK: - TTS (Edge TTS)

    func speakAnnouncement(_ text: String) {
        guard !text.isEmpty else { return }

        status = .speaking

        Task {
            do {
                let audioData = try await edgeTTS.synthesize(
                    text: text,
                    voice: selectedVoiceId,
                    rate: ttsRate
                )
                print("[TTS] Received \(audioData.count) bytes of audio")

                try await playAudio(data: audioData)
            } catch {
                print("[TTS] Error: \(error)")
                status = .idle
            }
        }
    }

    private func playAudio(data: Data) async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)

        // Edge TTS returns MP3 audio
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo_tts_\(UUID().uuidString).mp3")
        try data.write(to: tempURL)

        let player = try AVAudioPlayer(contentsOf: tempURL)
        self.audioPlayer = player
        player.delegate = self
        player.prepareToPlay()
        player.volume = 1.0

        print("[Playback] Duration: \(player.duration)s")
        player.play()

        while player.isPlaying {
            try await Task.sleep(for: .milliseconds(100))
        }

        try? FileManager.default.removeItem(at: tempURL)
        status = .idle
    }
}

// MARK: - AVAudioPlayerDelegate

extension SpeechManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.status = .idle
        }
    }
}
