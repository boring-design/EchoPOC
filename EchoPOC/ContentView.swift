import SwiftUI

struct ContentView: View {
    @StateObject private var speechManager = SpeechManager()
    @State private var permissionsGranted = false
    @State private var isPressed = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text(speechManager.status.rawValue)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
                    .animation(.easeInOut, value: speechManager.status)

                ScrollView {
                    Text(speechManager.transcribedText.isEmpty ? "Hold the button and speak" : speechManager.transcribedText)
                        .font(.title3)
                        .foregroundStyle(speechManager.transcribedText.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: 200)

                VStack(spacing: 6) {
                    Text("TTS Voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(speechManager.selectedVoiceOption()?.name ?? "Auto")
                        .font(.headline)
                }

                Spacer()

                pushToTalkButton

                Spacer()
            }
            .padding()
            .navigationTitle("Echo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                VoiceSettingsView(speechManager: speechManager)
            }
            .task {
                permissionsGranted = await speechManager.requestPermissions()
            }
        }
    }

    // MARK: - Subviews

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
                        speechManager.stopListening()
                    }
            )
            .disabled(!permissionsGranted || speechManager.status == .speaking)
            .opacity(permissionsGranted ? 1.0 : 0.4)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch speechManager.status {
        case .idle: .secondary
        case .listening: .green
        case .speaking: .blue
        }
    }

    private var buttonColor: Color {
        switch speechManager.status {
        case .idle: .blue
        case .listening: .red
        case .speaking: .gray
        }
    }
}

#Preview {
    ContentView()
}
