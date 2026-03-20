import SwiftUI
import OctomilClient

// Minimal chat sample — streaming text generation with OctomilChat.
//
// Prerequisites:
//   1. Replace the auth credentials below with your own.
//   2. Deploy a chat-capable model (e.g. phi-4-mini) via `octomil deploy --phone`
//      or configure managed delivery in the manifest.

@main
struct ChatSampleApp: App {
    @StateObject private var vm = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ChatView(vm: vm)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ChatViewModel: ObservableObject {
    // -- Replace with your credentials --
    private let auth = AuthConfig.orgApiKey(orgId: "YOUR_ORG_ID", apiKey: "YOUR_API_KEY")
    private let modelName = "phi-4-mini"

    @Published var messages: [(role: String, text: String)] = []
    @Published var input = ""
    @Published var error: String?
    @Published var isGenerating = false
    @Published var isConfiguring = false

    private var client: OctomilClient?
    private var task: Task<Void, Never>?

    func configure() async {
        guard client == nil else { return }
        isConfiguring = true
        error = nil

        let c = OctomilClient(auth: auth)
        do {
            try await c.configure(
                manifest: AppManifest(models: [
                    .init(id: modelName, capability: .chat, delivery: .managed),
                ]),
                auth: auth
            )
            client = c
        } catch {
            client = nil
            self.error = "Setup failed: \(error.localizedDescription)"
        }

        isConfiguring = false
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isGenerating, let client else { return }

        messages.append((role: "user", text: text))
        input = ""
        isGenerating = true
        let idx = messages.count
        messages.append((role: "assistant", text: ""))

        let chat = OctomilChat(modelName: modelName, responses: client.responses)

        task = Task {
            var accumulated = ""
            do {
                for try await chunk in chat.stream(text) {
                    if let content = chunk.choices.first?.delta.content {
                        accumulated += content
                        messages[idx] = (role: "assistant", text: accumulated)
                    }
                }
            } catch is CancellationError {
                messages[idx] = (role: "assistant", text: accumulated + " [cancelled]")
            } catch {
                messages[idx] = (role: "assistant", text: "Error: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func stop() {
        task?.cancel()
    }
}

// MARK: - View

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(vm.messages.enumerated()), id: \.offset) { i, msg in
                                HStack {
                                    if msg.role == "user" { Spacer() }
                                    Text(msg.text)
                                        .padding(10)
                                        .background(msg.role == "user" ? Color.blue : Color(.systemGray5))
                                        .foregroundStyle(msg.role == "user" ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    if msg.role == "assistant" { Spacer() }
                                }
                                .id(i)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { proxy.scrollTo(vm.messages.count - 1) }
                }

                Divider()

                HStack {
                    TextField("Message", text: $vm.input)
                        .textFieldStyle(.roundedBorder)
                        .disabled(vm.isGenerating || vm.isConfiguring || vm.error != nil && vm.messages.isEmpty)
                        .onSubmit { vm.send() }

                    if vm.isGenerating {
                        Button("Stop", action: vm.stop)
                            .foregroundStyle(.red)
                    } else {
                        Button("Send", action: vm.send)
                            .disabled(
                                vm.isConfiguring ||
                                vm.input.trimmingCharacters(in: .whitespaces).isEmpty ||
                                (vm.error != nil && vm.messages.isEmpty)
                            )
                    }
                }
                .padding()

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding([.horizontal, .bottom])
                }
            }
            .navigationTitle("Chat Sample")
            .task { await vm.configure() }
        }
    }
}
