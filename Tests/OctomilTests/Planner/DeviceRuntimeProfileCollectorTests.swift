import Foundation
import XCTest
@testable import Octomil

final class DeviceRuntimeProfileCollectorTests: XCTestCase {

    // MARK: - Profile Collection

    func testCollectReturnsValidProfile() {
        let profile = DeviceRuntimeProfileCollector.collect()

        XCTAssertEqual(profile.sdk, "ios")
        XCTAssertEqual(profile.sdkVersion, OctomilVersion.current)
        XCTAssertFalse(profile.platform.isEmpty)
        XCTAssertFalse(profile.arch.isEmpty)
        XCTAssertNotNil(profile.osVersion)
        XCTAssertNotNil(profile.chip)
        XCTAssertNotNil(profile.ramTotalBytes)
        XCTAssertGreaterThan(profile.ramTotalBytes ?? 0, 0)
    }

    func testCollectDoesNotAssumeCoreMLRuntime() {
        let profile = DeviceRuntimeProfileCollector.collect()

        XCTAssertTrue(
            profile.installedRuntimes.isEmpty,
            "CoreML framework availability alone is not a model-capable Octomil runtime"
        )
    }

    func testCollectIncludesAdditionalRuntimes() {
        let extra = [
            InstalledRuntime(engine: "mlx", version: "0.30.0", available: true, accelerator: "metal"),
            InstalledRuntime(engine: "llamacpp", version: "b2000", available: true),
        ]

        let profile = DeviceRuntimeProfileCollector.collect(additionalRuntimes: extra)

        let engines = Set(profile.installedRuntimes.map { $0.engine })
        XCTAssertTrue(engines.contains("mlx-lm"))
        XCTAssertTrue(engines.contains("llama.cpp"))
        XCTAssertEqual(profile.installedRuntimes.count, 2)
    }

    // MARK: - Platform Detection

    func testPlatformName() {
        let name = DeviceRuntimeProfileCollector.platformName()
        #if os(iOS)
        XCTAssertEqual(name, "iOS")
        #elseif os(macOS)
        XCTAssertEqual(name, "macOS")
        #endif
    }

    func testCpuArchitecture() {
        let arch = DeviceRuntimeProfileCollector.cpuArchitecture()
        #if arch(arm64)
        XCTAssertEqual(arch, "arm64")
        #elseif arch(x86_64)
        XCTAssertEqual(arch, "x86_64")
        #endif
    }

    func testOsVersionNotEmpty() {
        let version = DeviceRuntimeProfileCollector.osVersion()
        XCTAssertFalse(version.isEmpty)
    }

    func testMachineIdentifierNotEmpty() {
        let machine = DeviceRuntimeProfileCollector.machineIdentifier()
        XCTAssertFalse(machine.isEmpty)
        XCTAssertNotEqual(machine, "unknown")
    }

    // MARK: - Hardware

    func testTotalRAMBytesPositive() {
        let ram = DeviceRuntimeProfileCollector.totalRAMBytes()
        XCTAssertGreaterThan(ram, 0)
    }

    // MARK: - Accelerators

    func testDetectAccelerators() {
        let accels = DeviceRuntimeProfileCollector.detectAccelerators()
        #if arch(arm64)
        XCTAssertTrue(accels.contains("metal"))
        XCTAssertTrue(accels.contains("ane"))
        #endif
    }

    // MARK: - Core Runtimes

    func testDetectCoreRuntimesDoesNotReportFrameworkAvailability() {
        let runtimes = DeviceRuntimeProfileCollector.detectCoreRuntimes()
        XCTAssertTrue(runtimes.isEmpty)
    }

    // MARK: - Privacy: No User Data

    func testProfileContainsNoUserData() {
        let profile = DeviceRuntimeProfileCollector.collect()

        // Verify no user-identifiable information is present.
        // The profile should only contain hardware/software metadata.
        // Machine identifier (e.g. "MacBookPro18,1") is a model identifier,
        // not a unique device fingerprint.
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(profile),
              let jsonStr = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to encode profile")
            return
        }

        // Should not contain home directory path
        let home = NSHomeDirectory()
        XCTAssertFalse(jsonStr.contains(home), "Profile should not contain home directory path")

        // Should not contain UUID-style device identifiers
        // (IDFV patterns like 8-4-4-4-12 hex)
        let uuidPattern = try! NSRegularExpression(
            pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        )
        let matches = uuidPattern.numberOfMatches(
            in: jsonStr,
            range: NSRange(jsonStr.startIndex..., in: jsonStr)
        )
        XCTAssertEqual(matches, 0, "Profile should not contain UUID device identifiers")
    }
}
