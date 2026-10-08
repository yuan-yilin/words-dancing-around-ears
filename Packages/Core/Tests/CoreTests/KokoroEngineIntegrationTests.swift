import XCTest
@testable import Core

/// Kokoro 引擎端到端集成测试：真实加载模型并合成中文语音。
/// 前置：模型已通过 scripts/fetch-model.sh 预置（否则跳过）。
final class KokoroEngineIntegrationTests: XCTestCase {
    func testSynthesizeChineseSpeech() throws {
        guard let modelDirectory = ModelLocator.kokoroModelDirectory() else {
            throw XCTSkip("Kokoro 模型未就绪（先运行 scripts/fetch-model.sh）")
        }

        let engine = try KokoroEngine(modelDirectory: modelDirectory)

        XCTAssertEqual(engine.sampleRate, 24_000)
        XCTAssertGreaterThanOrEqual(engine.voices.count, 8, "应至少提供 8 个中文声音")
        XCTAssertTrue(engine.voices.contains { $0.name == "zf_xiaoxiao" })

        let text = "你好，这是词绕耳畔的离线语音合成测试。今天天气不错。"
        let speech = try engine.synthesize(
            text: text,
            voice: KokoroVoiceCatalog.defaultVoice
        )

        // 一句 ~24 字, 24kHz 下应在数秒音频量级
        XCTAssertGreaterThan(speech.samples.count, 24_000, "合成采样过短: \(speech.samples.count)")
        XCTAssertLessThan(speech.samples.count, 24_000 * 30)
        XCTAssertEqual(speech.sampleRate, 24_000)

        // 检查有实际能量（不是全静音）
        let peak = speech.samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.05, "音频疑似静音, 峰值 \(peak)")

        // 落盘供人工试听
        let wav = URL(fileURLWithPath: "/tmp/wordsdancing-kokoro-test.wav")
        let ok = writeWav(samples: speech.samples, sampleRate: speech.sampleRate, to: wav)
        XCTAssertTrue(ok, "wav 写入失败")
        print("试听文件: /tmp/wordsdancing-kokoro-test.wav (\(speech.duration)s)")
    }

    func testEnglishFallbackInMixedText() throws {
        guard ModelLocator.kokoroModelDirectory() != nil else {
            throw XCTSkip("Kokoro 模型未就绪")
        }
        let engine = try KokoroEngine()
        let speech = try engine.synthesize(
            text: "Mixed 中英文 test, 数字 123.",
            voice: KokoroVoiceCatalog.defaultVoice
        )
        XCTAssertGreaterThan(speech.samples.count, 24_000 / 2)
    }

    // MARK: - wav 写入（16bit PCM）

    private func writeWav(samples: [Float], sampleRate: Int32, to url: URL) -> Bool {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return false
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }
}

import AVFoundation
