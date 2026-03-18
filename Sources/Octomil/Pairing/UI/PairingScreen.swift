#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A SwiftUI pairing screen for the main app target.
///
/// Present this view when a deep link (`octomil://pair?token=X&host=Y`) is
/// received. It drives the full pairing flow through ``PairingViewModel``,
/// showing connecting, downloading, success, and error states.
///
/// Designed to be embedded inside a `NavigationStack` — does not render its
/// own navigation bar or full-screen background.
///
/// # Usage
///
/// ```swift
/// NavigationStack {
///     PairingScreen(token: "ABC123", host: "https://api.octomil.com")
///         .navigationTitle("Pair Device")
/// }
/// ```
///
/// Or use the `.octomilPairing()` view modifier for automatic deep link handling.
@available(iOS 15.0, macOS 12.0, *)
public struct PairingScreen: View {

    @StateObject private var viewModel: PairingViewModel

    /// Callback invoked when the user taps "Try it out" on the success screen.
    /// When nil, the built-in ``TryItOutScreen`` is presented automatically.
    private let onTryModel: ((PairedModelInfo) -> Void)?

    /// Callback invoked when the user taps "Open Dashboard".
    private let onOpenDashboard: (() -> Void)?

    /// Tracks whether the built-in TryItOutScreen is being presented.
    @State private var showTryItOut = false
    @State private var tryItOutModelInfo: PairedModelInfo?

    /// Creates a pairing screen.
    /// - Parameters:
    ///   - token: Pairing code from the deep link.
    ///   - host: Server URL from the deep link.
    ///   - onTryModel: Called when the user taps "Try it out". When nil,
    ///     the built-in ``TryItOutScreen`` is presented automatically.
    ///   - onOpenDashboard: Called when the user taps "Open Dashboard".
    public init(
        token: String,
        host: String,
        onTryModel: ((PairedModelInfo) -> Void)? = nil,
        onOpenDashboard: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PairingViewModel(token: token, host: host))
        self.onTryModel = onTryModel
        self.onOpenDashboard = onOpenDashboard
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                stateIcon
                    .padding(.top, 40)

                switch viewModel.state {
                case .connecting(let host):
                    connectingCard(host: host)

                case .downloading(let progress):
                    downloadingCard(progress: progress)

                case .success(let model):
                    successCard(model: model)

                case .error(let message):
                    errorCard(message: message)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .onAppear {
            viewModel.startPairing()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showTryItOut) {
            if let info = tryItOutModelInfo {
                NavigationView {
                    TryItOutScreen(modelInfo: info)
                }
            }
        }
        #else
        .sheet(isPresented: $showTryItOut) {
            if let info = tryItOutModelInfo {
                NavigationView {
                    TryItOutScreen(modelInfo: info)
                        .frame(minWidth: 400, minHeight: 500)
                }
            }
        }
        #endif
    }

    // MARK: - State Icon

    @ViewBuilder
    private var stateIcon: some View {
        switch viewModel.state {
        case .connecting:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                }
                Text("Connecting to server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .downloading:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                }
                Text("Deploying model to device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .success:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                }
                Text("Model deployed successfully")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .error:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                }
                Text("Something went wrong")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Connecting State

    private func connectingCard(host: String) -> some View {
        PairingCardView {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)

                Text("Connecting...")
                    .font(.headline)

                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(displayHost(host))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Downloading State

    private func downloadingCard(progress: DownloadProgressInfo) -> some View {
        PairingCardView {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progress.modelName)
                            .font(.headline)
                        if progress.totalBytes > 0 {
                            Text("\(progress.downloadedString) of \(progress.totalString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }

                ProgressView(value: progress.fraction)
                    .tint(.blue)
            }
        }
    }

    // MARK: - Success State

    private func successCard(model: PairedModelInfo) -> some View {
        VStack(spacing: 16) {
            PairingCardView {
                VStack(spacing: 12) {
                    HStack {
                        Text(model.name)
                            .font(.headline)
                        Spacer()
                        Text(model.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Divider()

                    VStack(spacing: 8) {
                        modelInfoRow(label: "Size", value: model.sizeString)
                        modelInfoRow(label: "Runtime", value: model.runtime)
                        if let tps = model.tokensPerSecond, tps > 0 {
                            modelInfoRow(label: "Performance", value: String(format: "%.1f tok/s", tps))
                        }
                    }
                }
            }

            Button {
                if let handler = onTryModel {
                    handler(model)
                } else {
                    tryItOutModelInfo = model
                    showTryItOut = true
                }
            } label: {
                Label("Try it out", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                if let handler = onOpenDashboard {
                    handler()
                } else {
                    openDashboardFallback()
                }
            } label: {
                Text("Open Dashboard")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Error State

    private func errorCard(message: String) -> some View {
        VStack(spacing: 16) {
            PairingCardView {
                VStack(spacing: 12) {
                    Text("Pairing Failed")
                        .font(.headline)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                viewModel.retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func modelInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func displayHost(_ host: String) -> String {
        var display = host
        if display.hasPrefix("https://") {
            display = String(display.dropFirst(8))
        } else if display.hasPrefix("http://") {
            display = String(display.dropFirst(7))
        }
        if display.hasSuffix("/") {
            display = String(display.dropLast())
        }
        return display
    }

    private func openDashboardFallback() {
        #if canImport(UIKit)
        if let url = URL(string: "https://app.octomil.com") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Card Container

/// Rounded card used by ``PairingScreen``.
@available(iOS 15.0, macOS 12.0, *)
struct PairingCardView<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 15.0, macOS 12.0, *)
struct PairingScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PairingScreen(
                token: "ABC123",
                host: "https://api.octomil.com"
            )
            .navigationTitle("Pair Device")
        }
    }
}
#endif
#endif
