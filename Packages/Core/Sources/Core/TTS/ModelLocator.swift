import Foundation

/// 模型目录定位：按优先级查找本地 Kokoro 模型。
///
/// 查找顺序：
/// 1. `~/.local/share/wordsdancing/models/kokoro-multi-lang-v1_0`（开发机, scripts/fetch-model.sh 预置）
/// 2. App 沙盒内 `Application Support/wordsdancing/models/kokoro-multi-lang-v1_0`（App 内下载后）
public enum ModelLocator {
    public static let kokoroModelName = "kokoro-multi-lang-v1_0"

    /// 模型是否已就绪（关键文件齐全）
    public static var isKokoroModelReady: Bool {
        kokoroModelDirectory() != nil
    }

    /// 返回可用的 Kokoro 模型目录, 不存在返回 nil
    public static func kokoroModelDirectory() -> URL? {
        for base in searchPaths() {
            let dir = base.appendingPathComponent(kokoroModelName, isDirectory: true)
            if isCompleteModel(at: dir) {
                return dir
            }
        }
        return nil
    }

    /// App 内下载模型的落盘目录
    public static func appSupportModelsDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base
            .appendingPathComponent("wordsdancing", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// 模型归档解压后的完整校验
    public static func isCompleteModel(at directory: URL) -> Bool {
        let fm = FileManager.default
        let required = [
            "model.onnx", "voices.bin", "tokens.txt",
            "lexicon-us-en.txt", "lexicon-zh.txt",
        ]
        for name in required {
            guard fm.fileExists(atPath: directory.appendingPathComponent(name).path) else {
                return false
            }
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(
            atPath: directory.appendingPathComponent("espeak-ng-data").path,
            isDirectory: &isDir
        ), isDir.boolValue else {
            return false
        }
        return true
    }

    private static func searchPaths() -> [URL] {
        var paths: [URL] = []

        // 1. 开发机共享目录（仅 macOS；iOS 沙盒内无意义）
        #if os(macOS)
        paths.append(
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".local/share/wordsdancing/models", isDirectory: true)
        )
        #endif

        // 2. App 沙盒 Application Support
        paths.append(appSupportModelsDirectory())

        return paths
    }
}
