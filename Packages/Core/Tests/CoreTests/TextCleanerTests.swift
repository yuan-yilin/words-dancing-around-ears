import XCTest
@testable import Core

final class TextCleanerTests: XCTestCase {
    func testEmptyInput() {
        XCTAssertEqual(TextCleaner.clean([]), "")
        XCTAssertEqual(TextCleaner.clean(["   ", ""]), "")
    }

    func testPageNumberRemoved() {
        let result = TextCleaner.clean(["正文开始", "12", "第 3 页", "— 45 —", "正文结束"])
        XCTAssertFalse(result.contains("12\n"))
        XCTAssertFalse(result.contains("第 3 页"))
        XCTAssertTrue(result.contains("正文开始"))
        XCTAssertTrue(result.contains("正文结束"))
    }

    func testCJKLinesJoined() {
        let result = TextCleaner.clean(["这是一段中文文本, 分成了", "两行, 需要合并。"])
        XCTAssertTrue(result.contains("这是一段中文文本, 分成了两行, 需要合并。"))
    }

    func testLatinLinesJoinedWithSpace() {
        let result = TextCleaner.clean(["Artificial Intelligence is a", "branch of computer science."])
        XCTAssertTrue(result.contains("Artificial Intelligence is a branch of computer science."))
    }

    func testHyphenationRemoved() {
        let result = TextCleaner.clean(["This is an inter-", "national project."])
        XCTAssertTrue(result.contains("international"))
        XCTAssertFalse(result.contains("inter-"))
    }

    func testParagraphBreakOnSentenceEnd() {
        let result = TextCleaner.clean(["第一段结束。", "第二段开始了。"])
        let paragraphs = result.components(separatedBy: "\n")
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0], "第一段结束。")
    }

    func testShortTitleStartsNewParagraph() {
        let result = TextCleaner.clean(["第一章", "这一章的内容开始了, 讲述一些事情。"])
        let paragraphs = result.components(separatedBy: "\n")
        XCTAssertEqual(paragraphs.first, "第一章")
    }
}
