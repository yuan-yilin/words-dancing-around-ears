import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Kokoro 模型下载器（App 内首次下载, 之后完全离线）。
///
/// - 下载：URLSession download delegate, 实时进度
/// - 解压：macOS 调用系统 tar；iOS 暂不支持 App 内解压（M6 接压缩库）,
///   开发期用 Mac 预置或 Xcode 拷贝进沙盒
public final class ModelDownloader: NSObject, @unchecked Sendable {
    public static let modelArchiveURL = URL(
        string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
    )!

    private let progressHandler: (Double, String) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var didFinish = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// - Parameter progress: (0..1, 阶段描述) 回调
    public init(progress: @escaping (Double, String) -> Void) {
        self.progressHandler = progress
        super.init()
    }

    /// 下载并解压到 App 沙盒模型目录
    public func downloadAndInstall() async throws {
        let destination = ModelLocator.appSupportModelsDirectory()
        let archiveURL = destination.appendingPathComponent("kokoro-model.tar.bz2")

        // 1. 下载
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.didFinish = false
            let task = self.session.downloadTask(with: Self.modelArchiveURL)
            task.resume()
        }

        // 2. 解压
        await MainActor.run { self.progressHandler(1.0, "解压模型中…") }
        #if os(macOS)
        try await Self.extractTarBZ2(archive: archiveURL, into: destination)
        #else
        throw ModelDownloadError.unsupportedOnDevice
        #endif

        // 3. 清理归档并校验
        try? FileManager.default.removeItem(at: archiveURL)
        guard ModelLocator.isKokoroModelReady else {
            throw ModelDownloadError.installIncomplete
        }
        await MainActor.run { self.progressHandler(1.0, "模型就绪") }
    }

    public func cancel() {
        session.invalidateAndCancel()
        continuation?.resume(throwing: URLError(.cancelled))
        continuation = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let text = "下载中 \(Self.format(totalBytesWritten)) / \(Self.format(totalBytesExpectedToWrite))"
        Task { @MainActor in
            self.progressHandler(fraction, text)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        didFinish = true
        let destination = ModelLocator.appSupportModelsDirectory()
            .appendingPathComponent("kokoro-model.tar.bz2")
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: ())
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // 成功时 didFinishDownloadingTo 已 resume, 只处理失败
        guard !didFinish, let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - 解压（macOS）

extension ModelDownloader {
    #if os(macOS)
    static func extractTarBZ2(archive: URL, into directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", directory.path]
        try process.run()
        let status = await process.waitUntilExitAsync()
        guard status == 0 else {
            throw ModelDownloadError.extractFailed
        }
    }
    #endif

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public enum ModelDownloadError: Error, LocalizedError {
    case extractFailed
    case installIncomplete
    case unsupportedOnDevice

    public var errorDescription: String? {
        switch self {
        case .extractFailed: return "模型解压失败"
        case .installIncomplete: return "模型文件不完整"
        case .unsupportedOnDevice: return "iOS 端暂不支持 App 内解压模型，请先用 Mac 预置（M6 支持端内安装）"
        }
    }
}

#if canImport(AppKit)
extension Process {
    func waitUntilExitAsync() async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [self] in
                waitUntilExit()
                continuation.resume(returning: terminationStatus)
            }
        }
    }
}
#endif
