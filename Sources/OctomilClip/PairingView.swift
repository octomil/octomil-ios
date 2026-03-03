#if os(iOS)
import SwiftUI
import Octomil
import CoreML

/// Main view for the Octomil App Clip pairing flow.
///
/// Displays different states as the pairing progresses:
/// - Connecting to the server
/// - Waiting for model deployment
/// - Downloading the model
/// - Running benchmarks
/// - Displaying results with interactive inference
public struct PairingView: View {

    @StateObject private var viewModel = PairingViewModel()

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    switch viewModel.state {
                    case .idle:
                        idleView

                    case .connecting:
                        connectingView

                    case .waiting(let modelName):
                        waitingView(modelName: modelName)

                    case .downloading(let progress):
                        downloadingView(progress: progress)

                    case .benchmarking(let metrics):
                        benchmarkingView(metrics: metrics)

                    case .complete(let report):
                        completeView(report: report)

                    case .error(let message):
                        errorView(message: message)
                    }
                }
                .padding()
            }
            .navigationTitle("Octomil")
            .navigationBarTitleDisplayMode(.inline)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                handleIncomingURL(activity)
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Octomil Pairing")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan the QR code from the Octomil dashboard to begin.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting to Octomil...")
                .font(.title3)
                .fontWeight(.medium)

            Text("Establishing connection with the server.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func waitingView(modelName: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Waiting for deployment...")
                .font(.title3)
                .fontWeight(.medium)

            HStack {
                Image(systemName: "cube.box")
                    .foregroundColor(.accentColor)
                Text(modelName)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)

            Text("The server is preparing an optimized model for your device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Downloading Model")
                .font(.title3)
                .fontWeight(.medium)

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func benchmarkingView(metrics: LiveMetrics) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Running performance tests...")
                .font(.title3)
                .fontWeight(.medium)

            if metrics.currentInference > 0 {
                VStack(spacing: 8) {
                    HStack {
                        Text("Inference")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(metrics.currentInference)/\(metrics.totalInferences)")
                    }

                    if let latency = metrics.lastLatencyMs {
                        HStack {
                            Text("Last latency")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f ms", latency))
                        }
                    }
                }
                .font(.subheadline)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }

    private func completeView(report: BenchmarkReport) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("Benchmark Complete")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Model + Device Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: "Model", value: report.modelName)
                        Divider()
                        row(label: "Device", value: report.deviceName)
                        row(label: "Chip", value: report.chipFamily)
                        row(label: "RAM", value: String(format: "%.1f GB", report.ramGB))
                        row(label: "OS", value: "iOS \(report.osVersion)")
                        if let delegate = report.activeDelegate {
                            Divider()
                            row(label: "Delegate", value: delegateDisplayName(delegate))
                        }
                        if let disabled = report.disabledDelegates, !disabled.isEmpty {
                            row(label: "Disabled", value: disabled.map { delegateDisplayName($0) }.joined(separator: ", "))
                        }
                    }
                } label: {
                    Label("Configuration", systemImage: "cpu")
                }

                // Performance Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: "Tokens/sec", value: String(format: "%.1f", report.tokensPerSecond))
                        row(label: "TTFT", value: String(format: "%.1f ms", report.ttftMs))
                        row(label: "TPOT", value: String(format: "%.1f ms", report.tpotMs))
                        Divider()
                        row(label: "p50 Latency", value: String(format: "%.1f ms", report.p50LatencyMs))
                        row(label: "p95 Latency", value: String(format: "%.1f ms", report.p95LatencyMs))
                        row(label: "p99 Latency", value: String(format: "%.1f ms", report.p99LatencyMs))
                    }
                } label: {
                    Label("Performance", systemImage: "speedometer")
                }

                // Resources Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: "Memory Peak", value: formatBytes(report.memoryPeakBytes))
                        row(label: "Model Load", value: String(format: "%.0f ms", report.modelLoadTimeMs))
                        row(label: "Cold Inference", value: String(format: "%.1f ms", report.coldInferenceMs))
                        row(label: "Warm Inference", value: String(format: "%.1f ms", report.warmInferenceMs))
                        row(label: "Inference Count", value: "\(report.inferenceCount)")
                        if let batteryLevel = report.batteryLevel {
                            row(label: "Battery", value: String(format: "%.0f%%", batteryLevel * 100))
                        }
                        if let thermalState = report.thermalState {
                            row(label: "Thermal", value: thermalState.capitalized)
                        }
                    }
                } label: {
                    Label("Resources", systemImage: "chart.bar")
                }

                // Share Button
                if let shareText = viewModel.shareText {
                    ShareLink(item: shareText) {
                        Label("Share Results", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                // Interactive Inference Section
                interactiveInferenceSection
            }
        }
    }

    // MARK: - Interactive Inference

    private var interactiveInferenceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Enter a prompt...", text: $viewModel.prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(viewModel.isRunningInference)

                Button {
                    viewModel.runInference()
                } label: {
                    HStack {
                        if viewModel.isRunningInference {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isRunningInference ? "Running..." : "Run Inference")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isRunningInference)

                if !viewModel.response.isEmpty {
                    Divider()

                    Text(viewModel.response)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)

                    if let metrics = viewModel.lastInferenceMetrics {
                        HStack(spacing: 8) {
                            MetricPill(
                                label: "Tokens/s",
                                value: String(format: "%.1f", metrics.tokensPerSecond)
                            )
                            MetricPill(
                                label: "TTFT",
                                value: String(format: "%.0f ms", metrics.ttftMs)
                            )
                            MetricPill(
                                label: "Tokens",
                                value: "\(metrics.totalTokens)"
                            )
                        }

                        HStack(spacing: 8) {
                            MetricPill(
                                label: "Prompt",
                                value: "\(metrics.promptTokens)"
                            )
                            MetricPill(
                                label: "Completion",
                                value: "\(metrics.completionTokens)"
                            )
                            MetricPill(
                                label: "Latency",
                                value: String(format: "%.0f ms", metrics.totalLatencyMs)
                            )
                        }
                    }
                }
            }
        } label: {
            Label("Try it", systemImage: "text.cursor")
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Pairing Failed")
                .font(.title3)
                .fontWeight(.medium)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    private func delegateDisplayName(_ delegate: String) -> String {
        switch delegate {
        case "neural_engine": return "Neural Engine"
        case "gpu": return "GPU"
        case "cpu": return "CPU"
        default: return delegate
        }
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ activity: NSUserActivity) {
        guard let url = activity.webpageURL else { return }
        handleURL(url)
    }

    private func handleURL(_ url: URL) {
        // Try the octomil:// deep link scheme first
        if let action = DeepLinkHandler.parse(url: url) {
            switch action {
            case .pair(let token, let host):
                let serverURL = host.flatMap(URL.init(string:))
                    ?? URL(string: "https://api.octomil.com")!
                viewModel.startPairing(code: token, serverURL: serverURL)
            case .unknown:
                viewModel.state = .error("Unrecognized deep link: \(url.absoluteString)")
            }
            return
        }

        // Fall back to universal link format: https://...?code=X&server=Y
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
              let code = codeItem.value else {
            viewModel.state = .error("Invalid pairing URL. Missing code parameter.")
            return
        }

        // Extract server URL from the QR URL host if available
        var serverURL = URL(string: "https://api.octomil.com")!
        if let hostItem = components.queryItems?.first(where: { $0.name == "server" }),
           let serverString = hostItem.value,
           let parsedURL = URL(string: serverString) {
            serverURL = parsedURL
        }

        viewModel.startPairing(code: code, serverURL: serverURL)
    }
}

