import Foundation
import Octomil
import CoreML
import Combine
import CoreVideo

/// View model for the Octomil Demo app
@MainActor
class OctomilDemoViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var isRegistered = false
    @Published var deviceId: String?
    @Published var model: OctomilModel?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isNetworkAvailable = true
    @Published var backgroundTrainingEnabled = false
    @Published var lastInferenceResult: String?
    @Published var lastTrainingResult: TrainingResult?

    // MARK: - Private Properties

    private var client: OctomilClient?
    private var networkToken: UUID?

    // MARK: - Configuration

    /// Replace with your actual API key and server URL
    private let apiKey = "your-api-key"
    private let orgId = "default"
    // For a real device, replace localhost with your Mac's LAN IP (e.g., 192.168.1.10)
    private static let defaultHost = "localhost"
    private static let defaultPort = 8000
    private let serverURL: URL = {
        let host = ProcessInfo.processInfo.environment["OCTOMIL_SERVER_HOST"] ?? defaultHost
        let port = ProcessInfo.processInfo.environment["OCTOMIL_SERVER_PORT"].flatMap(Int.init) ?? defaultPort
        guard let url = URL(string: "http://\(host):\(port)") else {
            fatalError("Invalid OCTOMIL_SERVER_HOST or OCTOMIL_SERVER_PORT")
        }
        return url
    }()
    private let defaultModelId = "fraud_detection"

    // MARK: - Initialization

    init() {
        setupClient()
        setupNetworkMonitoring()
    }

    deinit {
        if let token = networkToken {
            NetworkMonitor.shared.removeHandler(token)
        }
    }

    // MARK: - Setup

    private func setupClient() {
        let configuration = OctomilConfiguration.development
        client = OctomilClient(
            apiKey: apiKey,
            orgId: orgId,
            serverURL: serverURL,
            configuration: configuration
        )
    }

    private func setupNetworkMonitoring() {
        networkToken = NetworkMonitor.shared.addHandler { [weak self] isConnected in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = isConnected
            }
        }
    }

    // MARK: - Device Registration

    func registerDevice() async {
        guard let client = client else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let registration = try await client.register(
                metadata: [
                    "app_version": "1.1.0",
                    "demo_app": "true"
                ]
            )

            isRegistered = true
            deviceId = registration.deviceId

        } catch {
            handleError(error)
        }
    }

    // MARK: - Model Management

    func downloadModel() async {
        guard let client = client else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let downloadedModel = try await client.downloadModel(
                modelId: defaultModelId
            )

            model = downloadedModel

        } catch {
            handleError(error)
        }
    }

    func checkForUpdates() async {
        guard let client = client else { return }

        do {
            if let updateInfo = try await client.checkForUpdates(modelId: defaultModelId) {
                // Update available
                print("Update available: \(updateInfo.newVersion)")

                if updateInfo.isRequired {
                    await downloadModel()
                }
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Inference

    func runInference() async {
        guard let model = model else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Create sample input based on model's expected input
            // In a real app, you would use actual data
            let sampleInput = createSampleInput(for: model)
            let prediction = try model.predict(input: sampleInput)

            // Extract result
            if let firstOutput = prediction.featureNames.first,
               let value = prediction.featureValue(for: firstOutput) {
                lastInferenceResult = formatOutput(value)
            } else {
                lastInferenceResult = "Prediction completed"
            }

        } catch {
            handleError(error)
        }
    }

    // MARK: - Training

    func runTraining() async {
        guard let client = client,
              let model = model else { return }

        guard model.supportsTraining else {
            handleError(OctomilError.trainingNotSupported)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let config = TrainingConfig(
                epochs: 1,
                batchSize: 32,
                learningRate: 0.001
            )

            let batch = createTrainingBatch(for: model, batchSize: 8)
            if batch.count == 0 {
                handleError(OctomilError.trainingFailed(reason: "Training batch is empty"))
                return
            }

            let roundResult = try await client.joinRound(
                modelId: defaultModelId,
                dataProvider: { batch },
                config: config
            )

            lastTrainingResult = roundResult.trainingResult

        } catch {
            handleError(error)
        }
    }

    // MARK: - Background Training

    func toggleBackgroundTraining(enabled: Bool) {
        guard let client = client else { return }

        if enabled {
            client.enableBackgroundTraining(
                modelId: defaultModelId,
                dataProvider: { [weak self] in
                    guard let model = self?.model else {
                        return EmptyBatchProvider()
                    }
                    return self?.createTrainingBatch(for: model, batchSize: 8) ?? EmptyBatchProvider()
                },
                constraints: .relaxed
            )
        } else {
            client.disableBackgroundTraining()
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        if let octomilError = error as? OctomilError {
            errorMessage = octomilError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }

    // MARK: - Helper Methods

    private func createSampleInput(for model: OctomilModel) -> MLFeatureProvider {
        // Create a dictionary with sample values based on model's input description
        var inputDict: [String: Any] = [:]

        for (name, description) in model.inputDescriptions {
            switch description.type {
            case .double:
                inputDict[name] = 0.5
            case .int64:
                inputDict[name] = Int64(1)
            case .string:
                inputDict[name] = "sample"
            case .multiArray:
                // Create a sample multi-array
                if let constraint = description.multiArrayConstraint,
                   let array = createSampleMultiArray(constraint: constraint) {
                    inputDict[name] = array
                }
            case .image:
                if let constraint = description.imageConstraint {
                    inputDict[name] = createBlankPixelBuffer(
                        width: constraint.pixelsWide,
                        height: constraint.pixelsHigh
                    )
                }
            default:
                break
            }
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: inputDict) else {
            return EmptyFeatureProvider()
        }
        return provider
    }

    private func createSampleMultiArray(constraint: MLMultiArrayConstraint) -> MLMultiArray? {
        let shape = constraint.shape.map { $0.intValue }
        return try? MLMultiArray(shape: shape as [NSNumber], dataType: constraint.dataType)
    }

    private func createTrainingBatch(for model: OctomilModel, batchSize: Int) -> MLBatchProvider {
        let trainingInputs = model.mlModel.modelDescription.trainingInputDescriptionsByName
        let inputDescriptions = trainingInputs.isEmpty
            ? model.mlModel.modelDescription.inputDescriptionsByName
            : trainingInputs

        if inputDescriptions.isEmpty {
            return EmptyBatchProvider()
        }

        var providers: [MLFeatureProvider] = []
        providers.reserveCapacity(batchSize)

        for _ in 0..<batchSize {
            var featureDict: [String: Any] = [:]
            for (name, description) in inputDescriptions {
                if let value = createRandomValue(for: description) {
                    featureDict[name] = value
                }
            }
            if let provider = try? MLDictionaryFeatureProvider(dictionary: featureDict) {
                providers.append(provider)
            }
        }

        if providers.isEmpty {
            return EmptyBatchProvider()
        }

        return MLArrayBatchProvider(array: providers)
    }

    private func formatOutput(_ value: MLFeatureValue) -> String {
        switch value.type {
        case .double:
            return String(format: "%.4f", value.doubleValue)
        case .int64:
            return "\(value.int64Value)"
        case .string:
            return value.stringValue
        case .dictionary:
            if let dict = value.dictionaryValue as? [String: Double] {
                let sorted = dict.sorted { $0.value > $1.value }
                if let top = sorted.first {
                    return "\(top.key): \(String(format: "%.2f%%", top.value * 100))"
                }
            }
            return "Dictionary output"
        case .multiArray:
            if let array = value.multiArrayValue {
                return "Array[\(array.shape.map { $0.intValue })]"
            }
            return "MultiArray output"
        default:
            return "Output received"
        }
    }
}

// MARK: - Random Training Data Helpers

private func createRandomValue(for description: MLFeatureDescription) -> Any? {
    switch description.type {
    case .double:
        return Double.random(in: 0.0...1.0)
    case .int64:
        return Int64.random(in: 0...9)
    case .string:
        return "sample"
    case .multiArray:
        if let constraint = description.multiArrayConstraint {
            return createRandomMultiArray(constraint: constraint)
        }
        return nil
    case .image:
        if let constraint = description.imageConstraint {
            return createBlankPixelBuffer(
                width: constraint.pixelsWide,
                height: constraint.pixelsHigh
            )
        }
        return nil
    default:
        return nil
    }
}

private func createRandomMultiArray(constraint: MLMultiArrayConstraint) -> MLMultiArray? {
    let shape = constraint.shape.map { $0.intValue }
    guard let array = try? MLMultiArray(shape: shape as [NSNumber], dataType: constraint.dataType) else {
        return nil
    }
    for i in 0..<array.count {
        array[i] = NSNumber(value: Double.random(in: 0.0...1.0))
    }
    return array
}

private func createBlankPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
        memset(baseAddress, 0, CVPixelBufferGetDataSize(buffer))
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])

    return buffer
}

// MARK: - Empty Batch Provider

class EmptyBatchProvider: MLBatchProvider {
    var count: Int { return 0 }

    func features(at _: Int) -> MLFeatureProvider {
        fatalError("Empty batch provider")
    }
}

/// Placeholder feature provider used when sample input creation fails.
private class EmptyFeatureProvider: MLFeatureProvider {
    var featureNames: Set<String> { [] }
    func featureValue(for _: String) -> MLFeatureValue? { nil }
}
