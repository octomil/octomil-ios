import XCTest
@testable import Octomil

final class InstallIdTests: XCTestCase {

    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Use a unique suite for each test to avoid cross-test contamination
        let suiteName = "ai.octomil.test.installId.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        InstallId.resetCache()
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testDefaults.description)
        testDefaults = nil
        InstallId.resetCache()
        super.tearDown()
    }

    // MARK: - Generation

    func testGeneratesUUIDOnFirstCall() {
        let id = InstallId.getOrCreate(defaults: testDefaults)
        XCTAssertFalse(id.isEmpty)
        // Should be a valid UUID format
        XCTAssertNotNil(UUID(uuidString: id), "Expected a valid UUID string, got: \(id)")
    }

    // MARK: - Persistence

    func testPersistsToUserDefaults() {
        let id = InstallId.getOrCreate(defaults: testDefaults)
        let stored = testDefaults.string(forKey: InstallId.defaultsKey)
        XCTAssertEqual(stored, id)
    }

    func testReadsExistingValue() {
        let existingId = "existing-install-id-12345"
        testDefaults.set(existingId, forKey: InstallId.defaultsKey)

        let id = InstallId.getOrCreate(defaults: testDefaults)
        XCTAssertEqual(id, existingId)
    }

    // MARK: - Stability

    func testStableAcrossCalls() {
        let first = InstallId.getOrCreate(defaults: testDefaults)
        let second = InstallId.getOrCreate(defaults: testDefaults)
        XCTAssertEqual(first, second)
    }

    func testStableAfterCacheReset() {
        let first = InstallId.getOrCreate(defaults: testDefaults)
        InstallId.resetCache()
        let second = InstallId.getOrCreate(defaults: testDefaults)
        XCTAssertEqual(first, second)
    }

    // MARK: - Cache Behavior

    func testCacheAvoidsRepeatedReads() {
        let first = InstallId.getOrCreate(defaults: testDefaults)
        // Overwrite the stored value — cached value should still be returned
        testDefaults.set("overwritten-value", forKey: InstallId.defaultsKey)
        let second = InstallId.getOrCreate(defaults: testDefaults)
        XCTAssertEqual(first, second, "Cached value should be returned even after UserDefaults changes")
    }

    func testResetCacheForcesReread() {
        let first = InstallId.getOrCreate(defaults: testDefaults)
        InstallId.resetCache()
        testDefaults.set("new-value-after-reset", forKey: InstallId.defaultsKey)
        let second = InstallId.getOrCreate(defaults: testDefaults)
        XCTAssertEqual(second, "new-value-after-reset")
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Empty Value Handling

    func testHandlesEmptyStoredValue() {
        testDefaults.set("", forKey: InstallId.defaultsKey)
        let id = InstallId.getOrCreate(defaults: testDefaults)
        // Should generate a new UUID since stored value was empty
        XCTAssertFalse(id.isEmpty)
        XCTAssertNotNil(UUID(uuidString: id))
    }

    // MARK: - OTLP Resource Integration

    func testOtlpResourceIncludesInstallId() {
        let installId = InstallId.getOrCreate(defaults: testDefaults)
        let resource = OtlpResource.fromSDK(
            deviceId: "test-device",
            orgId: "test-org",
            installId: installId
        )

        let installIdAttr = resource.attributes.first { $0.key == OTLPResourceAttribute.octomilInstallId }
        XCTAssertNotNil(installIdAttr, "Resource should contain octomil.install.id attribute")
        if case .stringValue(let value) = installIdAttr?.value {
            XCTAssertEqual(value, installId)
        } else {
            XCTFail("Expected stringValue for install.id attribute")
        }
    }

    func testOtlpResourceOmitsInstallIdWhenNil() {
        let resource = OtlpResource.fromSDK(
            deviceId: "test-device",
            orgId: "test-org",
            installId: nil
        )

        let installIdAttr = resource.attributes.first { $0.key == OTLPResourceAttribute.octomilInstallId }
        XCTAssertNil(installIdAttr, "Resource should not contain octomil.install.id when nil")
    }
}
