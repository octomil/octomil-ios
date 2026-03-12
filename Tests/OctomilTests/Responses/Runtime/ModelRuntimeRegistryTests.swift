import XCTest
@testable import Octomil

final class ModelRuntimeRegistryTests: XCTestCase {

    override func tearDown() {
        ModelRuntimeRegistry.shared.clear()
        super.tearDown()
    }

    func testResolveReturnsNilWhenEmpty() {
        XCTAssertNil(ModelRuntimeRegistry.shared.resolve(modelId: "any-model"))
    }

    func testResolveExactFamilyMatch() {
        ModelRuntimeRegistry.shared.register(family: "phi-4-mini") { _ in StubRuntime() }
        XCTAssertNotNil(ModelRuntimeRegistry.shared.resolve(modelId: "phi-4-mini"))
    }

    func testResolvePrefixMatch() {
        ModelRuntimeRegistry.shared.register(family: "phi") { _ in StubRuntime() }
        XCTAssertNotNil(ModelRuntimeRegistry.shared.resolve(modelId: "phi-4-mini"))
    }

    func testResolvePrefersExactOverPrefix() {
        var usedExact = false
        ModelRuntimeRegistry.shared.register(family: "phi-4-mini") { _ in
            usedExact = true
            return StubRuntime()
        }
        ModelRuntimeRegistry.shared.register(family: "phi") { _ in StubRuntime() }
        _ = ModelRuntimeRegistry.shared.resolve(modelId: "phi-4-mini")
        XCTAssertTrue(usedExact)
    }

    func testResolveFallsBackToDefault() {
        ModelRuntimeRegistry.shared.defaultFactory = { _ in StubRuntime() }
        XCTAssertNotNil(ModelRuntimeRegistry.shared.resolve(modelId: "unknown-model"))
    }

    func testResolveReturnsNilWhenNoMatch() {
        ModelRuntimeRegistry.shared.register(family: "phi") { _ in StubRuntime() }
        XCTAssertNil(ModelRuntimeRegistry.shared.resolve(modelId: "llama-3"))
    }

    func testResolveIsCaseInsensitive() {
        ModelRuntimeRegistry.shared.register(family: "PHI") { _ in StubRuntime() }
        XCTAssertNotNil(ModelRuntimeRegistry.shared.resolve(modelId: "phi-4-mini"))
    }

    func testClearRemovesAll() {
        ModelRuntimeRegistry.shared.register(family: "phi") { _ in StubRuntime() }
        ModelRuntimeRegistry.shared.defaultFactory = { _ in StubRuntime() }
        ModelRuntimeRegistry.shared.clear()
        XCTAssertNil(ModelRuntimeRegistry.shared.resolve(modelId: "phi"))
    }
}

// MARK: - Test helpers

private final class StubRuntime: ModelRuntime, @unchecked Sendable {
    let capabilities = RuntimeCapabilities()
    func run(request: RuntimeRequest) async throws -> RuntimeResponse {
        RuntimeResponse(text: "stub")
    }
    func stream(request: RuntimeRequest) -> AsyncThrowingStream<RuntimeChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func close() {}
}
