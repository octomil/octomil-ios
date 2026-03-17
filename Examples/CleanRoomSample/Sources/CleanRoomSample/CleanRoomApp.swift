import SwiftUI
import OctomilClient

/// Clean-room integration test: configures Octomil with a single
/// `.product(name: "OctomilClient", package: "octomil-ios")` dependency.
///
/// Zero engine-specific imports.
/// Zero registration calls.
/// Zero XCFramework knowledge.
@main
struct CleanRoomApp: App {
    @StateObject private var viewModel = CleanRoomViewModel()

    init() {
        // All runtime wiring happens inside the SDK — no engine imports needed
        Task {
            try await OctomilClient(
                auth: .orgApiKey(orgId: "demo-org", apiKey: "demo-key")
            ).configure(
                manifest: AppManifest(models: [
                    .init(
                        id: "phi-4-mini",
                        capability: .chat,
                        delivery: .managed
                    ),
                    .init(
                        id: "sherpa-zipformer-en-20m",
                        capability: .transcription,
                        delivery: .managed
                    ),
                    .init(
                        id: "smollm2-135m",
                        capability: .keyboardPrediction,
                        delivery: .managed
                    ),
                ])
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            CleanRoomView(viewModel: viewModel)
        }
    }
}

@MainActor
class CleanRoomViewModel: ObservableObject {
    @Published var chatResult = ""
    @Published var predictionResult = ""
    @Published var transcriptionResult = ""
}

struct CleanRoomView: View {
    @ObservedObject var viewModel: CleanRoomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Octomil Clean Room Test")
                .font(.title2.bold())

            Text("Single dependency: OctomilClient")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Zero engine imports. Zero registration calls.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Chat: \(viewModel.chatResult)")
            Text("Prediction: \(viewModel.predictionResult)")
            Text("Transcription: \(viewModel.transcriptionResult)")

            Spacer()
        }
        .padding()
    }
}
