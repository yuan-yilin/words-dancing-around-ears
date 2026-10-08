import XCTest
@testable import Core

final class LibraryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRoundtrip() {
        let store = LibraryStore(directory: tempDir)
        XCTAssertEqual(store.load().count, 0)

        var book = BookRecord(title: "三体", filePath: "/tmp/三体.pdf", pageCount: 302)
        book.currentChunkIndex = 42
        book.voiceName = "zm_yunjian"
        book.speed = 1.5
        book.lastReadAt = Date(timeIntervalSinceNow: -100)
        store.upsert(book)
        store.upsert(BookRecord(title: "人类简史", filePath: "/tmp/人类简史.pdf", pageCount: 440))

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        // 最近阅读排序: 后插入的 lastReadAt 更晚
        XCTAssertEqual(loaded.first?.title, "人类简史")

        let restored = loaded.first { $0.title == "三体" }
        XCTAssertEqual(restored?.currentChunkIndex, 42)
        XCTAssertEqual(restored?.voiceName, "zm_yunjian")
        XCTAssertEqual(restored?.speed, 1.5)
        XCTAssertEqual(restored?.pageCount, 302)
    }

    func testUpsertUpdatesExisting() {
        let store = LibraryStore(directory: tempDir)
        let book = BookRecord(title: "书", filePath: "/tmp/book.pdf")
        store.upsert(book)
        store.upsert(book) // 同 id 再存

        var modified = book
        modified.currentChunkIndex = 7
        store.upsert(modified)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.currentChunkIndex, 7)
    }

    func testRemove() {
        let store = LibraryStore(directory: tempDir)
        let a = BookRecord(title: "A", filePath: "/tmp/a.pdf")
        let b = BookRecord(title: "B", filePath: "/tmp/b.pdf")
        store.upsert(a)
        store.upsert(b)
        store.remove(id: a.id)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "B")
    }

    func testNewInstanceReadsSameFile() {
        let store1 = LibraryStore(directory: tempDir)
        store1.upsert(BookRecord(title: "持久", filePath: "/tmp/x.pdf"))

        // 另一个实例（模拟 App 重启）
        let store2 = LibraryStore(directory: tempDir)
        XCTAssertEqual(store2.load().first?.title, "持久")
    }
}
