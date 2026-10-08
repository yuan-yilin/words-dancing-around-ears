import Foundation
import CoreGraphics
import Vision

/// Apple Vision OCR 实现：中文（简/繁）+ 英文, 精确模式。
///
/// 注意：Vision 的语言纠正不支持中文（官方文档明确）, 因此关闭
/// usesLanguageCorrection, 后续靠 TextCleaner 清洗。
public final class VisionOCR: OCRProvider {
    public init() {}

    public func recognizePage(cgImage: CGImage) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                request.usesLanguageCorrection = false

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let lines = Self.lines(from: request.results ?? [])
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(
                        throwing: OCRError.recognitionFailed(error.localizedDescription)
                    )
                }
            }
        }
    }

    /// VNRecognizedTextObservation → OCRLine（boundingBox 从 bottom-left 转 top-left）
    static func lines(from observations: [VNRecognizedTextObservation]) -> [OCRLine] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let topLeftRect = CGRect(
                x: box.origin.x,
                y: 1 - box.origin.y - box.height,
                width: box.width,
                height: box.height
            )
            return OCRLine(text: candidate.string, rect: topLeftRect)
        }
    }
}
