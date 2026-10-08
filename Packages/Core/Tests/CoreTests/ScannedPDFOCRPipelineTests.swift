import XCTest
import PDFKit
import AppKit
@testable import Core

/// M4 端到端：生成无文字层的「扫描式 PDF」→ PDFOCRPipeline → 断言文本还原。
final class ScannedPDFOCRPipelineTests: XCTestCase {
    func testScannedPDFEndToEnd() async throws {
        // 1. 用位图页面构造无文字层 PDF
        let page1 = try XCTUnwrap(
            PDFPage(image: renderTextImage("这是第一页的内容。人工智能很有趣。"))
        )
        let page2 = try XCTUnwrap(
            PDFPage(image: renderTextImage("第二页讲语音合成技术。谢谢收听。"))
        )
        let document = PDFDocument()
        document.insert(page1, at: 0)
        document.insert(page2, at: 1)

        // 2. 提取：两页都应判定为扫描页
        let pages = PDFTextExtractor.extractPages(from: document)
        XCTAssertTrue(pages.allSatisfy(\.isLikelyScanned), "位图 PDF 应判定为扫描页")

        // 3. 跑 OCR 管线（带进度回调）
        var progressCalls: [(Int, Int)] = []
        let result = await PDFOCRPipeline.process(
            document: document,
            pages: pages,
            progress: { done, total in progressCalls.append((done, total)) }
        )

        // 4. 断言
        XCTAssertEqual(progressCalls.count, 2)
        XCTAssertEqual(progressCalls.last?.1, 2)
        XCTAssertEqual(progressCalls.last?.0, 2)

        let text1 = result[0].text
        let text2 = result[1].text
        XCTAssertTrue(text1.contains("第一页") || text1.contains("人工智能"), "第 1 页识别: \(text1)")
        XCTAssertTrue(text2.contains("语音合成") || text2.contains("第二页"), "第 2 页识别: \(text2)")
        XCTAssertFalse(result[0].isLikelyScanned, "OCR 后不再是扫描页")
    }

    // MARK: - 文字渲染（无文字层, 仅位图）

    private func renderTextImage(_ text: String) -> NSImage {
        let size = CGSize(width: 900, height: 160)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "PingFang SC", size: 56) ?? NSFont.systemFont(ofSize: 56),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(
            at: NSPoint(x: 30, y: 50),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }
}
