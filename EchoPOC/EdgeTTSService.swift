import Foundation
import CryptoKit

struct EdgeTTSVoice: Identifiable, Equatable {
    let id: String
    let name: String
    let gender: String
    let style: String

    static let allChinese: [EdgeTTSVoice] = [
        EdgeTTSVoice(id: "zh-CN-YunxiNeural", name: "Yunxi", gender: "Male", style: "Lively, Sunshine"),
        EdgeTTSVoice(id: "zh-CN-XiaoxiaoNeural", name: "Xiaoxiao", gender: "Female", style: "Warm"),
        EdgeTTSVoice(id: "zh-CN-XiaoyiNeural", name: "Xiaoyi", gender: "Female", style: "Lively"),
        EdgeTTSVoice(id: "zh-CN-YunjianNeural", name: "Yunjian", gender: "Male", style: "Passion"),
        EdgeTTSVoice(id: "zh-CN-YunxiaNeural", name: "Yunxia", gender: "Male", style: "Cute"),
        EdgeTTSVoice(id: "zh-CN-YunyangNeural", name: "Yunyang", gender: "Male", style: "Professional"),
    ]

    static let defaultVoice = allChinese[0]
}

actor EdgeTTSService {
    private static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let chromiumVersion = "143.0.3650.75"
    private static let chromiumMajor = "143"

    private static var baseWSURL: String {
        "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
    }

    // MARK: - Public API

    func synthesize(
        text: String,
        voice: String = EdgeTTSVoice.defaultVoice.id,
        rate: String = "+50%",
        volume: String = "+0%",
        pitch: String = "+0Hz"
    ) async throws -> Data {
        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let secMsGec = Self.generateSecMsGec()
        let secMsGecVersion = "1-\(Self.chromiumVersion)"

        let urlString = "\(Self.baseWSURL)"
            + "?TrustedClientToken=\(Self.trustedClientToken)"
            + "&ConnectionId=\(connectionId)"
            + "&Sec-MS-GEC=\(secMsGec)"
            + "&Sec-MS-GEC-Version=\(secMsGecVersion)"

        guard let url = URL(string: urlString) else {
            throw EdgeTTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(Self.chromiumMajor).0.0.0 Safari/537.36 Edg/\(Self.chromiumMajor).0.0.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let muid = Self.generateMUID()
        request.setValue("muid=\(muid);", forHTTPHeaderField: "Cookie")

        let webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket.resume()

        do {
            // Step 1: Send speech config
            let configMessage = Self.buildConfigMessage()
            try await webSocket.send(.string(configMessage))

            // Step 2: Send SSML
            let ssml = Self.buildSSML(text: text, voice: voice, rate: rate, volume: volume, pitch: pitch)
            let ssmlMessage = Self.buildSSMLMessage(ssml: ssml, requestId: connectionId)
            try await webSocket.send(.string(ssmlMessage))

            // Step 3: Receive audio data
            var audioData = Data()
            while true {
                let message = try await webSocket.receive()
                switch message {
                case .string(let text):
                    if text.contains("Path:turn.end") {
                        webSocket.cancel(with: .normalClosure, reason: nil)
                        return audioData
                    }
                case .data(let data):
                    guard data.count >= 2 else { continue }
                    let headerLength = Int(data[0]) << 8 | Int(data[1])
                    let audioStart = headerLength + 2
                    if audioStart < data.count {
                        audioData.append(data[audioStart...])
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            webSocket.cancel(with: .abnormalClosure, reason: nil)
            throw error
        }
    }

    // MARK: - Message Building

    private static func buildConfigMessage() -> String {
        let timestamp = dateToString()
        return "X-Timestamp:\(timestamp)\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":"
            + "{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},"
            + "\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\""
            + "}}}}\r\n"
    }

    private static func buildSSML(
        text: String,
        voice: String,
        rate: String,
        volume: String,
        pitch: String
    ) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")

        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voice)'>"
            + "<prosody pitch='\(pitch)' rate='\(rate)' volume='\(volume)'>"
            + escaped
            + "</prosody>"
            + "</voice>"
            + "</speak>"
    }

    private static func buildSSMLMessage(ssml: String, requestId: String) -> String {
        let timestamp = dateToString()
        return "X-RequestId:\(requestId)\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(timestamp)Z\r\n"
            + "Path:ssml\r\n\r\n"
            + ssml
    }

    // MARK: - DRM / Auth

    private static func generateSecMsGec() -> String {
        let winEpoch: Double = 11644473600
        let nsPerTick: Double = 1e9 / 100

        var ticks = Date().timeIntervalSince1970
        ticks += winEpoch
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        ticks *= nsPerTick

        let strToHash = String(format: "%.0f", ticks) + trustedClientToken
        let hash = SHA256.hash(data: Data(strToHash.utf8))
        return hash.map { String(format: "%02x", $0) }.joined().uppercased()
    }

    private static func generateMUID() -> String {
        (0..<32).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined().uppercased()
    }

    private static func dateToString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

enum EdgeTTSError: LocalizedError {
    case invalidURL
    case noAudioReceived
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Edge TTS URL"
        case .noAudioReceived:
            return "No audio received from Edge TTS"
        case .connectionFailed(let reason):
            return "Edge TTS connection failed: \(reason)"
        }
    }
}
