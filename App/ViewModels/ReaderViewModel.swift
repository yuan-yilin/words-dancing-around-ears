import Foundation
import Core
import PDFKit
import Observation

/// 朗读流水线编排：
///
/// ```
/// 文本 → TextChunker 分段
///        → 播放 chunk N（PCMChunkPlayer）
///            ‖ 同时后台合成 chunk N+1（KokoroEngine）
///        → N 播完无缝衔接 N+1（预生成）
/// ```
@Observable
final class ReaderViewModel {
    // MARK: - 状态

    private(set) var chunks: [String] = []
    private(set) var currentChunkIndex = 0
    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var isGenerating = false
    private(set) var isEngineLoading = false
    private(set) var errorMessage: String?

    var voice: TTSVoice = KokoroVoiceCatalog.defaultVoice
    var speed: Float = 1.0

    /// 当前正在朗读的 chunk 文本（供 UI 高亮）
    private(set) var currentChunkText = ""

    // MARK: - 引擎与播放器

    private var engine: KokoroEngine?
    private let player = PCMChunkPlayer()
    /// 下一个需要「合成并入队」的 chunk 下标
    private var nextToEnqueue = 0
    private var generationTask: Task<Void, Never>?

    // MARK: - 文本准备

    /// 用整书文本建立播放队列（重置进度）
    func load(text: String) {
        stop()
        chunks = TextChunker.chunks(from: text)
        nextToEnqueue = 0
        currentChunkIndex = 0
        currentChunkText = chunks.first ?? ""
    }

    var totalChunks: Int { chunks.count }

    // MARK: - 播放控制

    func play() {
        if isPaused {
            try? player.resume()
            isPaused = false
            isPlaying = true
            return
        }
        guard !chunks.isEmpty else { return }

        errorMessage = nil

        // 确保引擎就绪（首次加载模型约数秒）
        let readyEngine: KokoroEngine
        if let engine {
            readyEngine = engine
        } else {
            isEngineLoading = true
            do {
                readyEngine = try KokoroEngine()
                engine = readyEngine
            } catch {
                errorMessage = error.localizedDescription
                isEngineLoading = false
                return
            }
            isEngineLoading = false
        }

        do {
            try player.activate(sampleRate: readyEngine.sampleRate)
        } catch {
            errorMessage = "音频会话启动失败：\(error.localizedDescription)"
            return
        }

        player.onChunkFinished = { [weak self] index in
            self?.handleChunkFinished(index)
        }
        player.onAllFinished = { [weak self] in
            self?.handleAllFinished()
        }

        isPlaying = true
        isPaused = false

        // 启动流水线：预生成并依次入队
        advancePipeline()
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        player.pause()
        isPaused = true
    }

    func stop() {
        generationTask?.cancel()
        player.onChunkFinished = nil
        player.onAllFinished = nil
        player.stop()
        nextToEnqueue = 0
        isPlaying = false
        isPaused = false
        isGenerating = false
    }

    /// 跳到指定 chunk 播放
    func jump(to index: Int) {
        guard chunks.indices.contains(index) else { return }
        stop()
        currentChunkIndex = index
        nextToEnqueue = index
        currentChunkText = chunks[index]
        play()
    }

    // MARK: - 流水线

    /// 生成 nextToEnqueue 并入队, 同时预生成后续 chunk（保持播放队列里有 1 个备播）
    private func advancePipeline() {
        guard isPlaying, nextToEnqueue < chunks.count else { return }

        let index = nextToEnqueue
        nextToEnqueue += 1
        let text = chunks[index]
        let voice = voice
        let speed = speed

        isGenerating = true
        generationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self, let engine = self.engine else { return }
            do {
                let speech = try engine.synthesize(text: text, voice: voice, speed: speed)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.player.enqueue(samples: speech.samples)
                    self.isGenerating = self.nextToEnqueue < self.chunks.count
                    // 入队成功即预生成下一个, 保证流水线不断流
                    if self.isPlaying && self.nextToEnqueue < self.chunks.count {
                        self.advancePipeline()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleChunkFinished(_ index: Int) {
        currentChunkIndex = index + 1
        if chunks.indices.contains(currentChunkIndex) {
            currentChunkText = chunks[currentChunkIndex]
        }
    }

    private func handleAllFinished() {
        isPlaying = false
        isPaused = false
        currentChunkIndex = 0
        nextToEnqueue = 0
        if chunks.indices.contains(0) {
            currentChunkText = chunks[0]
        }
    }
}
