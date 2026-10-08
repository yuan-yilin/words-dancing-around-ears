import Foundation

/// Kokoro 中英文 TTS 引擎（基于 sherpa-onnx）。
///
/// config 构造参照官方示例 sherpa-onnx/swift-api-examples/tts-kokoro-zh-en.swift。
public final class KokoroEngine: TTSEngine {
    private let tts: SherpaOnnxOfflineTtsWrapper

    public let sampleRate: Int32
    public let voices: [TTSVoice] = KokoroVoiceCatalog.chineseVoices

    /// 用模型目录初始化引擎（模型加载耗时且占内存, 请全局只保留一个实例）
    /// - Parameter modelDirectory: 含 model.onnx / voices.bin / tokens.txt /
    ///   lexicon-*.txt / espeak-ng-data 的目录（ModelLocator.kokoroModelDirectory()）
    public init(modelDirectory: URL) throws {
        func path(_ name: String) -> String {
            modelDirectory.appendingPathComponent(name).path
        }

        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: path("model.onnx"),
            voices: path("voices.bin"),
            tokens: path("tokens.txt"),
            dataDir: path("espeak-ng-data"),
            lexicon: path("lexicon-us-en.txt") + "," + path("lexicon-zh.txt")
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, debug: 0)
        var ttsConfig = sherpaOnnxOfflineTtsConfig(model: modelConfig)

        self.tts = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        self.sampleRate = tts.sampleRate
    }

    /// 便捷初始化：自动定位模型
    public convenience init() throws {
        guard let modelDirectory = ModelLocator.kokoroModelDirectory() else {
            throw TTSError.modelNotReady
        }
        try self.init(modelDirectory: modelDirectory)
    }

    public func synthesize(text: String, voice: TTSVoice, speed: Float = 1.0) throws -> GeneratedSpeech {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return GeneratedSpeech(samples: [], sampleRate: sampleRate)
        }

        let audio = tts.generate(text: cleaned, sid: voice.id, speed: speed)
        let samples = audio.samples
        guard !samples.isEmpty else {
            throw TTSError.synthesisFailed
        }
        return GeneratedSpeech(samples: samples, sampleRate: audio.sampleRate)
    }
}
