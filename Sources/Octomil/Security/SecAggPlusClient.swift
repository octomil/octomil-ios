import Foundation
import CryptoKit
import os.log

// MARK: - SecAgg+ Configuration

/// Configuration for the SecAgg+ protocol with ECDH pairwise masking.
public struct SecAggPlusConfig: Sendable {

    /// Quantization parameters for clipping, scaling, and modular arithmetic.
    public struct QuantizationParams: Sendable {
        /// Clipping range for input values.
        public let clippingRange: Float
        /// Target range for quantized output.
        public let targetRange: Int
        /// Modular range for masked arithmetic.
        public let modRange: Int

        public init(
            clippingRange: Float = 8.0,
            targetRange: Int = 1 << 22,
            modRange: Int = 1 << 32
        ) {
            self.clippingRange = clippingRange
            self.targetRange = targetRange
            self.modRange = modRange
        }
    }

    public let sessionId: String
    public let roundId: String
    public let threshold: Int
    public let totalClients: Int
    public let myIndex: Int
    public let quantization: QuantizationParams

    /// Convenience accessors for backward compatibility.
    public var clippingRange: Float { quantization.clippingRange }
    public var targetRange: Int { quantization.targetRange }
    public var modRange: Int { quantization.modRange }

    public init(
        sessionId: String,
        roundId: String,
        threshold: Int,
        totalClients: Int,
        myIndex: Int,
        quantization: QuantizationParams = QuantizationParams()
    ) {
        self.sessionId = sessionId
        self.roundId = roundId
        self.threshold = threshold
        self.totalClients = totalClients
        self.myIndex = myIndex
        self.quantization = quantization
    }

}

// MARK: - SecAgg+ Client

