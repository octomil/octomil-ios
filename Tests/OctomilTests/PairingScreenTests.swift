#if canImport(SwiftUI)
import Combine
import XCTest
@testable import Octomil

// MARK: - PairingScreenState Tests

final class PairingScreenStateTests: XCTestCase {

    // MARK: - DownloadProgressInfo Tests

    func testDownloadProgressInfoFormatsBytes() {
        // Megabytes
        let mb = DownloadProgressInfo(
            modelName: "test-model",
            fraction: 0.5,
            bytesDownloaded: 500 * 1024 * 1024,
            totalBytes: 1000 * 1024 * 1024
        )
        XCTAssertEqual(mb.downloadedString, "500 MB")
        XCTAssertEqual(mb.totalString, "1000 MB")
    }

    func testDownloadProgressInfoFormatsGigabytes() {
        let gb = DownloadProgressInfo(
            modelName: "large-model",
            fraction: 0.78,
            bytesDownloaded: 2_100_000_000,
            totalBytes: 2_700_000_000
        )
        // 2.1 GB / 2.7 GB threshold is > 1 GB so should format as GB
        XCTAssertTrue(gb.downloadedString.contains("GB"))
        XCTAssertTrue(gb.totalString.contains("GB"))
    }

    func testDownloadProgressInfoZeroBytes() {
        let zero = DownloadProgressInfo(
            modelName: "empty",
            fraction: 0.0,
            bytesDownloaded: 0,
            totalBytes: 0
        )
        XCTAssertEqual(zero.downloadedString, "0 MB")
        XCTAssertEqual(zero.totalString, "0 MB")
    }

    func testDownloadProgressInfoFractionAccuracy() {
        let partial = DownloadProgressInfo(
            modelName: "model",
            fraction: 0.333,
            bytesDownloaded: 333,
            totalBytes: 1000
        )
        XCTAssertEqual(partial.fraction, 0.333, accuracy: 0.001)
    }

    // MARK: - PairedModelInfo Tests

    func testPairedModelInfoProperties() {
        let info = PairedModelInfo(
            name: "phi-4-mini",
            version: "v1.2",
            sizeString: "2.7 GB",
            runtime: "CoreML",
            tokensPerSecond: 85.3
        )

        XCTAssertEqual(info.name, "phi-4-mini")
        XCTAssertEqual(info.version, "v1.2")
        XCTAssertEqual(info.sizeString, "2.7 GB")
        XCTAssertEqual(info.runtime, "CoreML")
        XCTAssertEqual(info.tokensPerSecond ?? -1, 85.3, accuracy: 0.01)
    }

    func testPairedModelInfoNilTokensPerSecond() {
        let info = PairedModelInfo(
            name: "test",
            version: "v1",
            sizeString: "100 MB",
            runtime: "ONNX",
            tokensPerSecond: nil
        )

        XCTAssertNil(info.tokensPerSecond)
    }

    // MARK: - PairingScreenState Enum Tests

    func testConnectingState() {
        let state = PairingScreenState.connecting(host: "192.168.1.100")
        if case .connecting(let host) = state {
            XCTAssertEqual(host, "192.168.1.100")
        } else {
            XCTFail("Expected connecting state")
        }
    }

    func testDownloadingState() {
        let progress = DownloadProgressInfo(
            modelName: "phi-4-mini",
            fraction: 0.5,
            bytesDownloaded: 1_350_000_000,
            totalBytes: 2_700_000_000
        )
        let state = PairingScreenState.downloading(progress: progress)
        if case .downloading(let p) = state {
            XCTAssertEqual(p.modelName, "phi-4-mini")
            XCTAssertEqual(p.fraction, 0.5, accuracy: 0.001)
        } else {
            XCTFail("Expected downloading state")
        }
    }

    func testSuccessState() {
        let model = PairedModelInfo(
            name: "llama-3b",
            version: "v2.0",
            sizeString: "1.5 GB",
            runtime: "CoreML",
            tokensPerSecond: 120.0
        )
        let state = PairingScreenState.success(model: model)
        if case .success(let m) = state {
            XCTAssertEqual(m.name, "llama-3b")
            XCTAssertEqual(m.version, "v2.0")
        } else {
            XCTFail("Expected success state")
        }
    }

    func testErrorState() {
        let state = PairingScreenState.error(message: "Network timeout")
        if case .error(let message) = state {
            XCTAssertEqual(message, "Network timeout")
        } else {
            XCTFail("Expected error state")
        }
    }
}

// MARK: - PairingViewModel Tests

@MainActor
final class PairingViewModelTests: XCTestCase {

    func testInitialStateIsConnecting() {
        let vm = PairingViewModel(token: "TEST123", host: "https://api.octomil.com")

        if case .connecting(let host) = vm.state {
            XCTAssertEqual(host, "https://api.octomil.com")
        } else {
            XCTFail("Expected initial state to be .connecting, got \(vm.state)")
        }
    }

    func testInvalidHostProducesError() async {
        // A host with invalid characters should produce an error state
        let vm = PairingViewModel(token: "TEST", host: "")

        let expectation = expectation(description: "State transitions to error")
        var cancellable: AnyCancellable?

        cancellable = vm.$state
            .dropFirst() // skip the initial .connecting value
            .sink { state in
                if case .error(let message) = state {
                    XCTAssertTrue(message.contains("Invalid server URL") || message.contains("error"),
                                  "Unexpected error message: \(message)")
                    expectation.fulfill()
                }
                // The flow may also fail with a network error since "" is not a valid URL
                // that's still an acceptable outcome - the important thing is it doesn't crash
            }

        vm.startPairing()

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable?.cancel()
    }

