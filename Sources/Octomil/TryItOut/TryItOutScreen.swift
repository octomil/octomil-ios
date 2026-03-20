#if canImport(SwiftUI)
import SwiftUI

/// A modality-aware "Try it out" screen that adapts its UI based on the
/// deployed model's modality.
///
/// Launched from the "Try it out" button on ``PairingScreen``'s success state.
/// Reads the model's modality from ``PairedModelInfo`` and renders the
/// appropriate sub-view:
///
/// - `text` / `llm` -> ``TextChatView`` (chat-style text I/O)
/// - `vision` / `image` -> ``VisionInputView`` (photo picker + prompt)
/// - `audio` / `speech` -> ``AudioInputView`` (record + transcribe)
/// - `classification` / `classifier` -> ``ClassificationView`` (photo + top-K bars)
/// - unknown / nil -> defaults to ``TextChatView``
///
/// # Usage
///
/// ```swift
/// TryItOutScreen(modelInfo: pairedModel)
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct TryItOutScreen: View {

    @StateObject private var viewModel: TryItOutViewModel
    @Environment(\.dismiss) private var dismiss

    /// Creates a Try It Out screen for the given model.
    ///
    /// - Parameter modelInfo: Model information from the completed pairing flow.
    public init(modelInfo: PairedModelInfo) {
        _viewModel = StateObject(wrappedValue: TryItOutViewModel(modelInfo: modelInfo))
    }

    public var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                modalityContent
            }
        }
        .task {
            await viewModel.loadModelIfNeeded()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.08, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                if let latency = viewModel.lastLatencyMs {
                    LatencyBadge(latencyMs: latency)
                }
            }

            HStack(spacing: 8) {
                Text(viewModel.modelInfo.name)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(viewModel.modelInfo.version)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    )

                Spacer()

                Text(viewModel.modality.rawValue.capitalized)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.cyan.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.cyan.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Modality Content

    @ViewBuilder
    private var modalityContent: some View {
        switch viewModel.modality {
        case .text:
            TextChatView(viewModel: viewModel)
        case .vision:
            VisionInputView(viewModel: viewModel)
        case .audio:
            AudioInputView(viewModel: viewModel)
        case .classification:
            ClassificationView(viewModel: viewModel)
        }
    }
}

// MARK: - Latency Badge

/// Displays inference latency in a compact pill-shaped badge.
@available(iOS 15.0, macOS 12.0, *)
struct LatencyBadge: View {
    let latencyMs: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
            Text(formattedLatency)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
        }
        .foregroundColor(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.15))
        )
    }

    private var formattedLatency: String {
        if latencyMs >= 1000 {
            return String(format: "%.1fs", latencyMs / 1000)
        }
        return String(format: "%.0fms", latencyMs)
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 15.0, macOS 12.0, *)
struct TryItOutScreen_Previews: PreviewProvider {
    static var previews: some View {
        TryItOutScreen(
            modelInfo: PairedModelInfo(
                name: "phi-4-mini",
                version: "v1.2",
                sizeString: "2.7 GB",
                runtime: "CoreML",
                tokensPerSecond: 85.3,
                modalities: ["text"]
            )
        )
    }
}
#endif
#endif
