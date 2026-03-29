import SwiftUI
import UIKit

struct VoiceSettingsView: View {
    @ObservedObject var speechManager: SpeechManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Current") {
                    selectableRow(option: speechManager.ttsVoiceOptions.first { $0.identifier == nil }!)
                }

                Section("Chinese") {
                    Text("Only high-quality voices are shown: Enhanced, Premium, and Siri.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(speechManager.installedChineseVoiceOptions) { option in
                        selectableRow(option: option)
                    }
                }

                Section("English") {
                    Text("Only high-quality voices are shown: Enhanced, Premium, and Siri.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(speechManager.installedEnglishVoiceOptions) { option in
                        selectableRow(option: option)
                    }
                }

                if !speechManager.downloadableVoiceOptions.isEmpty {
                    Section("Recommended Downloads") {
                        ForEach(speechManager.downloadableVoiceOptions) { option in
                            unavailableRow(option: option)
                        }
                    }

                    Section("How to Download") {
                        Text("Go to Settings > Accessibility > Spoken Content > Voices, download the voice you want, then return here and tap Refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Open App Settings") {
                            openAppSettings()
                        }
                    }
                }
            }
            .id(speechManager.availableVoiceRefreshToken)
            .navigationTitle("Voice Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") {
                        speechManager.refreshAvailableVoices()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectableRow(option: TTSVoiceOption) -> some View {
        Button {
            speechManager.selectedVoiceIdentifier = option.identifier
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .foregroundStyle(.primary)

                    if !option.subtitle.isEmpty {
                        Text(option.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if speechManager.selectedVoiceIdentifier == option.identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func unavailableRow(option: TTSVoiceOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.name)
                    .foregroundStyle(.primary)

                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Not Installed")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }

        UIApplication.shared.open(url)
    }
}

#Preview {
    VoiceSettingsView(speechManager: SpeechManager())
}
