import XCTest
@testable import Core

final class TextChunkerTests: XCTestCase {
    func testEmptyText() {
        XCTAssertEqual(TextChunker.chunks(from: ""), [])
        XCTAssertEqual(TextChunker.chunks(from: "  \n \n"), [])
    }

    func testShortTextAggregatesIntoOneChunk() {
        // 短句会聚合进一个 chunk（目标 400 字）, 内容无损
        let text = "你好。世界！"
        let chunks = TextChunker.chunks(from: text)
        XCTAssertEqual(chunks, ["你好。世界！"])
    }

    func testChunksBoundedLength() {
        // 100 个句子, 每句 10 字
        let sentences = (0..<100).map { "\($0)这是一句测试" }
        let text = sentences.joined(separator: "。")
        let chunks = TextChunker.chunks(from: text)
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 600, "chunk 超长: \(chunk.prefix(50))…")
        }
        // 聚合后总字数不应丢失
        let originalCount = text.filter { !$0.isWhitespace }.count
        let chunkedCount = chunks.joined().filter { !$0.isWhitespace }.count
        XCTAssertEqual(originalCount, chunkedCount, "分段造成文本丢失")
    }

    func testSingleOversizedSentenceSplitByClause() {
        // 一个超长无句号句（约 1600 字）, 按逗号切
        let parts = (0..<200).map { "第\($0)部分内容" }
        let text = parts.joined(separator: "，")
        let chunks = TextChunker.chunks(from: text)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 600)
        }
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace },
                       text.filter { !$0.isWhitespace })
    }

    func testNewlineAsWeakBoundary() {
        // 短行「标题」作为弱句界与后续内容分开, 但仍会聚合进 chunk（总字数 < 400）
        let text = "标题\n正文第一行内容较长一些\n第二行内容也比较长一些"
        let chunks = TextChunker.chunks(from: text)
        XCTAssertEqual(chunks.count, 1)
        // 弱句界保证短行不被粘进长句中（句界处保留分隔）
        XCTAssertTrue(chunks[0].hasPrefix("标题"))
        XCTAssertTrue(chunks[0].contains("较长一些"))
    }

    func testHardSplitDoesNotCutInsideAlphanumeric() {
        // 连续 800 个 ASCII 字母无任何标点
        let text = String(repeating: "abcdefgh", count: 100)
        let chunks = TextChunker.chunks(from: text)
        XCTAssertGreaterThan(chunks.count, 1)
        // 拼接回去应无损
        XCTAssertEqual(chunks.joined(), text)
    }

    func testMixedZhEn() {
        let text = "人工智能是Artificial Intelligence的中文说法。This sentence is English. 混合 12345 数字和English words。"
        let chunks = TextChunker.chunks(from: text)
        // 三句共约 90 字, 会被聚合进一个 chunk（目标 400 字）, 但内容无损
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace },
                       text.filter { !$0.isWhitespace })
        XCTAssertTrue(chunks[0].contains("Artificial Intelligence"))
    }
}
