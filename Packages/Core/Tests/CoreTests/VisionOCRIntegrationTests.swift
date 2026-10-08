import XCTest
import CoreText
import CoreGraphics
@testable import Core

/// Vision OCR 端到端测试：用 CoreText 渲染文字成图 → Vision 识别 → 断言还原。
/// 仅在 macOS 测试宿主有效。
final class VisionOCRIntegrationTests: XCTestCase {
    func testRecognizeRenderedChineseText() async throws {
        let image = try XCTUnwrap(
            renderText("你好世界，这是识别测试。", fontName: "PingFang SC", fontSize: 64),
            "文字渲染失败"
        )

        let ocr = VisionOCR()
        let lines = try await ocr.recognizePage(cgImage: image)
        let text = ReadingOrderProcessor.orderedText(lines)

        XCTAssertFalse(text.isEmpty, "OCR 未识别出任何文本")
        // 精确模式对渲染清晰的中文应至少命中核心词
        let containsExpected = text.contains("你好") || text.contains("世界")
        XCTAssertTrue(containsExpected, "识别结果不含预期词: \(text)")
    }

    func testRecognizeRenderedEnglishText() async throws {
        let image = try XCTUnwrap(
            renderText("HELLO WORLD 123", fontName: "Helvetica", fontSize: 64),
            "文字渲染失败"
        )

        let ocr = VisionOCR()
        let lines = try await ocr.recognizePage(cgImage: image)
        let text = ReadingOrderProcessor.orderedText(lines).uppercased()

        XCTAssertTrue(text.contains("HELLO"), "识别结果: \(text)")
        XCTAssertTrue(text.contains("123"), "识别结果: \(text)")
    }

    // MARK: - 文字渲染辅助

    private func renderText(_ text: String, fontName: String, fontSize: CGFloat) -> CGImage? {
        let width = 900, height = 200
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName(fontName as CFString, fontSize, nil),
            kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        guard let attributed = CFAttributedStringCreate(
            nil, text as CFString, attributes as CFDictionary
        ) else { return nil }
        let line = CTLineCreateWithAttributedString(attributed)

        context.textPosition = CGPoint(x: 20, y: 60)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