/// Full SecAgg+ client implementing the 4-stage Flower protocol with ECDH pairwise masking.
///
/// **Stage 1 -- Setup**: Generate two Curve25519 key pairs: (sk1, pk1) for pairwise masks,
/// (sk2, pk2) for share encryption.
///
/// **Stage 2 -- Share Keys**: Shamir-share rd_seed and sk1, encrypt each pair with
/// AES-GCM using the ECDH shared secret from (sk2, peer_pk2), derived via HKDF with
/// info string "secagg-share-encryption".
///
/// **Stage 3 -- Collect Masked Vectors**: Clip + quantize + add self-mask (SHA-256 counter
/// mode PRG) + add/subtract pairwise masks (mod modRange). Pairwise mask keys derived
/// via HKDF with info string "secagg-pairwise-mask".
///
/// **Stage 4 -- Unmask**: Reveal rd_seed shares for active peers and sk1 shares for
/// dropped peers.
public actor SecAggPlusClient {

    // MARK: - Constants

    /// HKDF info string for pairwise mask key derivation.
    private static let pairwiseMaskInfo = Data("secagg-pairwise-mask".utf8)

    /// HKDF info string for share encryption key derivation.
    private static let shareEncryptionInfo = Data("secagg-share-encryption".utf8)

    // MARK: - Properties

    private let config: SecAggPlusConfig
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "SecAgg+")

    // Dual key pairs (Curve25519 / X25519 for ECDH)
    private let sk1: Curve25519.KeyAgreement.PrivateKey
    private let sk2: Curve25519.KeyAgreement.PrivateKey

    // Self-mask seed
    private var rdSeed: Data

    // Shamir shares of rd_seed and sk1
    private var rdSeedShares: [ShamirShare]?
    private var sk1Shares: [ShamirShare]?

    // Peer state
    private var peerPublicKeys: [Int: (pk1: Curve25519.KeyAgreement.PublicKey, pk2: Curve25519.KeyAgreement.PublicKey)] = [:]
    private var sharedKeys: [Int: SymmetricKey] = [:]  // idx -> ECDH derived key for share encryption

    // Received shares from peers
    private var receivedRdSeedShares: [Int: Data] = [:]
    private var receivedSk1Shares: [Int: Data] = [:]

    // Field arithmetic helper (reuse from basic SecAgg)
    private let fieldHelper = SecureAggregationClient()

    public init(config: SecAggPlusConfig) {
        self.config = config
        self.sk1 = Curve25519.KeyAgreement.PrivateKey()
        self.sk2 = Curve25519.KeyAgreement.PrivateKey()
        self.rdSeed = SecAggPlusClient.generateSecureRandom(count: 32)
    }

    // MARK: - Stage 1: Setup

    /// Returns this client's two public keys (pk1, pk2) as raw representation bytes.
    public func getPublicKeys() -> (pk1: Data, pk2: Data) {
        let pk1Data = sk1.publicKey.rawRepresentation
        let pk2Data = sk2.publicKey.rawRepresentation
        return (pk1: pk1Data, pk2: pk2Data)
    }

    // MARK: - Stage 2: Share Keys

    /// Store public keys received from all peers.
    /// - Parameter peerKeys: Maps peer index (1-based) to (pk1_raw, pk2_raw).
    public func receivePeerPublicKeys(_ peerKeys: [Int: (pk1: Data, pk2: Data)]) throws {
        for (idx, (pk1Data, pk2Data)) in peerKeys {
            let pk1 = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pk1Data)
            let pk2 = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pk2Data)
            peerPublicKeys[idx] = (pk1: pk1, pk2: pk2)

            // Compute ECDH shared key with each peer using sk2/pk2 for share encryption
            if idx != config.myIndex {
                let sharedSecret = try sk2.sharedSecretFromKeyAgreement(with: pk2)
                let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
                    using: SHA256.self,
                    salt: Data(),
                    sharedInfo: Self.shareEncryptionInfo,
                    outputByteCount: 32
                )
                sharedKeys[idx] = derivedKey
            }
        }
    }

    /// Shamir-share rd_seed and sk1, encrypt, and return encrypted payloads per peer.
    public func generateEncryptedShares() async throws -> [Int: Data] {
        // Shamir-share rd_seed as a single field element
        let seedInt = dataToFieldElement(rdSeed)
        let rdShares = await fieldHelper.generateShamirShares(
            secret: [seedInt],
            threshold: config.threshold,
            totalShares: config.totalClients
        )
        rdSeedShares = rdShares.map { $0.first! }

        // Shamir-share sk1 private key as a field element
        let sk1Int = dataToFieldElement(sk1.rawRepresentation)
        let sk1SharesList = await fieldHelper.generateShamirShares(
            secret: [sk1Int],
            threshold: config.threshold,
            totalShares: config.totalClients
        )
        sk1Shares = sk1SharesList.map { $0.first! }

        var encrypted: [Int: Data] = [:]

        for i in 0..<config.totalClients {
            let peerIdx = i + 1
            guard let rdShare = rdSeedShares?[i],
                  let sk1Share = sk1Shares?[i] else { continue }

            if peerIdx == config.myIndex {
                // Keep own shares locally
                receivedRdSeedShares[config.myIndex] = serializeShare(rdShare)
                receivedSk1Shares[config.myIndex] = serializeShare(sk1Share)
                continue
            }

            guard let sharedKey = sharedKeys[peerIdx] else { continue }

            // Serialize both shares
            let rdBytes = serializeShare(rdShare)
            let sk1Bytes = serializeShare(sk1Share)

            // Concatenate with length prefix
            var plaintext = Data()
            var rdLen = UInt32(rdBytes.count).bigEndian
            plaintext.append(Data(bytes: &rdLen, count: 4))
            plaintext.append(rdBytes)
            plaintext.append(sk1Bytes)

            // Encrypt with AES-GCM
            let sealed = try AES.GCM.seal(plaintext, using: sharedKey)
            encrypted[peerIdx] = sealed.combined!
        }

        return encrypted
    }

    /// Receive and decrypt share pairs from peers.
    public func receiveEncryptedShares(_ shares: [Int: Data]) throws {
        for (senderIdx, encryptedData) in shares {
            guard let sharedKey = sharedKeys[senderIdx] else {
                logger.warning("No shared key for peer \(senderIdx)")
                continue
            }

            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let plaintext = try AES.GCM.open(sealedBox, using: sharedKey)

            // Parse: <4 bytes rd_len><rd_share_bytes><sk1_share_bytes>
            guard plaintext.count >= 4 else { continue }
            let rdLen = plaintext.withUnsafeBytes { buf -> Int in
                Int(buf.load(as: UInt32.self).bigEndian)
            }
            guard plaintext.count >= 4 + rdLen else { continue }

            let rdBytes = plaintext[4..<4 + rdLen]
            let sk1Bytes = plaintext[(4 + rdLen)...]

            receivedRdSeedShares[senderIdx] = Data(rdBytes)
            receivedSk1Shares[senderIdx] = Data(sk1Bytes)
        }
    }

    // MARK: - Stage 3: Collect Masked Vectors

    /// Clip, stochastic-quantize, and mask a model update vector.
    /// Returns masked integers mod modRange.
    public func maskModelUpdate(_ values: [Float]) -> [Int] {
        let mod = config.modRange
        let n = values.count

        // Step 1: Clip + stochastic quantize
        let quantized = SecAggPlusClient.quantize(
            values,
            clippingRange: config.clippingRange,
            targetRange: config.targetRange
        )

        // Step 2: Add self-mask (SHA-256 counter mode PRG from rd_seed)
        let selfMask = SecAggPlusClient.pseudoRandGen(
            seed: rdSeed, numRange: mod, count: n
        )
        var masked = zip(quantized, selfMask).map { ($0 + $1) % mod }

        // Step 3: Add/subtract pairwise masks
        for (peerIdx, keys) in peerPublicKeys {
            if peerIdx == config.myIndex { continue }

            // Compute pairwise key from sk1 and peer's pk1
            guard let sharedSecret = try? sk1.sharedSecretFromKeyAgreement(with: keys.pk1) else {
                continue
            }
            let pairwiseKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(),
                sharedInfo: Self.pairwiseMaskInfo,
                outputByteCount: 32
            )
            let pairwiseKeyData = pairwiseKey.withUnsafeBytes { Data($0) }
            let pairwiseMask = SecAggPlusClient.pseudoRandGen(
                seed: pairwiseKeyData, numRange: mod, count: n
            )

            if config.myIndex > peerIdx {
                // Add (Flower convention: i > j -> ADD)
                masked = zip(masked, pairwiseMask).map { ($0 + $1) % mod }
            } else {
                // Subtract (Flower convention: i < j -> SUBTRACT)
                masked = zip(masked, pairwiseMask).map { (($0 - $1) % mod + mod) % mod }
            }
        }

        return masked
    }

    // MARK: - Stage 4: Unmask

    /// Reveal shares for the unmask phase.
    /// For active peers: reveal rd_seed shares.
    /// For dropped peers: reveal sk1 shares.
    public func unmask(
        activeIndices: [Int],
        droppedIndices: [Int]
    ) -> (nodeIds: [Int], shares: [Data]) {
        let allIds = activeIndices + droppedIndices
        var sharesList: [Data] = []

        for nid in activeIndices {
            sharesList.append(receivedRdSeedShares[nid] ?? Data())
        }

        for nid in droppedIndices {
            sharesList.append(receivedSk1Shares[nid] ?? Data())
        }

        return (nodeIds: allIds, shares: sharesList)
    }

    // MARK: - Quantization

    /// Stochastic quantization: clip, shift, scale, stochastic round.
    static func quantize(
        _ values: [Float],
        clippingRange: Float,
        targetRange: Int
    ) -> [Int] {
        guard !values.isEmpty, clippingRange != 0 else { return [] }

        let quantizer = Float(targetRange) / (2.0 * clippingRange)
        return values.map { v in
            let clipped = max(-clippingRange, min(clippingRange, v))
            let shifted = (clipped + clippingRange) * quantizer
            // Stochastic rounding
            let c = Int(ceil(shifted))
            let prob = Float(c) - shifted
            if Float.random(in: 0..<1) < prob {
                return c - 1
            }
            return c
        }
    }

    /// Reverse quantization: map integers back to floats.
    static func dequantize(
        _ quantized: [Int],
        clippingRange: Float,
        targetRange: Int
    ) -> [Float] {
        guard !quantized.isEmpty, targetRange != 0 else { return [] }

        let scale = (2.0 * clippingRange) / Float(targetRange)
        return quantized.map { q in
            Float(q) * scale - clippingRange
        }
    }

    // MARK: - Pseudo-Random Generation

    /// SHA-256 counter mode PRG for deterministic mask generation.
    ///
    /// For each output value: computes `SHA256(seed || counter_be32)`, takes the
    /// first 4 bytes as a big-endian UInt32, and reduces mod numRange.
    /// This matches the cross-platform convention (server, Android, Python).
    static func pseudoRandGen(seed: Data, numRange: Int, count: Int) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(count)

        for counter in 0..<count {
            var block = seed
            var counterBE = UInt32(counter).bigEndian
            block.append(Data(bytes: &counterBE, count: 4))

            // SHA-256 via CryptoKit
            let hash = SHA256.hash(data: block)
            // Take first 4 bytes as big-endian UInt32
            let hashBytes = Array(hash)
            let value = (UInt32(hashBytes[0]) << 24) |
                        (UInt32(hashBytes[1]) << 16) |
                        (UInt32(hashBytes[2]) << 8) |
                        UInt32(hashBytes[3])
            result.append(Int(value) % numRange)
        }

        return result
    }

    // MARK: - Helpers

    /// Convert first 8 bytes of data to a UInt64 field element.
    private func dataToFieldElement(_ data: Data) -> UInt64 {
        let bytes = [UInt8](data.prefix(8))
        var value: UInt64 = 0
        for b in bytes {
            value = (value << 8) | UInt64(b)
        }
        return value
    }

    /// Serialize a ShamirShare to bytes.
    private func serializeShare(_ share: ShamirShare) -> Data {
        var data = Data()
        var idx = UInt32(share.index).bigEndian
        data.append(Data(bytes: &idx, count: 4))
        var valLen = UInt32(share.value.count).bigEndian
        data.append(Data(bytes: &valLen, count: 4))
        data.append(share.value)
        return data
    }

    /// Generate cryptographically secure random bytes.
    private static func generateSecureRandom(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
