import Foundation
import AVFoundation

/// Float32 PCM 播放器（AVAudioEngine + AVAudioPlayerNode）。
///
/// playerNode 以源采样率（Kokoro 24000Hz）连接到 mainMixerNode，
/// 引擎自动完成采样率转换。多个 chunk 依次排队播放，
/// 配合 ReaderViewModel 形成「播放 N 时后台合成 N+1」的流水线。
public final class PCMChunkPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// 播放节点格式（Float32, 单声道, 源采样率）——activate 后有效
    private(set) var format: AVAudioFormat?

    private let stateQueue = DispatchQueue(label: "wordsdancing.player.state")
    private var scheduledCount = 0
    private var finishedCount = 0
    private var paused = false

    /// 一个 chunk 播放完毕回调（主线程）
    public var onChunkFinished: ((Int) -> Void)?
    /// 排队内容全部播完回调（主线程）
    public var onAllFinished: (() -> Void)?

    public init() {}

    // MARK: - 会话/引擎管理

    /// 激活音频会话并启动引擎（每个播放会话调用一次）
    public func activate(sampleRate: Int32) throws {
        let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!

        if format != srcFormat {
            engine.stop()
            engine.reset()
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: srcFormat)
            format = srcFormat
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        #endif

        scheduledCount = 0
        finishedCount = 0
        if !engine.isRunning {
            try engine.start()
        }
        if !playerNode.isPlaying && !paused {
            playerNode.play()
        }
    }

    // MARK: - 队列操作

    /// 排队一段采样（线程安全；空的采样会被忽略, 不会计入调度数）
    public func enqueue(samples: [Float]) {
        guard !samples.isEmpty, let format else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channel[0].update(from: src.baseAddress!, count: samples.count)
            }
        }

        let index = stateQueue.sync {
            scheduledCount += 1
            return scheduledCount - 1
        }
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleChunkCompletion(index: index)
            }
        }
    }

    public func pause() {
        paused = true
        playerNode.pause()
    }

    public func resume() throws {
        guard paused else { return }
        if !engine.isRunning {
            try engine.start()
        }
        playerNode.play()
        paused = false
    }

    /// 停止并清空未播内容
    public func stop() {
        playerNode.stop()
        stateQueue.sync {
            scheduledCount = 0
            finishedCount = 0
        }
        paused = false
    }

    public var isPlaying: Bool {
        playerNode.isPlaying
    }

    public var isPaused: Bool {
        paused
    }

    /// 已排队未播完的 chunk 数
    public var pendingChunkCount: Int {
        stateQueue.sync { scheduledCount - finishedCount }
    }

    // MARK: - 内部

    private func handleChunkCompletion(index: Int) {
        stateQueue.sync {
            finishedCount += 1
        }
        onChunkFinished?(index)
        let remaining = stateQueue.sync { scheduledCount - finishedCount }
        if remaining == 0 && !isPlaying {
            onAllFinished?()
        }
    }
}
