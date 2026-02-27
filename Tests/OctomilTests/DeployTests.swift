import XCTest
import CoreML
@testable import Octomil

final class DeployTests: XCTestCase {

    // MARK: - Engine Tests

    func testEngineRawValues() {
        XCTAssertEqual(Engine.auto.rawValue, "auto")
        XCTAssertEqual(Engine.coreml.rawValue, "coreml")
        XCTAssertEqual(Engine.mlx.rawValue, "mlx")
    }

    func testEngineCodableRoundTrip() throws {
        let original = Engine.coreml
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Engine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEngineAutoCodable() throws {
        let original = Engine.auto
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Engine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEngineDecodesFromString() throws {
        let json = Data("\"coreml\"".utf8)
        let decoded = try JSONDecoder().decode(Engine.self, from: json)
        XCTAssertEqual(decoded, .coreml)
    }

    func testEngineInvalidStringFails() {
        let json = Data("\"pytorch\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Engine.self, from: json))
    }

    func testEngineMlxCodableRoundTrip() throws {
        let original = Engine.mlx
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Engine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEngineMlxDecodesFromString() throws {
        let json = Data("\"mlx\"".utf8)
        let decoded = try JSONDecoder().decode(Engine.self, from: json)
        XCTAssertEqual(decoded, .mlx)
    }

    func testDeployWithMlxEngineThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.mlmodelc")
        try? FileManager.default.createDirectory(at: fakePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath, engine: .mlx, benchmark: false)
            XCTFail("Expected DeployError")
        } catch let error as DeployError {
            if case .unsupportedFormat(let msg) = error {
                XCTAssertTrue(msg.contains("mlx"), "Error should mention mlx")
                XCTAssertTrue(msg.contains("OctomilMLX"), "Error should mention OctomilMLX package")
            } else {
                XCTFail("Expected unsupportedFormat")
            }
        } catch {
            XCTFail("Expected DeployError, got \(type(of: error))")
        }
    }

    // MARK: - DeployError Tests

    func testUnsupportedFormatErrorDescription() {
        let error = DeployError.unsupportedFormat("pt")
        XCTAssertEqual(
            error.errorDescription,
            "Unsupported model format: .pt. Supported formats: .mlmodelc, .mlmodel, .mlpackage"
        )
    }

    func testUnsupportedFormatWithEmptyExtension() {
        let error = DeployError.unsupportedFormat("")
        XCTAssertTrue(error.errorDescription!.contains("Unsupported model format"))
    }

    func testDeployWithUnsupportedFormatThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.pt")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath)
            XCTFail("Expected DeployError")
        } catch let error as DeployError {
            if case .unsupportedFormat(let ext) = error {
                XCTAssertEqual(ext, "pt")
            } else {
                XCTFail("Expected unsupportedFormat")
            }
        } catch {
            XCTFail("Expected DeployError, got \(type(of: error))")
        }
    }

    func testDeployWithTxtFormatThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.txt")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath)
            XCTFail("Expected DeployError")
        } catch let error as DeployError {
            if case .unsupportedFormat(let ext) = error {
                XCTAssertEqual(ext, "txt")
            }
        } catch {
            XCTFail("Expected DeployError")
        }
    }

    func testDeployWithOnnxFormatThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.onnx")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath, benchmark: false)
            XCTFail("Expected DeployError")
        } catch {
            guard case DeployError.unsupportedFormat("onnx") = error else {
                XCTFail("Expected unsupportedFormat(\"onnx\"), got \(error)")
                return
            }
        }
    }

    // MARK: - DeployedModel Tests

    func testDeployedModelInitWithoutWarmup() throws {
        let warmup: WarmupResult? = nil
        let activeDelegate = warmup?.activeDelegate ?? "unknown"
        XCTAssertEqual(activeDelegate, "unknown",
                       "Without warmup, activeDelegate should be 'unknown'")

        let withWarmup = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: 10.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: ["cpu"]
        )
        XCTAssertEqual(withWarmup.activeDelegate, "neural_engine",
                       "With warmup, activeDelegate should match the provided value")
    }

    func testWarmupResultProperties() {
        let result = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: 10.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: ["cpu"]
        )

        XCTAssertEqual(result.coldInferenceMs, 50.0)
        XCTAssertEqual(result.warmInferenceMs, 5.0)
        XCTAssertEqual(result.cpuInferenceMs, 10.0)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "neural_engine")
        XCTAssertEqual(result.disabledDelegates, ["cpu"])
    }

    func testWarmupResultCPUFaster() {
        let result = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 15.0,
            cpuInferenceMs: 8.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine"]
        )

        XCTAssertFalse(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "cpu")
        XCTAssertEqual(result.disabledDelegates, ["neural_engine"])
    }

    func testWarmupResultNoCPUBaseline() {
        let result = WarmupResult(
            coldInferenceMs: 100.0,
            warmInferenceMs: 10.0,
            cpuInferenceMs: nil,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: []
        )

        XCTAssertNil(result.cpuInferenceMs)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertTrue(result.disabledDelegates.isEmpty)
    }

    // MARK: - Deploy Name Resolution Tests

    func testDeployNameFromURL() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("MyCustomModel.safetensors")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath, name: nil)
            XCTFail("Expected error")
        } catch {
            // Expected — unsupported format
        }
    }

    func testDeployCustomNamePassedThrough() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.bin")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath, name: "MyModel")
            XCTFail("Expected error")
        } catch {
            // Expected — unsupported format
        }
    }

    // MARK: - Deploy Benchmark Flag Tests

    func testDeployBenchmarkDefaultIsTrue() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("test.bin")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is DeployError)
        }
    }

    func testDeployBenchmarkFalseStillValidates() async {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("test.bin")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try await Deploy.model(at: fakePath, benchmark: false)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is DeployError)
        }
    }
}
