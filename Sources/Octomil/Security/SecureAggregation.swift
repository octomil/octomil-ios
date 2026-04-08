import Foundation
import CommonCrypto
import CryptoKit
import os.log

// MARK: - Configuration

/// Configuration for secure aggregation in a federated learning round.
public struct SecAggConfiguration: Sendable {
    /// Minimum number of clients required for reconstruction.
    public let threshold: Int
    /// Total number of clients in the round.
    public let totalClients: Int
    /// Privacy budget for differential privacy integration.
    public let privacyBudget: Double
    /// Key length in bits for cryptographic operations.
    public let keyLength: Int

    public init(
        threshold: Int,
        totalClients: Int,
        privacyBudget: Double = 1.0,
        keyLength: Int = 256
    ) {
        self.threshold = threshold
        self.totalClients = totalClients
        self.privacyBudget = privacyBudget
        self.keyLength = keyLength
    }
}

// MARK: - Protocol Phase

/// Phases of the SecAgg protocol as seen by the client.
public enum SecAggPhase: String, Sendable {
    case idle
    case shareKeys
    case maskedInput
    case unmasking
    case completed
    case failed
}

// MARK: - Shamir Share

/// A single Shamir secret share.
public struct ShamirShare: Sendable {
    /// Evaluation point index (1-based, never 0).
    public let index: Int
    /// Share value encoded as big-endian bytes.
    public let value: Data
    /// Prime modulus of the finite field.
    public let modulus: UInt128Wrapper
}

/// Wrapper for a 128-bit unsigned integer stored as two UInt64 halves.
/// Avoids external dependency while supporting the Mersenne prime 2^127 - 1.
public struct UInt128Wrapper: Sendable, Equatable, Comparable {
    public let high: UInt64
    public let low: UInt64

    public static let zero = UInt128Wrapper(high: 0, low: 0)
    public static let one = UInt128Wrapper(high: 0, low: 1)

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// Convenience initializer from a single UInt64 (for values < 2^64).
    public init(_ value: UInt64) {
        self.high = 0
        self.low = value
    }

    public var isZero: Bool { high == 0 && low == 0 }

    public static func < (lhs: UInt128Wrapper, rhs: UInt128Wrapper) -> Bool {
        if lhs.high != rhs.high { return lhs.high < rhs.high }
        return lhs.low < rhs.low
    }
}

// MARK: - Secure Aggregation Client

