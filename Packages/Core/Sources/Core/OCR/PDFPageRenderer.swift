import Foundation
import PDFKit
import CoreGraphics

/// PDF 页面 → CGImage 渲染（OCR 前置步骤）
public enum PDFPageRenderer {
    /// 渲染某页为位图
    /// - Parameters:
    ///   - page: PDF 页
    ///   - scale: 相对 mediaBox 的放大倍数（2.0 ≈ 144dpi, OCR 够用）
    public static func renderImage(from page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 白底（透明底会显著降低 Vision OCR 质量）
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
