import XCTest
@testable import Octomil

final class OctomilResponsesErrorTests: XCTestCase {

    func testAuthRequiredErrorMessage() {
        let error = OctomilResponsesError.authRequired("phi-4-mini")
        XCTAssertEqual(
            error.errorDescription,
            "Cloud fallback for model 'phi-4-mini' requires authentication, but no valid token is available"
        )
    }

    func testNoRuntimeErrorMessage() {
        let error = OctomilResponsesError.noRuntime("unknown-model")
        XCTAssertEqual(
            error.errorDescription,
            "No ModelRuntime registered for model: unknown-model"
        )
    }

    func testRuntimeNotFoundErrorMessage() {
        let error = OctomilResponsesError.runtimeNotFound("Custom message")
        XCTAssertEqual(error.errorDescription, "Custom message")
    }
}
