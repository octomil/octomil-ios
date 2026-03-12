#if canImport(SwiftUI)
import SwiftUI
import PhotosUI

/// Classification UI that displays top-K label results with horizontal
/// confidence bars.
///
/// Similar to ``VisionInputView`` for image selection, but the output
/// is a ranked list of labels with animated confidence bars instead of
/// free-form text.
@available(iOS 16.0, macOS 13.0, *)
struct ClassificationView: View {

    @ObservedObject var viewModel: TryItOutViewModel
    @State private var selectedImageData: Data?
    @State private var photoSelection: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image selection area
                imageSelectionArea
                    .padding(.top, 16)

                // Classify button
                classifyButton

                // Results area
                resultsArea
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
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            #endif

            Button {
                selectedImageData = nil
                viewModel.reset()
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
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.3))

                Text("Select an image to classify")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
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

    // MARK: - Classify Button

    private var classifyButton: some View {
        Button {
            guard let data = selectedImageData else { return }
            viewModel.classifyImage(imageData: data)
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "tag")
                }
                Text(isLoading ? "Classifying..." : "Classify")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(canClassify ? 1.0 : 0.3)
            )
            .cornerRadius(10)
        }
        .disabled(!canClassify)
    }

    // MARK: - Results Area

    @ViewBuilder
    private var resultsArea: some View {
        if !viewModel.classificationResults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Results")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    if let latency = viewModel.lastLatencyMs {
                        LatencyBadge(latencyMs: latency)
                    }
                }

                ForEach(viewModel.classificationResults) { result in
                    ConfidenceBar(result: result)
                }
            }
        } else if case .error(let message) = viewModel.inferenceState {
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

    private var canClassify: Bool {
        selectedImageData != nil && !isLoading
    }

    private var isLoading: Bool {
        if case .loading = viewModel.inferenceState { return true }
        return false
    }
}

// MARK: - Confidence Bar

/// A horizontal bar showing a classification label with its confidence score.
@available(iOS 15.0, macOS 12.0, *)
struct ConfidenceBar: View {
    let result: ClassificationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text(String(format: "%.1f%%", result.confidence * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barGradient)
                        .frame(
                            width: max(0, geo.size.width * result.confidence),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }

    private var barGradient: LinearGradient {
        if result.confidence > 0.7 {
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.green],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if result.confidence > 0.3 {
            return LinearGradient(
                colors: [Color.yellow.opacity(0.8), Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [Color.white.opacity(0.3), Color.white.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
#endif
