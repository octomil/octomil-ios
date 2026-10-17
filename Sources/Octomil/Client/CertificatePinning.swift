import Foundation
import CommonCrypto
import os.log

/// Delegate that validates the API host's leaf certificate against pinned SPKI SHA-256 hashes.
///
/// Pins are the base64 SHA-256 of the DER SubjectPublicKeyInfo, i.e. the output of
/// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`.
/// Hosts other than `pinnedHost` (e.g. presigned CDN downloads) and empty pin sets use
/// system validation.
public final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {

    private let pinnedHashes: [String]
    private let pinnedHost: String?
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "CertificatePinning")

    /// Creates a new pinning delegate.
    /// - Parameters:
    ///   - pinnedHashes: Base64-encoded SHA-256 hashes of allowed SPKI structures.
    ///     Pass an empty array to fall back to system validation.
    ///   - pinnedHost: Only this host is pinned. `nil` pins every host.
    public init(pinnedHashes: [String] = [], pinnedHost: String? = nil) {
        self.pinnedHashes = pinnedHashes
        self.pinnedHost = pinnedHost?.lowercased()
        super.init()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // No pins configured — fall back to system default validation.
        guard !pinnedHashes.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let pinnedHost, challenge.protectionSpace.host.lowercased() != pinnedHost {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the trust object using system root certificates first.
        var error: CFError?
        let trustValid = SecTrustEvaluateWithError(serverTrust, &error)
        guard trustValid else {
            logger.warning("Server trust evaluation failed: \(String(describing: error))")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract the server's leaf certificate public key and check its hash.
        if let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
           let hashBase64 = Self.spkiHash(of: serverCertificate) {

            if pinnedHashes.contains(hashBase64) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }

            logger.error("Certificate pin mismatch. Server hash: \(hashBase64)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        logger.error("Unable to extract public key from server certificate")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Hashing

    // DER SubjectPublicKeyInfo prefixes; SecKey exports only the raw key bytes.
    private static let rsa2048Header: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
        0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]
    private static let rsa4096Header: [UInt8] = [
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
        0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    ]
    private static let ecP256Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ]
    private static let ecP384Header: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
        0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
    ]
    private static let ecP521Header: [UInt8] = [
        0x30, 0x81, 0x9b, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05,
        0x2b, 0x81, 0x04, 0x00, 0x23, 0x03, 0x81, 0x86, 0x00
    ]

    /// Base64 SHA-256 of the certificate's SPKI, or nil for unsupported key types.
    static func spkiHash(of certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
              let type = attrs[kSecAttrKeyType] as? String,
              let bits = attrs[kSecAttrKeySizeInBits] as? Int else {
            return nil
        }

        let header: [UInt8]
        switch (type, bits) {
        case (kSecAttrKeyTypeRSA as String, 2048): header = rsa2048Header
        case (kSecAttrKeyTypeRSA as String, 4096): header = rsa4096Header
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 256): header = ecP256Header
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 384): header = ecP384Header
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 521): header = ecP521Header
        default: return nil
        }
        return sha256(data: Data(header) + raw).base64EncodedString()
    }

    /// Computes the SHA-256 hash of the given data.
    static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash)
    }

}
