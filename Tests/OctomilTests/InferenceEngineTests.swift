import Foundation
import XCTest
@testable import Octomil

/// Tests for the four streaming inference engines:
/// ``LLMEngine``, ``ImageEngine``, ``AudioEngine``, ``VideoEngine``.
///
/// All engines use placeholder/simulated implementations, so these tests
/// verify chunk counts, modalities, configuration effects, and cancellation
/// without needing real model files.
final class InferenceEngineTests: XCTestCase {

    private let tempModelPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-model")

    // MARK: - LLMEngine

    func testLLMEngineGeneratesChunks() async throws {
        let engine = LLMEngine(modelPath: tempModelPath, maxTokens: 512)
        let stream = engine.generate(input: "Hello world test", modality: .text, config: GenerationConfig())

        var chunks: [InferenceChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        XCTAssertGreaterThan(chunks.count, 0)
    }

    func testLLMEngineChunksHaveTextModality() async throws {
        let engine = LLMEngine(modelPath: tempModelPath, maxTokens: 512)
        let stream = engine.generate(input: "Test prompt", modality: .text, config: GenerationConfig())

        for try await chunk in stream {
            XCTAssertEqual(chunk.modality, .text)
        }
    }

    func testLLMEngineChunksContainUTF8Data() async throws {
        let engine = LLMEngine(modelPath: tempModelPath, maxTokens: 512)
        let stream = engine.generate(input: "Sample input", modality: .text, config: GenerationConfig())

        for try await chunk in stream {
            let text = String(data: chunk.data, encoding: .utf8)
            XCTAssertNotNil(text, "Each chunk should be valid UTF-8")
        }
    }

    func testLLMEngineDefaultMaxTokens() {
        let engine = LLMEngine(modelPath: tempModelPath)
        XCTAssertEqual(engine.maxTokens, 512)
    }

    func testLLMEngineDefaultTemperature() {
        let engine = LLMEngine(modelPath: tempModelPath)
        XCTAssertEqual(engine.temperature, 0.7)
    }

    func testLLMEngineCustomConfiguration() {
        let engine = LLMEngine(modelPath: tempModelPath, maxTokens: 1024, temperature: 0.9)
        XCTAssertEqual(engine.maxTokens, 1024)
        XCTAssertEqual(engine.temperature, 0.9)
    }

    func testLLMEngineCancellation() async throws {
        let engine = LLMEngine(modelPath: tempModelPath, maxTokens: 512)
        let stream = engine.generate(input: "Long prompt for testing cancellation behavior", modality: .text, config: GenerationConfig())

        let task = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count >= 2 { break }
            }
            return count
        }

