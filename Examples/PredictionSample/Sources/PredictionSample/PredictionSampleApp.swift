import SwiftUI
import OctomilClient

// Minimal text prediction sample — next-word suggestions.
//
// Prerequisites:
//   1. Replace the auth credentials below with your own.
//   2. Deploy a prediction model (e.g. smollm2-135m) via `octomil deploy --phone`
//      or configure managed delivery in the manifest.

@main
struct PredictionSampleApp: App {
    @StateObject private var vm = PredictionViewModel()

    var body: some Scene {
        WindowGroup {
            PredictionView(vm: vm)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class PredictionViewModel: ObservableObject {
    // -- Replace with your credentials --
    private let auth = AuthConfig.orgApiKey(orgId: "YOUR_ORG_ID", apiKey: "YOUR_API_KEY")
    private let modelName = "smollm2-135m"

    @Published var input = "The weather today is"
    @Published var suggestions: [String] = []
    @Published var isPredicting = false
    @Published var error: String?

    private var client: OctomilClient?

    func configure() async {
        guard client == nil else { return }
        let c = OctomilClient(auth: auth)
        try? await c.configure(manifest: AppManifest(models: [
            .init(id: modelName, capability: .keyboardPrediction, delivery: .managed),
        ]))
        client = c
    }

    func predict() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isPredicting, let client else { return }

        isPredicting = true
        error = nil

        Task {
            do {
                let result = try await client.text.predictions.create(input: text, n: 5)
                suggestions = result.predictions.map(\.text)
            } catch {
                self.error = error.localizedDescription
            }
            isPredicting = false
        }
    }

    func appendSuggestion(_ suggestion: String) {
        if input.last == " " {
            input += suggestion
        } else {
            input += " " + suggestion
        }
        suggestions = []
        predict()
    }
}

// MARK: - View

struct PredictionView: View {
    @ObservedObject var vm: PredictionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $vm.input)
                    .frame(minHeight: 80, maxHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                    .padding(.horizontal)

                // Suggestion chips
                if !vm.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(vm.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { vm.appendSuggestion(suggestion) }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                HStack {
                    Button(action: vm.predict) {
                        Label(
                            vm.isPredicting ? "Predicting..." : "Predict Next",
                            systemImage: "text.cursor"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isPredicting || vm.input.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Clear") {
                        vm.input = ""
                        vm.suggestions = []
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Prediction Sample")
            .task { await vm.configure() }
        }
    }
}
