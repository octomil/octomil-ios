import XCTest
@testable import Octomil

final class CertificatePinningTests: XCTestCase {

    // MARK: - SHA-256 Hashing

    func testSHA256ProducesCorrectLength() {
        let data = Data("hello world".utf8)
        let hash = CertificatePinningDelegate.sha256(data: data)
        XCTAssertEqual(hash.count, 32, "SHA-256 hash should be 32 bytes")
    }

    func testSHA256IsDeterministic() {
        let data = Data("test input".utf8)
        let hash1 = CertificatePinningDelegate.sha256(data: data)
        let hash2 = CertificatePinningDelegate.sha256(data: data)
        XCTAssertEqual(hash1, hash2, "SHA-256 should produce the same hash for the same input")
    }

    func testSHA256DifferentInputsDifferentHashes() {
        let data1 = Data("input one".utf8)
        let data2 = Data("input two".utf8)
        let hash1 = CertificatePinningDelegate.sha256(data: data1)
        let hash2 = CertificatePinningDelegate.sha256(data: data2)
        XCTAssertNotEqual(hash1, hash2, "Different inputs should produce different hashes")
    }

    // MARK: - SPKI Pins (generated with openssl)

    // openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    func testSPKIHashMatchesOpenSSLForECP256() throws {
        let der = "MIIBjjCCATOgAwIBAgIUWyqhVR8tbONtWt/xDYAXrBDVdBMwCgYIKoZIzj0EAwIwGzEZMBcGA1UEAwwQdGVzdC5vY3RvbWlsLmNvbTAgFw0yNjEwMTcxNzE1MDRaGA8yMTI2MDkyMzE3MTUwNFowGzEZMBcGA1UEAwwQdGVzdC5vY3RvbWlsLmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABMBcDiai3plxF6zltZX36EVePvle73+zYWTvNSdfz3j4xRoUoFDjFZgC+WR3J7v0KR7CQKalRVbX8xwIdZclmTCjUzBRMB0GA1UdDgQWBBSO5xOGKtu2vvphMjxYa1kPT7i41TAfBgNVHSMEGDAWgBSO5xOGKtu2vvphMjxYa1kPT7i41TAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQCsi0LkkJ4vG8f2q7ABTXfrRNWepeZSyznNGeJ117beMwIhANwj3wv5Z6dp8BR53la6MKRJrsnNkoszqntbKubXeOlo"
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: der)) as CFData))
        XCTAssertEqual(CertificatePinningDelegate.spkiHash(of: cert), "KHdND4n2+FBhQbv+TVDsx6YO9/3/2AZscKs4sM23fAo=")
    }

    func testSPKIHashMatchesOpenSSLForRSA2048() throws {
        let der = "MIIDGTCCAgGgAwIBAgIUH1jDmNDbto/C3sE/Jkg/BgHa5jYwDQYJKoZIhvcNAQELBQAwGzEZMBcGA1UEAwwQdGVzdC5vY3RvbWlsLmNvbTAgFw0yNjEwMTcxNzE1MDRaGA8yMTI2MDkyMzE3MTUwNFowGzEZMBcGA1UEAwwQdGVzdC5vY3RvbWlsLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAM4m8i07vOGMg9Jh22u9Q5tulKOU84+2XK8XvHwvT/HqT4+zuPgWqTZ3c+9V1wOX/cuMZEelGE0QCmhX2MqiUJfS5smsK+p/Wgf6tyfqLQA5MtZ/42iXJgAAGM8pyOaFNA5QQsQaY1KpwGUAFa7ExGnMH24LXVTDGITEe9E894zkkNJpkWIodGGwrlKd4e4lBzc3/cZ0lMU6JZ7qLZ0K9kkHlbr2Oi0bjPZzlreZK8axK2/v1GwMiHN1CeUurQBjFN362HHQsCzNVlQEOYWYX5HDT/3JHJ5dAxjhqaIifV8f0aQuKs+PCGRhld1jlo3gvZmj9jTK7eTPteAUpn6GYn8CAwEAAaNTMFEwHQYDVR0OBBYEFPC5hRLf6OBSZndPL9tNSM0t0RI9MB8GA1UdIwQYMBaAFPC5hRLf6OBSZndPL9tNSM0t0RI9MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAB1HVDqlowKZCb/9ECHatwLAydAyJhTxkWdAUEP8YaObgeXGqdPUoopEbacXVIQEtrN11kA0vuR22KlCrJVzX/6gbcCjo0S0VGCSDdDvYMFkVTQpBWU0flPMNgn8HNGZ1iHng1SMtmdZjJVUDEO/ly+qLRZw8eZ5kBgO345pxdKjtwlyVAyLkEdx4UlpgDTIspSzEQ5HcCFE6l2yaOIZSg53Dc/lMjm1o5g1RlqV6eQbCYGtRA36aBHNtA1NNk9RWuYf7jbKh1x5fGwV5SC2N1t0MgNIXeFZISQzqNuALY4b2G8fKdJibIIXkbbCV4uXibT9y73BAf4GGkxDB0fiQUs="
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: der)) as CFData))
        XCTAssertEqual(CertificatePinningDelegate.spkiHash(of: cert), "nDTwqyrAgFUucdBbdGN13UwE7X5/qEC+4YL5iP48YtQ=")
    }

    // MARK: - Delegate Configuration

    func testDelegateCreatedWithPins() {
        let pins = ["dGVzdHBpbjE=", "dGVzdHBpbjI="]
        let delegate = CertificatePinningDelegate(pinnedHashes: pins)
        XCTAssertNotNil(delegate, "Delegate should be created with pin hashes")
    }

    func testDelegateCreatedWithoutPins() {
        let delegate = CertificatePinningDelegate(pinnedHashes: [])
        XCTAssertNotNil(delegate, "Delegate should be created with empty pin hashes for passthrough")
    }

    // MARK: - Configuration Integration

    func testConfigurationWithPins() {
        let config = OctomilConfiguration(
            pinnedCertificateHashes: ["abc123", "def456"]
        )
        XCTAssertEqual(config.pinnedCertificateHashes.count, 2)
    }

    func testConfigurationDefaultNoPins() {
        let config = OctomilConfiguration()
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty,
                       "Default configuration should have no pinned certificates")
    }

    func testStandardPresetHasNoPins() {
        let config = OctomilConfiguration.standard
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty)
    }

    func testDevelopmentPresetHasNoPins() {
        let config = OctomilConfiguration.development
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty)
    }

    func testProductionPresetHasNoPins() {
        let config = OctomilConfiguration.production
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty)
    }
}
