import Foundation
import AVFoundation

enum CloudflareAIError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case audioEncodingFailed
    case audioDecodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Cloudflare API"
        case .apiError(let message):
            return "Cloudflare API error: \(message)"
        case .audioEncodingFailed:
            return "Failed to encode audio data"
        case .audioDecodingFailed:
            return "Failed to decode audio response"
        }
    }
}

enum CloudflareAIConfigError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "Cloudflare API not configured. Please set Account ID and API Token in Settings."
    }
}

actor CloudflareAIService {
    private let session: URLSession

    private var accountId: String {
        CloudflareConfig.accountId
    }

    private var apiToken: String {
        CloudflareConfig.apiToken
    }

    private var baseURL: String {
        "https://api.cloudflare.com/client/v4/accounts/\(accountId)/ai/run"
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    private func ensureConfigured() throws {
        guard CloudflareConfig.isConfigured else {
            throw CloudflareAIConfigError.notConfigured
        }
    }

    // MARK: - STT (Whisper)

    struct TranscriptionResult {
        let text: String
        let language: String?
        let duration: Double?
    }

    func transcribe(audioData: Data) async throws -> TranscriptionResult {
        try ensureConfigured()
        let url = URL(string: "\(baseURL)/@cf/openai/whisper-large-v3-turbo")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Audio = audioData.base64EncodedString()
        let body: [String: Any] = [
            "audio": base64Audio,
            "vad_filter": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudflareAIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard httpResponse.statusCode == 200 else {
            let errors = (json?["errors"] as? [[String: Any]])?.first?["message"] as? String
            throw CloudflareAIError.apiError(errors ?? "HTTP \(httpResponse.statusCode)")
        }

        guard let result = json?["result"] as? [String: Any],
              let text = result["text"] as? String else {
            throw CloudflareAIError.invalidResponse
        }

        let info = result["transcription_info"] as? [String: Any]
        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: info?["language"] as? String,
            duration: info?["duration"] as? Double
        )
    }

    // MARK: - TTS (MeloTTS)

    func synthesize(text: String, language: String = "en") async throws -> Data {
        try ensureConfigured()
        let url = URL(string: "\(baseURL)/@cf/myshell-ai/melotts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "prompt": text,
            "lang": language
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudflareAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errors = (json?["errors"] as? [[String: Any]])?.first?["message"] as? String
            throw CloudflareAIError.apiError(errors ?? "HTTP \(httpResponse.statusCode)")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        print("[TTS] Response Content-Type: \(contentType), size: \(data.count) bytes")

        // Raw audio response (audio/mpeg, audio/wav, etc.)
        if contentType.contains("audio/") {
            print("[TTS] Got raw audio data")
            return data
        }

        // JSON response — try multiple structures
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("[TTS] JSON keys: \(json.keys.sorted())")

            // {"result": {"audio": "<base64>"}}
            if let result = json["result"] as? [String: Any],
               let audioBase64 = result["audio"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                print("[TTS] Decoded base64 audio from result.audio: \(audioData.count) bytes")
                return audioData
            }

            // {"audio": "<base64>"}
            if let audioBase64 = json["audio"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                print("[TTS] Decoded base64 audio from audio: \(audioData.count) bytes")
                return audioData
            }

            // Log full response for debugging
            if let responseStr = String(data: data.prefix(500), encoding: .utf8) {
                print("[TTS] Unexpected JSON: \(responseStr)")
            }
        }

        // Maybe the response IS raw audio but Content-Type is wrong
        if data.count > 100 {
            print("[TTS] Treating raw response as audio data")
            return data
        }

        throw CloudflareAIError.audioDecodingFailed
    }

    // MARK: - Language Detection

    static func detectLanguage(for text: String) -> String {
        let containsChinese = text.contains { char in
            char.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
                    return true
                default:
                    return false
                }
            }
        }
        return containsChinese ? "zh" : "en"
    }
}
