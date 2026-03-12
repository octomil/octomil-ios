#if canImport(SwiftUI)
import SwiftUI
import PhotosUI

/// Vision input UI for image + optional prompt models.
///
/// Provides a photo picker button, an optional text prompt field,
/// an "Analyze" button, and a response area displaying the model's
/// output with latency.
@available(iOS 16.0, macOS 13.0, *)
struct VisionInputView: View {

    @ObservedObject var viewModel: TryItOutViewModel
    @State private var promptText: String = ""
    @State private var selectedImageData: Data?
    @State private var photoSelection: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image selection area
                imageSelectionArea
                    .padding(.top, 16)

                // Prompt field
                promptField

                // Analyze button
                analyzeButton

                // Output area
                outputArea
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Image Selection

    private var imageSelectionArea: some View {
        Group {
            if let imageData = selectedImageData {
                selectedImagePreview(data: imageData)
            } else {
                imagePickerButton
            }
        }
    }

    private func selectedImagePreview(data: Data) -> some View {
        VStack(spacing: 10) {
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            #endif

            Button {
                selectedImageData = nil
            } label: {
                Text("Remove")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var imagePickerButton: some View {
        PhotosPicker(
            selection: $photoSelection,
            matching: .images
        ) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.3))

                Text("Select an image")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [6])
                    )
                    .foregroundColor(.white.opacity(0.15))
            )
        }
        .onChange(of: photoSelection) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
            }
        }
    }

    // MARK: - Prompt Field

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt (optional)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            TextField("Describe what you want to analyze...", text: $promptText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Button {
            guard let data = selectedImageData else { return }
            let prompt = promptText.trimmingCharacters(in: .whitespaces)
            viewModel.analyzeImage(
                imageData: data,
                prompt: prompt.isEmpty ? nil : prompt
            )
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "eye")
                }
                Text(isLoading ? "Analyzing..." : "Analyze")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(canAnalyze ? 1.0 : 0.3)
            )
            .cornerRadius(10)
        }
        .disabled(!canAnalyze)
    }

    // MARK: - Output Area

    @ViewBuilder
    private var outputArea: some View {
        switch viewModel.inferenceState {
        case .idle:
            EmptyView()

        case .loading:
            EmptyView() // Loading shown in button

        case .result(let output, let latencyMs):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Result")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    LatencyBadge(latencyMs: latencyMs)
                }

                Text(output)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Error")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                    )
            }
        }
    }

    // MARK: - Helpers

    private var canAnalyze: Bool {
        selectedImageData != nil && !isLoading
    }

    private var isLoading: Bool {
        if case .loading = viewModel.inferenceState { return true }
        return false
    }
}
#endif
