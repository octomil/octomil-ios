import SwiftUI
import OctomilClient

// Minimal transcription sample — batch audio-to-text.
//
// Prerequisites:
//   1. Replace the auth credentials below with your own.
//   2. Deploy a transcription model (e.g. whisper-small) via `octomil deploy --phone`
//      or configure managed delivery in the manifest.
//   3. Add a test audio file named "test_audio.wav" to the app bundle,
//      or use the built-in recording feature.

@main
struct TranscriptionSampleApp: App {
    @StateObject private var vm = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup {
            TranscriptionView(vm: vm)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class TranscriptionViewModel: ObservableObject {
    // -- Replace with your credentials --
    private let auth = AuthConfig.orgApiKey(orgId: "YOUR_ORG_ID", apiKey: "YOUR_API_KEY")
    private let modelName = "whisper-small"

    @Published var transcription = ""
    @Published var isTranscribing = false
    @Published var error: String?

    private var client: OctomilClient?

    func configure() async {
        guard client == nil else { return }
        let c = OctomilClient(auth: auth)
        try? await c.configure(manifest: AppManifest(models: [
            .init(id: modelName, capability: .transcription, delivery: .managed),
        ]))
        client = c
    }

    func transcribe() {
        guard let client, !isTranscribing else { return }

        // Load bundled test audio (add test_audio.wav to your app bundle)
        guard let url = Bundle.main.url(forResource: "test_audio", withExtension: "wav"),
              let audioData = try? Data(contentsOf: url) else {
            error = "Add a test_audio.wav file to the app bundle to test transcription."
            return
        }

        isTranscribing = true
        error = nil

        Task {
            do {
                let result = try await client.audio.transcriptions.create(
                    audio: audioData,
                    model: modelName
                )
                transcription = result.text
            } catch {
                self.error = error.localizedDescription
            }
            isTranscribing = false
        }
    }
}

// MARK: - View

struct TranscriptionView: View {
    @ObservedObject var vm: TranscriptionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if vm.transcription.isEmpty {
                    Text("Tap the button to transcribe the bundled audio file.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    ScrollView {
                        Text(vm.transcription)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                Button(action: vm.transcribe) {
                    Label(
                        vm.isTranscribing ? "Transcribing..." : "Transcribe Audio",
                        systemImage: "waveform"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isTranscribing)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Transcription Sample")
            .task { await vm.configure() }
        }
    }
}
