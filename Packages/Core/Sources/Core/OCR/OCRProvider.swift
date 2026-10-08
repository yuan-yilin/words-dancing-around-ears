import Foundation
import CoreGraphics

/// OCR 识别出的一行文本及其位置
public struct OCRLine: Equatable, Sendable {
    public let text: String
    /// 归一化 0..1 矩形, **top-left 原点**（已从 Vision 的 bottom-left 转换）
    public let rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }

    var centerX: CGFloat { rect.midX }
    var centerY: CGFloat { rect.midY }
    var width: CGFloat { rect.width }
}

/// OCR 引擎抽象（将来可接 PaddleOCR 等）
public protocol OCRProvider {
    /// 识别一页图像, 返回原始行（顺序不定, 交给 ReadingOrderProcessor 排序）
    func recognizePage(cgImage: CGImage) async throws -> [OCRLine]
}

public enum OCRError: Error, LocalizedError {
    case pageRenderFailed
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .pageRenderFailed:
            return "PDF 页面渲染失败"
        case .recognitionFailed(let reason):
            return "OCR 识别失败：\(reason)"
        }
    }
}
