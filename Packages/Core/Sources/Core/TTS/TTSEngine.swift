import Foundation

/// TTS 语音（说话人）
public struct TTSVoice: Identifiable, Hashable, Sendable {
    /// kokoro 模型的 speaker id
    public let id: Int
    /// 内部名（如 zf_xiaobei）
    public let name: String
    /// 界面显示名
    public let displayName: String
    /// zh / en
    public let language: String

    public init(id: Int, name: String, displayName: String, language: String) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.language = language
    }
}

/// 合成结果：Float32 PCM 采样 + 采样率
public struct GeneratedSpeech {
    public let samples: [Float]
    public let sampleRate: Int32

    public init(samples: [Float], sampleRate: Int32) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// 时长（秒）
    public var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0
    }
}

public enum TTSError: Error, LocalizedError {
    case modelNotReady
    case synthesisFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "TTS 模型未就绪，请先下载 Kokoro 模型"
        case .synthesisFailed:
            return "语音合成失败"
        }
    }
}

/// TTS 引擎抽象：将来可替换为 Piper / Supertonic / AVSpeechSynthesizer 等实现
public protocol TTSEngine {
    /// 输出音频采样率
    var sampleRate: Int32 { get }
    /// 可用声音列表
    var voices: [TTSVoice] { get }
    /// 同步合成一段文本（调用方负责放后台线程）
    func synthesize(text: String, voice: TTSVoice, speed: Float) throws -> GeneratedSpeech
}

/// Kokoro 中英文声音目录（kokoro-multi-lang-v1_0, 共 53 speakers）
/// speaker id 对照: sherpa-onnx/scripts/kokoro/v1.0/generate_voices_bin.py
public enum KokoroVoiceCatalog {
    public static let chineseVoices: [TTSVoice] = [
        TTSVoice(id: 45, name: "zf_xiaobei", displayName: "晓贝（女）", language: "zh"),
        TTSVoice(id: 46, name: "zf_xiaoni", displayName: "晓妮（女）", language: "zh"),
        TTSVoice(id: 47, name: "zf_xiaoxiao", displayName: "晓晓（女）", language: "zh"),
        TTSVoice(id: 48, name: "zf_xiaoyi", displayName: "晓伊（女）", language: "zh"),
        TTSVoice(id: 49, name: "zm_yunjian", displayName: "云健（男）", language: "zh"),
        TTSVoice(id: 50, name: "zm_yunxi", displayName: "云希（男）", language: "zh"),
        TTSVoice(id: 51, name: "zm_yunxia", displayName: "云夏（男）", language: "zh"),
        TTSVoice(id: 52, name: "zm_yunyang", displayName: "云扬（男）", language: "zh"),
    ]

    public static let englishVoices: [TTSVoice] = [
        TTSVoice(id: 2, name: "af_bella", displayName: "Bella（女）", language: "en"),
        TTSVoice(id: 3, name: "af_heart", displayName: "Heart（女）", language: "en"),
        TTSVoice(id: 16, name: "am_michael", displayName: "Michael（男）", language: "en"),
        TTSVoice(id: 18, name: "am_puck", displayName: "Puck（男）", language: "en"),
    ]

    public static let defaultVoice = TTSVoice(
        id: 47, name: "zf_xiaoxiao", displayName: "晓晓（女）", language: "zh"
    )
}
