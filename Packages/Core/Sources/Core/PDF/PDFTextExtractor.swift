import Foundation
import PDFKit

/// 单页文本提取结果
public struct PDFPageText: Identifiable, Hashable, Sendable {
    /// 0-based 页码
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }

    /// 有效文本长度（去空白）
    public var effectiveCharacterCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// 该页几乎没有文字层, 大概率是扫描页, 需要 OCR
    public var isLikelyScanned: Bool {
        effectiveCharacterCount < 16
    }
}

public enum PDFExtractionError: Error, LocalizedError {
    case cannotOpenDocument

    public var errorDescription: String? {
        switch self {
        case .cannotOpenDocument:
            return "无法打开该 PDF 文档"
        }
    }
}

/// PDF → 逐页文本提取（判断文字页/扫描页的入口）
public enum PDFTextExtractor {
    /// 打开 PDF 并提取全部页面文本
    public static func extractPages(from url: URL) throws -> [PDFPageText] {
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractionError.cannotOpenDocument
        }
        return extractPages(from: document)
    }

    public static func extractPages(from document: PDFDocument) -> [PDFPageText] {
        (0..<document.pageCount).map { index in
            PDFPageText(id: index, text: document.page(at: index)?.string ?? "")
        }
    }

    /// 全书是否基本没有文字层（整本扫描版）
    public static func isLikelyScannedDocument(_ pages: [PDFPageText]) -> Bool {
        guard !pages.isEmpty else { return false }
        let scanned = pages.filter(\.isLikelyScanned).count
        return Double(scanned) / Double(pages.count) > 0.8
    }
}