// MARK: - MetricPill

/// Small pill showing a label/value pair, used for per-request inference metrics.
struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(6)
    }
}

// MARK: - InferenceMetrics

/// Per-request metrics from a single interactive inference run.
struct InferenceMetrics {
    let tokensPerSecond: Double
    let ttftMs: Double
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let totalLatencyMs: Double
}

// MARK: - Live Metrics

/// Live metrics displayed during benchmarking.
struct LiveMetrics {
    var currentInference: Int = 0
    var totalInferences: Int = 53
    var lastLatencyMs: Double?
}

// MARK: - Pairing State

/// States of the pairing flow.
enum PairingState {
    case idle
    case connecting
    case waiting(modelName: String)
    case downloading(progress: Double)
    case benchmarking(metrics: LiveMetrics)
    case complete(report: BenchmarkReport)
    case error(message: String)
}

// MARK: - View Model

/// View model driving the pairing flow and interactive inference.
@MainActor
final class PairingViewModel: ObservableObject {

    @Published var state: PairingState = .idle

    // Interactive inference state
    @Published var prompt: String = ""
    @Published var response: String = ""
    @Published var isRunningInference: Bool = false
    @Published var lastInferenceMetrics: InferenceMetrics?

    /// Compiled model URL kept alive for interactive inference after benchmarks.
    private var compiledModelURL: URL?

