import Foundation
import SwiftUI
import PDFKit
import Core
import Observation

/// 全局应用模型：书库、当前书、OCR、进度持久化、模型下载。
@MainActor
@Observable
final class AppModel {
    // MARK: - 书库

    private(set) var books: [BookRecord] = []
    private let store = LibraryStore()

    // MARK: - 当前书与阅读状态

    private(set) var currentBook: BookRecord?
    private(set) var document: PDFDocument?
    private(set) var documentURL: URL?
    private(set) var pages: [PDFPageText] = []
    private(set) var selectedPage: PDFPageText?

    /// OCR 进度（total == 0 表示未在跑）
    private(set) var ocrDone = 0
    private(set) var ocrTotal = 0
    private(set) var errorMessage: String?

    /// 文件选择器由根视图 ContentView 统一呈现（避免与 alert 同层级互相卡死）
    var showImporter = false

    func clearError() {
        errorMessage = nil
    }

    /// 延迟展示错误（不能在 fileImporter 关闭动画期间弹 alert, 会卡死后续呈现）
    private func reportError(_ message: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.errorMessage = message
        }
    }

    let readerVM = ReaderViewModel()
    private var ocrTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    // MARK: - 模型下载

    private(set) var isModelReady = ModelLocator.isKokoroModelReady
    private(set) var modelDownloadProgress: Double = 0
    private(set) var modelDownloadStatus = ""
    private(set) var isModelDownloading = false
    private var modelDownloader: ModelDownloader?

    // MARK: - 初始化

    init() {
        books = store.load()
        readerVM.onProgressChanged = { [weak self] chunkIndex in
            self?.scheduleProgressSave(chunkIndex: chunkIndex)
        }
    }

    var isReading: Bool { currentBook != nil }

    // MARK: - 打开/关闭书

    /// 从文件导入新书并打开
    func importPDF(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            // 物化 iCloud 文件（触发完整下载）并拷贝进 App 存储
            let title = url.deletingPathExtension().lastPathComponent
            let localURL = try materializePDF(from: url, title: title)

            guard let doc = PDFDocument(url: localURL) else {
                throw PDFExtractionError.cannotOpenDocument
            }
            let record = BookRecord(
                title: title,
                fileBookmark: try? localURL.bookmarkData(),
                filePath: localURL.path,
                pageCount: doc.pageCount
            )
            open(document: doc, url: localURL, record: record)
        } catch {
            reportError("导入失败：\(error.localizedDescription)")
        }
    }

    /// 拷贝 PDF 到 App 内部书库目录（NSFileCoordinator 会等待 iCloud 下载完成）
    private func materializePDF(from source: URL, title: String) throws -> URL {
        let fm = FileManager.default
        let booksDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books", isDirectory: true)
        try fm.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let destination = booksDir
            .appendingPathComponent("\(title)-\(UUID().uuidString.prefix(8)).pdf")
        try? fm.removeItem(at: destination)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: source,
            options: [],
            error: &coordinationError
        ) { sourceURL in
            do {
                try fm.copyItem(at: sourceURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = copyError ?? coordinationError as? Error {
            throw error
        }
        // 简单校验：拷贝出来的文件应该能解析出页面
        guard let probe = PDFDocument(url: destination), probe.pageCount > 0 else {
            try? fm.removeItem(at: destination)
            throw PDFExtractionError.cannotOpenDocument
        }
        return destination
    }

    /// 打开书库中的书（进度恢复）
    func openBook(_ book: BookRecord) {
        var record = book
        // 优先书签, 兜底原始路径（非沙盒 macOS）
        var url: URL?
        if let data = record.fileBookmark {
            var stale = false
            url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        }
        if url == nil, let path = record.filePath {
            url = URL(fileURLWithPath: path)
        }
        guard let url, let doc = PDFDocument(url: url) else {
            reportError("无法访问「\(record.title)」的文件（可能已移动或删除）")
            return
        }
        record.lastReadAt = Date()
        open(document: doc, url: url, record: record)
    }

    /// 关闭当前书（保存进度）
    func closeBook() {
        saveProgressNow()
        readerVM.stop()
        currentBook = nil
        document = nil
        documentURL = nil
        pages = []
        selectedPage = nil
    }

    func deleteBook(_ book: BookRecord) {
        store.remove(id: book.id)
        books = store.load()
        if book.id == currentBook?.id {
            closeBook()
        }
    }

    // MARK: - 进度持久化

    /// 延迟 1s 合并保存（朗读换段频繁触发时避免 IO 洪泛）
    private func scheduleProgressSave(chunkIndex: Int) {
        saveTask?.cancel()
        let book = currentBook
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writeProgress(bookID: book?.id, chunkIndex: chunkIndex)
        }
    }

    func saveProgressNow() {
        writeProgress(bookID: currentBook?.id, chunkIndex: readerVM.currentChunkIndex)
    }

    private func writeProgress(bookID: UUID?, chunkIndex: Int) {
        guard let id = bookID,
              var record = books.first(where: { $0.id == id }) else { return }
        let changed = record.currentChunkIndex != chunkIndex
            || record.voiceName != readerVM.voice.name
            || record.speed != readerVM.speed
        record.currentChunkIndex = chunkIndex
        record.voiceName = readerVM.voice.name
        record.speed = readerVM.speed
        record.lastReadAt = Date()
        if changed {
            store.upsert(record)
            books = store.load()
        }
    }

    // MARK: - 打开内部流程

    private func open(document: PDFDocument, url: URL, record: BookRecord) {
        ocrTask?.cancel()
        ocrDone = 0
        ocrTotal = 0
        errorMessage = nil

        #if canImport(MediaPlayer)
        NowPlayingBridge.shared.reader = readerVM
        #endif

        self.document = document
        self.documentURL = url
        self.currentBook = record
        self.pages = PDFTextExtractor.extractPages(from: document)
        self.selectedPage = pages.first

        // 恢复声音/语速/进度
        let savedVoice = KokoroVoiceCatalog.chineseVoices.first {
            $0.name == record.voiceName
        } ?? KokoroVoiceCatalog.defaultVoice
        readerVM.voice = savedVoice
        readerVM.speed = record.speed

        reloadReadingText()
        store.upsert(record)
        books = store.load()

        // 恢复到上次进度（不自动播放）
        if record.currentChunkIndex > 0,
           readerVM.totalChunks > record.currentChunkIndex {
            readerVM.restoreProgress(chunkIndex: record.currentChunkIndex)
        }

        // 含扫描页则自动 OCR
        if pages.contains(where: \.isLikelyScanned) {
            startOCR(document: document)
        }
    }

    /// 把当前页面文本（含 OCR 结果）装载进朗读器
    private func reloadReadingText() {
        let fullText = pages
            .filter { !$0.isLikelyScanned }
            .map(\.text)
            .joined(separator: "\n")
        readerVM.load(text: fullText)
    }

    /// 后台跑 OCR, 完成后替换扫描页文本并重新装载
    private func startOCR(document: PDFDocument) {
        ocrTask?.cancel()
        ocrTotal = pages.filter(\.isLikelyScanned).count
        ocrDone = 0
        let sourcePages = pages

        ocrTask = Task { [weak self] in
            let result = await PDFOCRPipeline.process(
                document: document,
                pages: sourcePages
            ) { done, total in
                self?.ocrDone = done
                self?.ocrTotal = total
            }
            guard !Task.isCancelled else { return }
            self?.pages = result
            self?.reloadReadingText()
            self?.ocrDone = 0
            self?.ocrTotal = 0
        }
    }

    func cancelOCR() {
        ocrTask?.cancel()
        ocrDone = 0
        ocrTotal = 0
    }

    // MARK: - 模型下载

    /// App 内下载并安装 Kokoro 模型（macOS 全流程; iOS 提示用 Mac 预置）
    func downloadModel() {
        guard !isModelDownloading else { return }
        isModelDownloading = true
        modelDownloadProgress = 0
        modelDownloadStatus = "准备下载…"

        let downloader = ModelDownloader { [weak self] fraction, status in
            self?.modelDownloadProgress = fraction
            self?.modelDownloadStatus = status
        }
        modelDownloader = downloader

        Task {
            do {
                try await downloader.downloadAndInstall()
                isModelReady = ModelLocator.isKokoroModelReady
                modelDownloadStatus = "模型就绪"
            } catch {
                if (error as? URLError)?.code != .cancelled {
                    errorMessage = "模型下载失败：\(error.localizedDescription)"
                }
                modelDownloadStatus = ""
            }
            isModelDownloading = false
        }
    }

    func cancelModelDownload() {
        modelDownloader?.cancel()
        isModelDownloading = false
        modelDownloadStatus = ""
    }
}
