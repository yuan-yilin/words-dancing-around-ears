import Foundation
import PDFKit

/// 扫描版 PDF 整合管线：对疑似扫描页执行 渲染 → OCR → 阅读顺序 → 清洗。
public enum PDFOCRPipeline {
    /// 处理一本书的页面文本
    /// - Parameters:
    ///   - document: PDF 文档
    ///   - pages: 逐页文本（isLikelyScanned 的页会被 OCR 结果替换）
    ///   - ocr: OCR 引擎
    ///   - progress: (已完成页, 总扫描页) 回调, 主线程
    /// - Returns: 替换后的逐页文本
    @discardableResult
    public static func process(
        document: PDFDocument,
        pages: [PDFPageText],
        ocr: OCRProvider = VisionOCR(),
        progress: ((Int, Int) -> Void)? = nil
    ) async -> [PDFPageText] {
        let scannedIndexes = pages.indices.filter { pages[$0].isLikelyScanned }
        let total = scannedIndexes.count
        guard total > 0 else { return pages }

        var result = pages
        var done = 0

        for index in scannedIndexes {
            let doneNow = done
            guard let page = document.page(at: index) else {
                done += 1
                await MainActor.run { progress?(doneNow + 1, total) }
                continue
            }

            let text: String
            do {
                text = try await recognizePage(page, ocr: ocr)
            } catch {
                text = ""
            }
            result[index] = PDFPageText(id: index, text: text)

            done += 1
            let finished = done
            await MainActor.run { progress?(finished, total) }
        }
        return result
    }

    /// 单页：渲染 → OCR → 排序 → 清洗
    public static func recognizePage(
        _ page: PDFPage,
        ocr: OCRProvider = VisionOCR()
    ) async throws -> String {
        guard let image = PDFPageRenderer.renderImage(from: page) else {
            throw OCRError.pageRenderFailed
        }
        let lines = try await ocr.recognizePage(cgImage: image)
        let ordered = ReadingOrderProcessor.orderedLines(lines)
        return TextCleaner.clean(ordered.map(\.text))
    }
}