        let count = try await task.value
        XCTAssertGreaterThanOrEqual(count, 2)
    }

    func testLLMEngineChunkIndicesStartAtZero() async throws {
        let engine = LLMEngine(modelPath: tempModelPath, maxTokens: 512)
        let stream = engine.generate(input: "Index test", modality: .text, config: GenerationConfig())

        var indices: [Int] = []
        for try await chunk in stream {
            indices.append(chunk.index)
        }

        XCTAssertFalse(indices.isEmpty)
        XCTAssertEqual(indices.first, 0)
        // Verify sequential
        for i in 1..<indices.count {
            XCTAssertEqual(indices[i], indices[i - 1] + 1)
        }
    }

    // MARK: - ImageEngine

    func testImageEngineGeneratesCorrectNumberOfChunks() async throws {
        let engine = ImageEngine(modelPath: tempModelPath, steps: 5)
        let stream = engine.generate(input: "A cat", modality: .image, config: GenerationConfig())

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 5)
    }

    func testImageEngineChunksHaveImageModality() async throws {
        let engine = ImageEngine(modelPath: tempModelPath, steps: 3)
        let stream = engine.generate(input: "A dog", modality: .image, config: GenerationConfig())

        for try await chunk in stream {
            XCTAssertEqual(chunk.modality, .image)
        }
    }

    func testImageEngineDefaultSteps() {
        let engine = ImageEngine(modelPath: tempModelPath)
        XCTAssertEqual(engine.steps, 20)
    }

    func testImageEngineDefaultGuidanceScale() {
        let engine = ImageEngine(modelPath: tempModelPath)
        XCTAssertEqual(engine.guidanceScale, 7.5)
    }

    func testImageEngineCustomSteps() async throws {
        let engine = ImageEngine(modelPath: tempModelPath, steps: 3)
        let stream = engine.generate(input: "test", modality: .image, config: GenerationConfig())

        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertEqual(count, 3)
    }

    func testImageEngineCancellation() async throws {
        let engine = ImageEngine(modelPath: tempModelPath, steps: 50)
        let stream = engine.generate(input: "test", modality: .image, config: GenerationConfig())

        let task = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count >= 3 { break }
            }
            return count
        }

        let count = try await task.value
        XCTAssertGreaterThanOrEqual(count, 3)
        XCTAssertLessThan(count, 50)
    }

    // MARK: - AudioEngine

    func testAudioEngineGeneratesChunks() async throws {
        // 0.5 sec * 16000 / 1024 = ~7 frames
        let totalFrames = Int(0.5 * Double(16000) / 1024)
        let engine = AudioEngine(modelPath: tempModelPath, totalFrames: totalFrames, sampleRate: 16000)
        let stream = engine.generate(input: "audio input", modality: .audio, config: GenerationConfig())

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, totalFrames)
    }

    func testAudioEngineChunksHaveAudioModality() async throws {
        let engine = AudioEngine(modelPath: tempModelPath, totalFrames: 3, sampleRate: 16000)
        let stream = engine.generate(input: "test", modality: .audio, config: GenerationConfig())

        for try await chunk in stream {
            XCTAssertEqual(chunk.modality, .audio)
        }
    }

    func testAudioEngineChunkDataSize() async throws {
        let engine = AudioEngine(modelPath: tempModelPath, totalFrames: 3, sampleRate: 16000)
        let stream = engine.generate(input: "test", modality: .audio, config: GenerationConfig())

        for try await chunk in stream {
            // Each frame: 1024 samples * 2 bytes = 2048
            XCTAssertEqual(chunk.data.count, 1024 * 2)
        }
    }

    func testAudioEngineDefaultConfiguration() {
        let engine = AudioEngine(modelPath: tempModelPath)
        XCTAssertEqual(engine.totalFrames, 80)
        XCTAssertEqual(engine.sampleRate, 16000)
    }

    func testAudioEngineCancellation() async throws {
        let engine = AudioEngine(modelPath: tempModelPath, totalFrames: 200, sampleRate: 16000)
        let stream = engine.generate(input: "test", modality: .audio, config: GenerationConfig())

        let task = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count >= 3 { break }
            }
            return count
        }

        let count = try await task.value
        XCTAssertGreaterThanOrEqual(count, 3)
    }

    // MARK: - VideoEngine

    func testVideoEngineGeneratesCorrectFrameCount() async throws {
        let engine = VideoEngine(modelPath: tempModelPath, frameCount: 5, width: 64, height: 64)
        let stream = engine.generate(input: "video input", modality: .video, config: GenerationConfig())

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 5)
    }

    func testVideoEngineChunksHaveVideoModality() async throws {
        let engine = VideoEngine(modelPath: tempModelPath, frameCount: 3)
        let stream = engine.generate(input: "test", modality: .video, config: GenerationConfig())

        for try await chunk in stream {
            XCTAssertEqual(chunk.modality, .video)
        }
    }

    func testVideoEngineDefaultConfiguration() {
        let engine = VideoEngine(modelPath: tempModelPath)
        XCTAssertEqual(engine.frameCount, 30)
        XCTAssertEqual(engine.width, 256)
        XCTAssertEqual(engine.height, 256)
    }

    func testVideoEngineCustomConfiguration() {
        let engine = VideoEngine(modelPath: tempModelPath, frameCount: 10, width: 128, height: 128)
        XCTAssertEqual(engine.frameCount, 10)
        XCTAssertEqual(engine.width, 128)
        XCTAssertEqual(engine.height, 128)
    }

    func testVideoEngineCancellation() async throws {
        let engine = VideoEngine(modelPath: tempModelPath, frameCount: 100)
        let stream = engine.generate(input: "test", modality: .video, config: GenerationConfig())

        let task = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count >= 5 { break }
            }
            return count
        }

        let count = try await task.value
        XCTAssertGreaterThanOrEqual(count, 5)
        XCTAssertLessThan(count, 100)
    }

    func testVideoEngineChunkIndicesAreSequential() async throws {
        let engine = VideoEngine(modelPath: tempModelPath, frameCount: 4)
        let stream = engine.generate(input: "test", modality: .video, config: GenerationConfig())

        var indices: [Int] = []
        for try await chunk in stream {
            indices.append(chunk.index)
        }

        XCTAssertEqual(indices, [0, 1, 2, 3])
    }

    // MARK: - StreamingInferenceEngine protocol conformance

    func testAllEnginesConformToProtocol() {
        // Verify each engine can be assigned to the protocol type
        let engines: [StreamingInferenceEngine] = [
            LLMEngine(modelPath: tempModelPath),
            ImageEngine(modelPath: tempModelPath),
            AudioEngine(modelPath: tempModelPath),
            VideoEngine(modelPath: tempModelPath),
        ]
        XCTAssertEqual(engines.count, 4)
    }
}