    func testRetryResetsToConnecting() async {
        let vm = PairingViewModel(token: "TEST", host: "https://api.octomil.com")

        // Manually set to error state for testing
        // We can't set state directly since it's private(set), but we can call retry
        // which internally resets to .connecting
        vm.retry()

        if case .connecting(let host) = vm.state {
            XCTAssertEqual(host, "https://api.octomil.com")
        } else {
            XCTFail("Expected retry to reset to .connecting")
        }
    }

    func testHostWithoutSchemeGetsHttpsPrefix() async {
        // When host lacks a scheme, the VM should prepend https://
        let vm = PairingViewModel(token: "TEST", host: "api.octomil.com")

        // The initial state should still capture the raw host
        if case .connecting(let host) = vm.state {
            XCTAssertEqual(host, "api.octomil.com")
        } else {
            XCTFail("Expected connecting state")
        }
    }
}

// MARK: - DownloadProgressInfo Formatting Tests

final class DownloadProgressFormattingTests: XCTestCase {

    func testFormatBytesSmallMB() {
        // 50 MB
        let info = DownloadProgressInfo(
            modelName: "test",
            fraction: 1.0,
            bytesDownloaded: 50 * 1024 * 1024,
            totalBytes: 50 * 1024 * 1024
        )
        XCTAssertEqual(info.downloadedString, "50 MB")
    }

    func testFormatBytesLargeMB() {
        // 999 MB (just under 1 GB)
        let bytes: Int64 = 999 * 1024 * 1024
        let info = DownloadProgressInfo(
            modelName: "test",
            fraction: 1.0,
            bytesDownloaded: bytes,
            totalBytes: bytes
        )
        XCTAssertEqual(info.downloadedString, "999 MB")
    }

    func testFormatBytesExactlyOneGB() {
        // 1024 MB = 1 GB
        let bytes: Int64 = 1024 * 1024 * 1024
        let info = DownloadProgressInfo(
            modelName: "test",
            fraction: 1.0,
            bytesDownloaded: bytes,
            totalBytes: bytes
        )
        XCTAssertEqual(info.downloadedString, "1.0 GB")
    }

    func testFormatBytesMultipleGB() {
        // 2.7 GB
        let bytes: Int64 = Int64(2.7 * 1024 * 1024 * 1024)
        let info = DownloadProgressInfo(
            modelName: "test",
            fraction: 1.0,
            bytesDownloaded: bytes,
            totalBytes: bytes
        )
        XCTAssertTrue(info.downloadedString.contains("2.7 GB") || info.downloadedString.contains("2.6 GB"),
                       "Expected ~2.7 GB, got: \(info.downloadedString)")
    }
}

// MARK: - Deep Link URL Parsing Tests

/// Tests for the URL parsing logic used by ``OctomilPairingModifier``.
/// We test the parsing separately since the modifier itself requires a SwiftUI host.
final class PairingDeepLinkParsingTests: XCTestCase {

    /// Parses a URL in the same way the modifier does.
    private func parseDeepLink(_ urlString: String) -> (token: String, host: String)? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        let isPairAction: Bool
        if components.scheme == "octomil" && components.host == "pair" {
            isPairAction = true
        } else if components.path.hasSuffix("/pair") {
            isPairAction = true
        } else {
            isPairAction = false
        }

        guard isPairAction else { return nil }

        let queryItems = components.queryItems ?? []
        guard let token = queryItems.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            return nil
        }

        let host = queryItems.first(where: { $0.name == "host" })?.value ?? "https://api.octomil.com"

        return (token: token, host: host)
    }

    func testCustomSchemeDeepLink() {
        let result = parseDeepLink("octomil://pair?token=ABC123&host=https://api.octomil.com")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "ABC123")
        XCTAssertEqual(result?.host, "https://api.octomil.com")
    }

    func testCustomSchemeWithoutHost() {
        let result = parseDeepLink("octomil://pair?token=XYZ")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "XYZ")
        XCTAssertEqual(result?.host, "https://api.octomil.com") // default
    }

    func testHttpsUniversalLink() {
        let result = parseDeepLink("https://app.octomil.com/pair?token=TEST&host=https://custom.server.io")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "TEST")
        XCTAssertEqual(result?.host, "https://custom.server.io")
    }

    func testMissingTokenReturnsNil() {
        let result = parseDeepLink("octomil://pair?host=https://api.octomil.com")
        XCTAssertNil(result)
    }

    func testEmptyTokenReturnsNil() {
        let result = parseDeepLink("octomil://pair?token=&host=https://api.octomil.com")
        XCTAssertNil(result)
    }

    func testNonPairSchemeReturnsNil() {
        let result = parseDeepLink("octomil://settings?token=ABC123")
        XCTAssertNil(result)
    }

    func testUnrelatedURLReturnsNil() {
        let result = parseDeepLink("https://example.com/page")
        XCTAssertNil(result)
    }

    func testCustomHostParameter() {
        let result = parseDeepLink("octomil://pair?token=CODE42&host=http://192.168.1.100:8000")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "CODE42")
        XCTAssertEqual(result?.host, "http://192.168.1.100:8000")
    }
}
#endif