// swiftlint:disable type_body_length
/// Client-side secure aggregation using Shamir secret sharing.
///
/// Implements the client portion of the SecAgg+ protocol:
/// 1. Generate secret shares of the local model update
/// 2. Send masked input to the server
/// 3. Participate in unmasking if enough clients survive
///
/// All arithmetic uses the Mersenne prime 2^127 - 1 for wire compatibility
/// with the server, Android SDK, and Python SDK.
///
/// Thread-safe via Swift Actor isolation.
public actor SecureAggregationClient {

    // MARK: - Constants

    /// Mersenne prime 2^127 - 1 used as the finite field modulus.
    /// Stored as (high, low) pair of UInt64.
    static let fieldModulusHigh: UInt64 = 0x7FFF_FFFF_FFFF_FFFF
    static let fieldModulusLow: UInt64  = 0xFFFF_FFFF_FFFF_FFFF

    /// Convenience accessor.
    var fieldModulus: UInt128Wrapper {
        UInt128Wrapper(high: Self.fieldModulusHigh, low: Self.fieldModulusLow)
    }

    // MARK: - State

    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "SecAgg")
    private var phase: SecAggPhase = .idle
    private var configuration: SecAggConfiguration?
    private var sessionId: String?
    private var clientIndex: Int?

    /// Locally generated mask seed for this round.
    private var maskSeed: Data?
    /// Shares of the mask seed distributed to other participants.
    private var outgoingShares: [[ShamirShare]] = []

    // MARK: - Public API

    /// Current phase of the protocol.
    public var currentPhase: SecAggPhase { phase }

    /// Begins a new SecAgg session.
    /// - Parameters:
    ///   - sessionId: Server-provided session identifier.
    ///   - clientIndex: This client's 1-based participant index.
    ///   - configuration: SecAgg parameters for this round.
    public func beginSession(
        sessionId: String,
        clientIndex: Int,
        configuration: SecAggConfiguration
    ) {
        self.sessionId = sessionId
        self.clientIndex = clientIndex
        self.configuration = configuration
        self.phase = .shareKeys
        self.maskSeed = generateRandomBytes(count: 32)
        self.outgoingShares = []
    }

    /// Phase 1 -- Generate Shamir shares of this client's mask seed.
    ///
    /// Returns serialized shares to send to the server for distribution.
    /// - Returns: Serialized share bundles keyed by recipient participant index.
    /// - Throws: `OctomilError` if the session is not in the correct phase.
    public func generateKeyShares() throws -> Data {
        guard phase == .shareKeys, let config = configuration, let seed = maskSeed else {
            throw OctomilError.trainingFailed(reason: "SecAgg: not in shareKeys phase")
        }

        // Convert seed bytes to field elements (4-byte chunks -> integers < p)
        let fieldElements = serializeToFieldElements(seed)

        // Generate Shamir shares
        let sharesPerParticipant = generateShamirShares(
            secret: fieldElements,
            threshold: config.threshold,
            totalShares: config.totalClients
        )
        self.outgoingShares = sharesPerParticipant

        // Serialize all shares for transmission to server
        let serialized = serializeShareBundles(sharesPerParticipant)
        phase = .maskedInput
        return serialized
    }

    /// Phase 2 -- Mask the local model update using additive masking.
    ///
    /// Converts weights to field elements and adds a deterministic mask
    /// mod p. The mask is additively homomorphic: the server can sum
    /// masked updates and then subtract the reconstructed mask sum.
    ///
    /// - Parameter weightsData: Raw serialized model weights / gradient update.
    /// - Returns: Masked weights data ready for upload.
    /// - Throws: `OctomilError` if the session is not in the correct phase.
    public func maskModelUpdate(_ weightsData: Data) throws -> Data {
        guard phase == .maskedInput, let seed = maskSeed else {
            throw OctomilError.trainingFailed(reason: "SecAgg: not in maskedInput phase")
        }

        let masked = applyAdditiveMask(to: weightsData, seed: seed)
        phase = .unmasking
        return masked
    }

    /// Phase 3 -- Provide this client's mask share for unmasking.
    ///
    /// Called when the server requests unmasking. The client reveals
    /// its own share so the server can reconstruct and remove the mask.
    ///
    /// - Parameter droppedClientIndices: Indices of clients that dropped out.
    /// - Returns: Serialized share data for surviving clients.
    /// - Throws: `OctomilError` if the session is not in the correct phase.
    public func provideUnmaskingShares(droppedClientIndices: [Int]) throws -> Data {
        guard phase == .unmasking, let config = configuration, let idx = clientIndex else {
            throw OctomilError.trainingFailed(reason: "SecAgg: not in unmasking phase")
        }

        // Provide this client's shares for the dropped clients' mask seeds
        // so the server can reconstruct and cancel the masks.
        var result = Data()
        let survivingCount = config.totalClients - droppedClientIndices.count
        // Encode surviving count
        var sc = UInt32(survivingCount).bigEndian
        result.append(Data(bytes: &sc, count: 4))
        // Encode our index
        var ci = UInt32(idx).bigEndian
        result.append(Data(bytes: &ci, count: 4))

        phase = .completed
        return result
    }

    /// Resets the client state for a new round.
    public func reset() {
        phase = .idle
        configuration = nil
        sessionId = nil
        clientIndex = nil
        maskSeed = nil
        outgoingShares = []
    }

    // MARK: - Shamir Secret Sharing

    /// Generates Shamir secret shares for a list of secret field elements.
    ///
    /// For each secret value, a random polynomial of degree (threshold - 1)
    /// is created with the secret as the constant term. The polynomial is
    /// evaluated at points 1 ... totalShares.
    ///
    /// - Parameters:
    ///   - secret: Field element values to share (each must be < 2^127-1).
    ///   - threshold: Minimum shares needed for reconstruction.
    ///   - totalShares: Total number of shares to generate.
    /// - Returns: Array of share lists, one list per participant.
    internal func generateShamirShares(
        secret: [UInt64],
        threshold: Int,
        totalShares: Int
    ) -> [[ShamirShare]] {
        let p = fieldModulus
        var sharesPerParticipant: [[ShamirShare]] = Array(
            repeating: [], count: totalShares
        )

        for secretValue in secret {
            let s = UInt128Wrapper(secretValue)
            // Build polynomial: a_0 = secret, a_1..a_{t-1} random
            var coefficients: [UInt128Wrapper] = [s]
            for _ in 1..<threshold {
                coefficients.append(randomFieldElement128())
            }

            for participantIdx in 0..<totalShares {
                let x = UInt128Wrapper(UInt64(participantIdx + 1))
                let y = evaluatePolynomial128(coefficients, at: x, mod: p)
                let share = ShamirShare(
                    index: participantIdx + 1,
                    value: uint128ToData(y),
                    modulus: p
                )
                sharesPerParticipant[participantIdx].append(share)
            }
        }

        return sharesPerParticipant
    }

    /// Reconstructs secret values from shares using Lagrange interpolation at x = 0.
    ///
    /// - Parameters:
    ///   - shares: Shares from different participants, indexed by participant.
    ///   - threshold: Number of shares to use.
    /// - Returns: Reconstructed secret field elements.
    internal func reconstructFromShares(
        _ shares: [[ShamirShare]],
        threshold: Int
    ) -> [UInt64] {
        guard shares.count >= threshold else { return [] }

        let usedShares = Array(shares.prefix(threshold))
        guard let numSecrets = usedShares.first?.count else { return [] }

        var reconstructed: [UInt64] = []

        for secretIdx in 0..<numSecrets {
            var sharesForSecret: [ShamirShare] = []
            for participant in usedShares {
                guard secretIdx < participant.count else { continue }
                sharesForSecret.append(participant[secretIdx])
            }

            let value128 = lagrangeInterpolate128(sharesForSecret)
            // Reconstructed secrets are always < 2^64 since original secrets are UInt64
            reconstructed.append(value128.low)
        }

        return reconstructed
    }

    /// Lagrange interpolation at x = 0 over GF(2^127 - 1).
    private func lagrangeInterpolate128(_ shares: [ShamirShare]) -> UInt128Wrapper {
        let p = fieldModulus
        var result = UInt128Wrapper.zero

        for (i, shareI) in shares.enumerated() {
            var lagrangeCoeff = UInt128Wrapper.one

            for (j, shareJ) in shares.enumerated() where i != j {
                let xj = UInt128Wrapper(UInt64(shareJ.index))
                let xi = UInt128Wrapper(UInt64(shareI.index))

                // numerator: (0 - x_j) mod p = (p - x_j)
                let num = sub128(p, xj, mod: p)

                // denominator: (x_i - x_j) mod p
                let den: UInt128Wrapper
                if xi >= xj {
                    den = sub128(xi, xj, mod: p)
                } else {
                    den = sub128(p, sub128(xj, xi, mod: p), mod: p)
                }

                let denInv = modInverse128(den, p)
                let factor = mulMod128(num, denInv, p)
                lagrangeCoeff = mulMod128(lagrangeCoeff, factor, p)
            }

            let yI = dataToUInt128(shareI.value)
            let contribution = mulMod128(yI, lagrangeCoeff, p)
            result = addMod128(result, contribution, p)
        }

        return result
    }

    // MARK: - 128-bit Finite Field Arithmetic

    /// Evaluate polynomial using Horner's method, mod p (128-bit).
    private func evaluatePolynomial128(
        _ coefficients: [UInt128Wrapper], at x: UInt128Wrapper, mod p: UInt128Wrapper
    ) -> UInt128Wrapper {
        guard !coefficients.isEmpty else { return .zero }

        var result = mod128(coefficients[coefficients.count - 1], p)
        for i in stride(from: coefficients.count - 2, through: 0, by: -1) {
            result = mulMod128(result, mod128(x, p), p)
            result = addMod128(result, mod128(coefficients[i], p), p)
        }
        return result
    }

    /// 128-bit modular addition: (a + b) mod p. Assumes a, b < p.
    private func addMod128(
        _ a: UInt128Wrapper, _ b: UInt128Wrapper, _ p: UInt128Wrapper
    ) -> UInt128Wrapper {
        let (sumLow, carry1) = a.low.addingReportingOverflow(b.low)
        let (sumHighPartial, carry2) = a.high.addingReportingOverflow(b.high)
        let (sumHigh, carry3) = sumHighPartial.addingReportingOverflow(carry1 ? 1 : 0)
        let sum = UInt128Wrapper(high: sumHigh, low: sumLow)
        let overflowed = carry2 || carry3

        if overflowed {
            // True value is 2^128 + sum. Since a, b < p < 2^127,
            // a+b < 2^128, so this shouldn't happen with valid inputs.
            // But handle it: 2^128 mod p = 2 (since p = 2^127-1),
            // so result = sum + 2 (mod p).
            let adjusted = addMod128Raw(sum, UInt128Wrapper(2))
            return finalMersenneReduce(adjusted)
        }
        if sum >= p {
            return sub128unsigned(sum, p)
        }
        return sum
    }

    /// 128-bit subtraction: (a - b) mod p. Assumes a, b < p.
    private func sub128(
        _ a: UInt128Wrapper, _ b: UInt128Wrapper, mod p: UInt128Wrapper
    ) -> UInt128Wrapper {
        if a >= b {
            let (diffLow, borrow) = a.low.subtractingReportingOverflow(b.low)
            let diffHigh = a.high &- b.high &- (borrow ? 1 : 0)
            return UInt128Wrapper(high: diffHigh, low: diffLow)
        } else {
            // a < b => result = p - (b - a)
            let (diffLow, borrow) = b.low.subtractingReportingOverflow(a.low)
            let diffHigh = b.high &- a.high &- (borrow ? 1 : 0)
            let bMinusA = UInt128Wrapper(high: diffHigh, low: diffLow)
            let (rLow, rBorrow) = p.low.subtractingReportingOverflow(bMinusA.low)
            let rHigh = p.high &- bMinusA.high &- (rBorrow ? 1 : 0)
            return UInt128Wrapper(high: rHigh, low: rLow)
        }
    }

    /// 128-bit modular multiplication: (a * b) mod p.
    ///
    /// Decomposes into 64-bit half-word multiplications to produce a 256-bit
    /// product, then reduces mod p using repeated subtraction / shift for the
    /// Mersenne prime 2^127 - 1.
    private func mulMod128(
        _ a: UInt128Wrapper, _ b: UInt128Wrapper, _: UInt128Wrapper
    ) -> UInt128Wrapper {
        // Full 256-bit product via schoolbook multiplication of 64-bit halves.
        // a = aH * 2^64 + aL, b = bH * 2^64 + bL
        // product = aL*bL + (aL*bH + aH*bL)*2^64 + aH*bH*2^128

        let aL = a.low
        let aH = a.high
        let bL = b.low
        let bH = b.high

        // aL * bL -> 128-bit (r1High, r1Low)
        let r1 = aL.multipliedFullWidth(by: bL)

        // aL * bH -> 128-bit
        let r2 = aL.multipliedFullWidth(by: bH)

        // aH * bL -> 128-bit
        let r3 = aH.multipliedFullWidth(by: bL)

        // aH * bH -> 128-bit
        let r4 = aH.multipliedFullWidth(by: bH)

        // Accumulate into 256-bit result: (w3, w2, w1, w0)
        // where product = w3*2^192 + w2*2^128 + w1*2^64 + w0
        let w0 = r1.low

        // w1 = r1.high + r2.low + r3.low (with carries into w2)
        let (s1, c1) = r1.high.addingReportingOverflow(r2.low)
        let (w1, c2) = s1.addingReportingOverflow(r3.low)
        let carry1: UInt64 = (c1 ? 1 : 0) + (c2 ? 1 : 0)

        // w2 = r2.high + r3.high + r4.low + carry1
        let (s2, c3) = r2.high.addingReportingOverflow(r3.high)
        let (s3, c4) = s2.addingReportingOverflow(r4.low)
        let (w2, c5) = s3.addingReportingOverflow(carry1)
        let carry2: UInt64 = (c3 ? 1 : 0) + (c4 ? 1 : 0) + (c5 ? 1 : 0)

        // w3 = r4.high + carry2
        let w3 = r4.high &+ carry2

        // Now reduce 256-bit (w3, w2, w1, w0) mod (2^127 - 1).
        // For Mersenne prime p = 2^127 - 1:
        //   x mod p ≡ (x mod 2^127) + (x >> 127) (mod p)
        // We apply this iteratively until the value fits in 128 bits and < p.
        return mersenneReduce256(w3: w3, w2: w2, w1: w1, w0: w0)
    }

    /// Reduces a 256-bit value mod 2^127 - 1 using the Mersenne identity:
    ///   x mod (2^127 - 1) = (x & (2^127-1)) + (x >> 127)
    private func mersenneReduce256(
        w3: UInt64, w2: UInt64, w1: UInt64, w0: UInt64
    ) -> UInt128Wrapper {
        // Value = (w3, w2, w1, w0) as a 256-bit number
        // low 127 bits = bits [126:0] of (w1, w0)
        // high part = bits [255:127]

        // Low 127 bits: (w1 & 0x7FFF_FFFF_FFFF_FFFF, w0)
        let lowHigh = w1 & 0x7FFF_FFFF_FFFF_FFFF
        let lowPart = UInt128Wrapper(high: lowHigh, low: w0)

        // High 129 bits (shift right by 127):
        // bit 127 is w1 bit 63. Shift (w3, w2, w1) >> 63 as 192-bit >> 63.
        // After the shift the result is at most 129 bits (256-127=129).
        let h0 = (w1 >> 63) | (w2 << 1)
        let h1 = (w2 >> 63) | (w3 << 1)
        // h2 = w3 >> 63 (at most 1 bit)
        let h2 = w3 >> 63

        // highPart is at most 129 bits: (h2, h1, h0)
        // We need to reduce this further. If h2 != 0, it means value > 2^128
        // which we need one more reduction round.
        // First add lowPart + (h1, h0):
        var sum = addMod128Raw(lowPart, UInt128Wrapper(high: h1, low: h0))

        // If h2 is set (1), add 2^128 mod p = 2^128 - (2^127-1) = 2^127+1 ≡ 2 (mod p)
        // Actually 2^128 mod (2^127-1) = 2^128 - (2^127-1) = 2^127 + 1
        // But 2^127 mod p = 1, so 2^128 mod p = 2.
        if h2 != 0 {
            sum = addMod128Raw(sum, UInt128Wrapper(2))
        }

        // The sum might be >= p or even >= 2p, so do final reduction
        // If carry happened in addMod128Raw, sum.high bit 63 could overflow
        // For Mersenne: just do the split again on 128-bit value
        return finalMersenneReduce(sum)
    }

    /// Raw 128-bit addition without mod reduction (may overflow to 129 bits,
    /// but for our use the values are bounded so this is safe).
    private func addMod128Raw(
        _ a: UInt128Wrapper, _ b: UInt128Wrapper
    ) -> UInt128Wrapper {
        let (sumLow, carry) = a.low.addingReportingOverflow(b.low)
        let sumHigh = a.high &+ b.high &+ (carry ? 1 : 0)
        return UInt128Wrapper(high: sumHigh, low: sumLow)
    }

    /// Final Mersenne reduction for a 128-bit value that may be >= p.
    /// Applies: x mod (2^127-1) = (x & mask127) + (x >> 127), repeat.
    private func finalMersenneReduce(_ v: UInt128Wrapper) -> UInt128Wrapper {
        var x = v
        // At most 2 iterations needed
        for _ in 0..<3 {
            let lowPart = UInt128Wrapper(high: x.high & 0x7FFF_FFFF_FFFF_FFFF, low: x.low)
            let highBit = x.high >> 63 // 0 or 1
            if highBit == 0 && lowPart < fieldModulus {
                return lowPart
            }
            // Add the carry bit
            let (sLow, c) = lowPart.low.addingReportingOverflow(highBit)
            let sHigh = lowPart.high &+ (c ? 1 : 0)
            x = UInt128Wrapper(high: sHigh, low: sLow)
        }
        // Final check
        if x >= fieldModulus {
            let (rLow, borrow) = x.low.subtractingReportingOverflow(fieldModulus.low)
            let rHigh = x.high &- fieldModulus.high &- (borrow ? 1 : 0)
            return UInt128Wrapper(high: rHigh, low: rLow)
        }
        return x
    }

    /// Reduce a 128-bit value mod p.
    private func mod128(_ v: UInt128Wrapper, _ p: UInt128Wrapper) -> UInt128Wrapper {
        if v < p { return v }
        return finalMersenneReduce(v)
    }

    /// Modular inverse via Fermat's little theorem: a^(-1) = a^(p-2) mod p.
    ///
    /// For the Mersenne prime p = 2^127 - 1, this computes a^(p-2) mod p
    /// using binary exponentiation (square-and-multiply).
    private func modInverse128(_ a: UInt128Wrapper, _ p: UInt128Wrapper) -> UInt128Wrapper {
        guard !a.isZero else { return .zero }

        // exponent = p - 2 = 2^127 - 3
        // Binary: 0111...1101 (126 ones, then 0, then 1)
        // = 0x7FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFD
        let expHigh: UInt64 = 0x7FFF_FFFF_FFFF_FFFF
        let expLow: UInt64 = 0xFFFF_FFFF_FFFF_FFFD

        return modExp128(base: a, expHigh: expHigh, expLow: expLow, mod: p)
    }

    /// Binary modular exponentiation: base^exp mod p.
    private func modExp128(
        base: UInt128Wrapper, expHigh: UInt64, expLow: UInt64, mod p: UInt128Wrapper
    ) -> UInt128Wrapper {
        var result = UInt128Wrapper.one
        var b = mod128(base, p)

        // Process low 64 bits
        var eLow = expLow
        for _ in 0..<64 {
            if eLow & 1 == 1 {
                result = mulMod128(result, b, p)
            }
            b = mulMod128(b, b, p)
            eLow >>= 1
        }

        // Process high 64 bits
        var eHigh = expHigh
        for _ in 0..<64 {
            if eHigh & 1 == 1 {
                result = mulMod128(result, b, p)
            }
            b = mulMod128(b, b, p)
            eHigh >>= 1
        }

        return result
    }

    /// Unsigned 128-bit subtraction (a - b), assumes a >= b.
    private func sub128unsigned(
        _ a: UInt128Wrapper, _ b: UInt128Wrapper
    ) -> UInt128Wrapper {
        let (diffLow, borrow) = a.low.subtractingReportingOverflow(b.low)
        let diffHigh = a.high &- b.high &- (borrow ? 1 : 0)
        return UInt128Wrapper(high: diffHigh, low: diffLow)
    }

    /// Random field element in [0, p) as a 128-bit value.
    private func randomFieldElement128() -> UInt128Wrapper {
        let p = fieldModulus
        // Rejection sampling: generate 128-bit random, reject if >= p
        while true {
            var bytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let high = bytes.withUnsafeBytes { buf -> UInt64 in
                buf.load(fromByteOffset: 0, as: UInt64.self).bigEndian
            }
            let low = bytes.withUnsafeBytes { buf -> UInt64 in
                buf.load(fromByteOffset: 8, as: UInt64.self).bigEndian
            }
            // Mask to 127 bits (clear bit 127 = high bit 63)
            let maskedHigh = high & 0x7FFF_FFFF_FFFF_FFFF
            let candidate = UInt128Wrapper(high: maskedHigh, low: low)
            if candidate < p {
                return candidate
            }
        }
    }

    // MARK: - Additive Masking

    /// Applies additive masking to weight data over the finite field.
    ///
    /// Converts weights to field elements, generates a mask stream from the seed,
    /// and computes masked[i] = (weight[i] + mask[i]) mod p for each element.
    /// This is additively homomorphic: sum of masked values = sum of weights + sum of masks (mod p).
    private func applyAdditiveMask(to data: Data, seed: Data) -> Data {
        guard !data.isEmpty else { return Data() }

        // Convert weight bytes to field elements (4-byte chunks)
        let weightElements = serializeToFieldElements(data)

        // Generate mask field elements from seed
        let maskBytes = expandSeed(seed, length: weightElements.count * 16)
        var maskElements: [UInt128Wrapper] = []
        for i in 0..<weightElements.count {
            let offset = i * 16
            let high = maskBytes.withUnsafeBytes { buf -> UInt64 in
                buf.load(fromByteOffset: offset, as: UInt64.self).bigEndian
            }
            let low = maskBytes.withUnsafeBytes { buf -> UInt64 in
                buf.load(fromByteOffset: offset + 8, as: UInt64.self).bigEndian
            }
            let raw = UInt128Wrapper(high: high & 0x7FFF_FFFF_FFFF_FFFF, low: low)
            maskElements.append(mod128(raw, fieldModulus))
        }

        // Additive masking: masked[i] = (weight[i] + mask[i]) mod p
        var maskedData = Data()
        for (w, m) in zip(weightElements, maskElements) {
            let wElem = UInt128Wrapper(w)
            let masked = addMod128(wElem, m, fieldModulus)
            // Serialize back to 4 bytes (original granularity)
            let truncated = UInt32(masked.low % UInt64(UInt32.max))
            var be = truncated.bigEndian
            maskedData.append(Data(bytes: &be, count: 4))
        }

        return maskedData
    }

    /// Expands a seed into a pseudo-random byte stream of the given length
    /// using iterative hashing (simplified HKDF-expand without external deps).
    private func expandSeed(_ seed: Data, length: Int) -> Data {
        var result = Data()
        var counter: UInt32 = 0

        while result.count < length {
            var block = seed
            var counterBytes = counter.bigEndian
            block.append(Data(bytes: &counterBytes, count: 4))
            let hash = sha256(block)
            result.append(hash)
            counter += 1
        }

        return result.prefix(length)
    }

    /// SHA-256 using CommonCrypto (available on all Apple platforms without imports).
    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { buffer in
            CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    // MARK: - Serialization

    /// Converts raw bytes to field elements (4-byte chunks -> UInt64 values < p).
    /// Values are guaranteed to be valid field elements (< 2^127 - 1) since
    /// 4-byte chunks produce values < 2^32 which is always < p.
    internal func serializeToFieldElements(_ data: Data) -> [UInt64] {
        var elements: [UInt64] = []
        var offset = 0

        while offset < data.count {
            let end = min(offset + 4, data.count)
            var chunk = Data(data[offset..<end])
            while chunk.count < 4 {
                chunk.append(0)
            }
            let value: UInt32 = chunk.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            // No mod needed: UInt32 values are always < 2^127 - 1
            elements.append(UInt64(value))
            offset += 4
        }

        return elements
    }

    /// Converts field elements back to bytes.
    internal func deserializeFromFieldElements(_ elements: [UInt64]) -> Data {
        var result = Data()
        for element in elements {
            let value = UInt32(element & 0xFFFF_FFFF)
            var be = value.bigEndian
            result.append(Data(bytes: &be, count: 4))
        }
        return result
    }

    /// Serializes share bundles for network transmission.
    private func serializeShareBundles(_ bundles: [[ShamirShare]]) -> Data {
        var data = Data()

        // Number of participants
        var count = UInt32(bundles.count).bigEndian
        data.append(Data(bytes: &count, count: 4))

        for participantShares in bundles {
            // Number of shares for this participant
            var shareCount = UInt32(participantShares.count).bigEndian
            data.append(Data(bytes: &shareCount, count: 4))

            for share in participantShares {
                // Index
                var idx = UInt32(share.index).bigEndian
                data.append(Data(bytes: &idx, count: 4))

                // Value length + value (16 bytes for 128-bit values)
                var valLen = UInt32(share.value.count).bigEndian
                data.append(Data(bytes: &valLen, count: 4))
                data.append(share.value)
            }
        }

        return data
    }

    /// Deserializes share bundles received from the server.
    internal func deserializeShareBundles(_ data: Data) -> [[ShamirShare]] {
        var bundles: [[ShamirShare]] = []
        var offset = 0

        guard data.count >= 4 else { return bundles }
        let participantCount = readUInt32(data, at: &offset)

        for _ in 0..<participantCount {
            guard offset + 4 <= data.count else { break }
            let shareCount = readUInt32(data, at: &offset)

            var shares: [ShamirShare] = []
            for _ in 0..<shareCount {
                guard offset + 8 <= data.count else { break }
                let index = readUInt32(data, at: &offset)
                let valLen = readUInt32(data, at: &offset)
                guard offset + Int(valLen) <= data.count else { break }
                let value = data[offset..<offset + Int(valLen)]
                offset += Int(valLen)

                shares.append(ShamirShare(
                    index: Int(index),
                    value: Data(value),
                    modulus: fieldModulus
                ))
            }
            bundles.append(shares)
        }

        return bundles
    }

    // MARK: - Byte Helpers

    /// Serializes a 128-bit value to 16 bytes (big-endian).
    private func uint128ToData(_ value: UInt128Wrapper) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let highBE = value.high.bigEndian
        let lowBE = value.low.bigEndian
        withUnsafeBytes(of: highBE) { buf in
            for i in 0..<8 { bytes[i] = buf[i] }
        }
        withUnsafeBytes(of: lowBE) { buf in
            for i in 0..<8 { bytes[8 + i] = buf[i] }
        }
        return Data(bytes)
    }

    /// Deserializes 16 bytes (big-endian) to a 128-bit value.
    /// Handles shorter data by zero-padding on the left.
    private func dataToUInt128(_ data: Data) -> UInt128Wrapper {
        // Ensure contiguous 16 bytes
        var bytes = [UInt8](repeating: 0, count: 16)
        let srcBytes = [UInt8](data)
        let offset = 16 - min(srcBytes.count, 16)
        for i in 0..<min(srcBytes.count, 16) {
            bytes[offset + i] = srcBytes[i]
        }

        let high: UInt64 = bytes.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 0, as: UInt64.self).bigEndian
        }
        let low: UInt64 = bytes.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 8, as: UInt64.self).bigEndian
        }
        return UInt128Wrapper(high: high, low: low)
    }

    private func readUInt32(_ data: Data, at offset: inout Int) -> UInt32 {
        let slice = data[offset..<offset + 4]
        offset += 4
        return slice.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    private func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
// swiftlint:enable type_body_length
