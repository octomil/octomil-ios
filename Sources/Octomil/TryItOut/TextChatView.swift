#if canImport(SwiftUI)
import SwiftUI

/// Chat-style UI for text modality models.
///
/// Displays a scrollable list of chat bubbles with a text input field
/// and send button at the bottom. Each model response shows the
/// inference latency.
@available(iOS 15.0, macOS 12.0, *)
struct TextChatView: View {

    @ObservedObject var viewModel: TryItOutViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            emptyState
                                .padding(.top, 60)
                        }

                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if case .loading = viewModel.inferenceState {
                            loadingIndicator
                                .id("loading")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input bar
            inputBar
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.25))

            Text("Send a message to try the model")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
            )
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type a message...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? .cyan : .white.opacity(0.2))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.06, green: 0.06, blue: 0.14)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isLoading
    }

    private var isLoading: Bool {
        if case .loading = viewModel.inferenceState { return true }
        return false
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendTextPrompt(text)
    }
}

// MARK: - Chat Bubble

/// A single chat bubble displaying a user or model message.
@available(iOS 15.0, macOS 12.0, *)
struct ChatBubble: View {
    let message: TryItOutMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.isUser
                                  ? Color.cyan.opacity(0.25)
                                  : Color.white.opacity(0.08))
                    )

                if let latency = message.latencyMs {
                    Text(formatLatency(latency))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    private func formatLatency(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.1fs", ms / 1000)
        }
        return String(format: "%.0fms", ms)
    }
}
#endif
