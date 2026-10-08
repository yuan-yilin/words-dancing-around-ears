import Foundation

/// 书库中的一本书（含朗读进度）
public struct BookRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    /// 安全作用域书签（iOS / 沙盒 macOS 重新访问文件用）
    public var fileBookmark: Data?
    /// 原始路径（非沙盒 macOS 兜底）
    public var filePath: String?
    public var pageCount: Int
    /// 朗读进度：chunk 下标
    public var currentChunkIndex: Int
    /// 选用的声音（TTSVoice.name）
    public var voiceName: String
    public var speed: Float
    public var createdAt: Date
    public var lastReadAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        fileBookmark: Data? = nil,
        filePath: String? = nil,
        pageCount: Int = 0,
        currentChunkIndex: Int = 0,
        voiceName: String = KokoroVoiceCatalog.defaultVoice.name,
        speed: Float = 1.0,
        createdAt: Date = Date(),
        lastReadAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.pageCount = pageCount
        self.currentChunkIndex = currentChunkIndex
        self.voiceName = voiceName
        self.speed = speed
        self.createdAt = createdAt
        self.lastReadAt = lastReadAt
    }
}

/// 书库持久化（JSON 文件, Application Support/wordsdancing/library.json）
public final class LibraryStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "wordsdancing.library")

    public init(directory: URL? = nil, filename: String = "library.json") {
        let dir = directory ?? {
            let base = ModelLocator.appSupportModelsDirectory()
                .deletingLastPathComponent() // …/wordsdancing/
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        }()
        self.fileURL = dir.appendingPathComponent(filename)
    }

    /// 读取全部记录（按最近阅读排序）
    public func load() -> [BookRecord] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let books = try? decoder.decode([BookRecord].self, from: data) else {
                return []
            }
            return books.sorted { $0.lastReadAt > $1.lastReadAt }
        }
    }

    /// 全量保存
    public func save(_ books: [BookRecord]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(books) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 新增或更新一条记录
    public func upsert(_ book: BookRecord) {
        queue.sync {
            var books = loadLocked()
            if let index = books.firstIndex(where: { $0.id == book.id }) {
                books[index] = book
            } else {
                books.append(book)
            }
            saveLocked(books)
        }
    }

    /// 删除一条记录
    public func remove(id: UUID) {
        queue.sync {
            var books = loadLocked()
            books.removeAll { $0.id == id }
            saveLocked(books)
        }
    }

    // MARK: - 内部（须在 queue 上调用）

    private func loadLocked() -> [BookRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BookRecord].self, from: data)) ?? []
    }

    private func saveLocked(_ books: [BookRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(books) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
