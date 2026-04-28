import XCTest

@testable import Octomil

final class FilesystemKeyTests: XCTestCase {
    func testPreservesValidASCII() throws {
        let key = try safeFilesystemKey("kokoro-en-v0_19")
        // ``<visible>-<12-char hash>``
        XCTAssertTrue(key.hasPrefix("kokoro-en-v0_19-"))
        XCTAssertEqual(key.count, "kokoro-en-v0_19".count + 1 + 12)
    }

    func testDeterministic() throws {
        let a = try safeFilesystemKey("kokoro-82m")
        let b = try safeFilesystemKey("kokoro-82m")
        XCTAssertEqual(a, b)
    }

    func testDisambiguatesDifferentInputsThatSanitizeAlike() throws {
        // Both sanitize to "model_v1" but the SHA-256 prefix is taken
        // over the *original* string, so the keys differ.
        let a = try safeFilesystemKey("model/v1")
        let b = try safeFilesystemKey("model\\v1")
        XCTAssertNotEqual(a, b)
    }

    func testReplacesWindowsReservedCharsWithUnderscore() throws {
        let key = try safeFilesystemKey("a<b>c:d\"e/f\\g|h?i*j")
        // Pure ASCII allowlist output.
        for char in key {
            XCTAssertTrue(char.isASCII)
        }
    }

    func testReplacesNonASCIIWithUnderscore() throws {
        let key = try safeFilesystemKey("modèle-français-🎵")
        for char in key {
            XCTAssertTrue(char.isASCII)
        }
    }

    func testCollapsesEmptyAndDotOnlyToIdHash() throws {
        XCTAssertTrue(try safeFilesystemKey("").hasPrefix("id-"))
        XCTAssertTrue(try safeFilesystemKey(".").hasPrefix("id-"))
        XCTAssertTrue(try safeFilesystemKey("..").hasPrefix("id-"))
        XCTAssertTrue(try safeFilesystemKey("   ").hasPrefix("id-"))
    }

    func testCapsVisiblePortion() throws {
        let longInput = String(repeating: "a", count: 500)
        let key = try safeFilesystemKey(longInput)
        XCTAssertLessThanOrEqual(key.count, DEFAULT_MAX_VISIBLE_CHARS + 13)
    }

    func testRejectsNULBytes() {
        XCTAssertThrowsError(try safeFilesystemKey("foo\u{0000}bar"))
    }

    func testCrossSDKConformanceForKokoro82m() throws {
        // Python and Node derive "kokoro-82m-64e5b12f9efb" for the
        // canonical Kokoro id; iOS must too so artifact dirs and
        // lock files line up across SDKs on a shared cache root.
        let key = try safeFilesystemKey("kokoro-82m")
        XCTAssertEqual(key, "kokoro-82m-64e5b12f9efb")
    }
}