    /// Text for the share sheet.
    var shareText: String? {
        guard case .complete(let report) = state else { return nil }
        return """
        Octomil Benchmark Results
        Model: \(report.modelName)
        Device: \(report.deviceName) (\(report.chipFamily))
        Tokens/sec: \(String(format: "%.1f", report.tokensPerSecond))
        TTFT: \(String(format: "%.1f", report.ttftMs)) ms
        TPOT: \(String(format: "%.1f", report.tpotMs)) ms
        p50: \(String(format: "%.1f", report.p50LatencyMs)) ms
        p95: \(String(format: "%.1f", report.p95LatencyMs)) ms
        Memory Peak: \(String(format: "%.1f", Double(report.memoryPeakBytes) / (1024 * 1024))) MB
        """
    }

    func reset() {
        state = .idle
        prompt = ""
        response = ""
        isRunningInference = false
        lastInferenceMetrics = nil
        compiledModelURL = nil
    }

    func startPairing(code: String, serverURL: URL) {
        state = .connecting

        Task {
            do {
                let manager = PairingManager(serverURL: serverURL)

                // Step 1: Connect to session
                let session = try await manager.connect(code: code)
                state = .waiting(modelName: session.modelName)

                // Step 2: Wait for model deployment
                let deployment = try await manager.waitForDeployment(code: code)
                state = .downloading(progress: 0.5)

                // Step 3: Download model and run benchmarks
                state = .benchmarking(metrics: LiveMetrics())
                let report = try await manager.executeDeployment(deployment)

                // Step 4: Submit benchmark results
                try? await manager.submitBenchmark(code: code, report: report)

                state = .complete(report: report)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Interactive Inference

    func runInference() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !isRunningInference else { return }

        isRunningInference = true
        response = ""
        lastInferenceMetrics = nil

        let currentPrompt = prompt

        Task {
            let inferenceStart = Date()

            // Attempt streaming inference via LLMEngine if we have a compiled model
            if let modelURL = compiledModelURL {
                await runStreamingInference(prompt: currentPrompt, modelURL: modelURL, start: inferenceStart)
            } else {
                // Fallback: run single-shot prediction with the raw MLModel
                await runSingleShotInference(prompt: currentPrompt, start: inferenceStart)
            }

            isRunningInference = false
        }
    }

    /// Run streaming inference using LLMEngine and collect per-token metrics.
    private func runStreamingInference(prompt: String, modelURL: URL, start: Date) async {
        let engine = LLMEngine(modelPath: modelURL)
        let wrapper = InstrumentedStreamWrapper(modality: .text)
        let (stream, getResult) = wrapper.wrap(engine, input: prompt)

        // Estimate prompt tokens (rough: split by whitespace)
        let promptTokenCount = prompt.split(separator: " ").count

        var firstChunkTime: Date?
        var completionTokenCount = 0

        do {
            for try await chunk in stream {
                if firstChunkTime == nil {
                    firstChunkTime = Date()
                }

                if let text = String(data: chunk.data, encoding: .utf8) {
                    response += text
                    completionTokenCount += 1
                }
            }
        } catch {
            if response.isEmpty {
                response = "Error: \(error.localizedDescription)"
            }
        }

        let totalLatencyMs = Date().timeIntervalSince(start) * 1000
        let ttftMs = (firstChunkTime ?? Date()).timeIntervalSince(start) * 1000
        let totalTokens = promptTokenCount + completionTokenCount
        let tokensPerSecond: Double
        if totalLatencyMs > 0, completionTokenCount > 0 {
            tokensPerSecond = Double(completionTokenCount) / (totalLatencyMs / 1000.0)
        } else {
            tokensPerSecond = 0
        }

        lastInferenceMetrics = InferenceMetrics(
            tokensPerSecond: tokensPerSecond,
            ttftMs: ttftMs,
            promptTokens: promptTokenCount,
            completionTokens: completionTokenCount,
            totalTokens: totalTokens,
            totalLatencyMs: totalLatencyMs
        )
    }

    /// Fallback single-shot inference using MLModel.prediction directly.
    private func runSingleShotInference(prompt: String, start: Date) async {
        // Without a compiled model URL, we cannot run inference
        response = "Model not available for interactive inference. Re-run pairing to enable."

        let totalLatencyMs = Date().timeIntervalSince(start) * 1000
        let promptTokenCount = prompt.split(separator: " ").count

        lastInferenceMetrics = InferenceMetrics(
            tokensPerSecond: 0,
            ttftMs: totalLatencyMs,
            promptTokens: promptTokenCount,
            completionTokens: 0,
            totalTokens: promptTokenCount,
            totalLatencyMs: totalLatencyMs
        )
    }
}

// MARK: - Preview

struct PairingView_Previews: PreviewProvider {
    static var previews: some View {
        PairingView()
    }
}
#endif
