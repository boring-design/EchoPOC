import SwiftUI

struct VoiceSettingsView: View {
    @ObservedObject var speechManager: SpeechManager
    @State private var accountId: String = CloudflareConfig.accountId
    @State private var apiToken: String = CloudflareConfig.apiToken
    @State private var showToken = false

    private let rateOptions = [
        ("+0%", "1.0x"),
        ("+25%", "1.25x"),
        ("+50%", "1.5x"),
        ("+75%", "1.75x"),
        ("+100%", "2.0x"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(EdgeTTSVoice.allChinese) { voice in
                    Button {
                        speechManager.selectedVoiceId = voice.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.name)
                                    .foregroundStyle(.primary)
                                Text("\(voice.gender) · \(voice.style)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if speechManager.selectedVoiceId == voice.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("TTS Voice (Edge Neural)")
            }

            Section {
                ForEach(rateOptions, id: \.0) { rate, label in
                    Button {
                        speechManager.ttsRate = rate
                    } label: {
                        HStack {
                            Text(label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if speechManager.ttsRate == rate {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Preview") {
                    speechManager.speakAnnouncement("你好，这是语音预览测试。Hello, this is a voice preview.")
                }
                .disabled(speechManager.status == .speaking)
            } header: {
                Text("Speech Rate")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Enter Account ID", text: $accountId)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: accountId) { _, newValue in
                            CloudflareConfig.accountId = newValue
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if showToken {
                                TextField("Enter API Token", text: $apiToken)
                            } else {
                                SecureField("Enter API Token", text: $apiToken)
                            }
                        }
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: apiToken) { _, newValue in
                            CloudflareConfig.apiToken = newValue
                        }

                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if CloudflareConfig.isConfigured {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Label("Not configured", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            } header: {
                Text("Cloudflare Workers AI (STT)")
            } footer: {
                Text("Get credentials at dash.cloudflare.com → AI → Workers AI")
            }

            Section {
                HStack {
                    Text("STT")
                    Spacer()
                    Text("Cloudflare Whisper V3 Turbo")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("TTS")
                    Spacer()
                    Text("Microsoft Edge Neural TTS")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Engines")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        VoiceSettingsView(speechManager: SpeechManager())
    }
}
