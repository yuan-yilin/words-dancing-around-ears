import XCTest
@testable import Core

final class ReadingOrderProcessorTests: XCTestCase {
    private func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.3, h: CGFloat = 0.03) -> OCRLine {
        OCRLine(text: text, rect: CGRect(x: x, y: y, width: w, height: h))
    }

    func testEmpty() {
        XCTAssertEqual(ReadingOrderProcessor.orderedLines([]), [])
    }

    func testSingleColumnTopToBottom() {
        let lines = [
            line("第三行", x: 0.1, y: 0.5),
            line("第一行", x: 0.1, y: 0.1),
            line("第二行", x: 0.1, y: 0.3),
        ]
        let ordered = ReadingOrderProcessor.orderedLines(lines)
        XCTAssertEqual(ordered.map(\.text), ["第一行", "第二行", "第三行"])
    }

    func testSameRowSortedByX() {
        // 同一视觉行的两段, 按从左到右
        let lines = [
            line("右", x: 0.5, y: 0.1, w: 0.2),
            line("左", x: 0.1, y: 0.12, w: 0.2),
        ]
        let ordered = ReadingOrderProcessor.orderedLines(lines)
        XCTAssertEqual(ordered.map(\.text), ["左", "右"])
    }

    func testTwoColumns() {
        // 双栏: 左栏 3 行, 右栏 2 行, 交错输入
        let lines = [
            line("A1", x: 0.08, y: 0.1),
            line("B1", x: 0.58, y: 0.12),
            line("A2", x: 0.08, y: 0.3),
            line("A3", x: 0.08, y: 0.5),
            line("B2", x: 0.58, y: 0.32),
        ]
        let ordered = ReadingOrderProcessor.orderedLines(lines)
        XCTAssertEqual(ordered.map(\.text), ["A1", "A2", "A3", "B1", "B2"])
    }

    func testThreeColumns() {
        // 三栏, 每行只占栏宽的一部分（真实 OCR 行不会撑满整栏）
        let lines = [
            line("C1", x: 0.72, y: 0.1, w: 0.2),
            line("A1", x: 0.05, y: 0.1, w: 0.2),
            line("B1", x: 0.38, y: 0.1, w: 0.2),
            line("C2", x: 0.72, y: 0.4, w: 0.2),
            line("A2", x: 0.05, y: 0.4, w: 0.2),
            line("B2", x: 0.38, y: 0.4, w: 0.2),
        ]
        let ordered = ReadingOrderProcessor.orderedLines(lines)
        XCTAssertEqual(ordered.map(\.text), ["A1", "A2", "B1", "B2", "C1", "C2"])
    }

    func testShortLineDoesNotCreateFalseColumn() {
        // 页脚一条短行居中, 不应触发分栏（右侧纵向覆盖不足）
        var lines: [OCRLine] = []
        for i in 0..<10 {
            lines.append(line("正文\(i)", x: 0.08, y: 0.05 + CGFloat(i) * 0.06, w: 0.6))
        }
        lines.append(line("页脚", x: 0.45, y: 0.92, w: 0.1))
        let ordered = ReadingOrderProcessor.orderedLines(lines)
        XCTAssertEqual(ordered.last?.text, "页脚")
        XCTAssertEqual(ordered.count, 11)
    }
}
