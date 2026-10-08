import Foundation
import CoreGraphics

/// OCR 阅读顺序修正：按行位置重排为人类阅读顺序。
///
/// 算法（递归分栏）：
/// 1. 在 x 方向寻找「栏间沟槽」——一条无任何行横向穿越的竖直空白带
/// 2. 找到沟槽即按其切分为左右两组, 分别递归处理, 先左后右
/// 3. 无沟槽（单栏）时按 y 聚类成行, 行内按 x 排序, 行间按 y 排序
///
/// 这样能正确处理单栏、双栏乃至多栏 PDF, 而不会出现
/// 「左栏一行 + 右栏一行」交替的错序。
public enum ReadingOrderProcessor {
    /// 栏间沟槽最小宽度（归一化）
    private static let gutterWidth: CGFloat = 0.06
    /// 行聚类时的垂直重叠比例阈值
    private static let rowOverlapRatio: CGFloat = 0.5

    /// 返回按阅读顺序排列的行
    public static func orderedLines(_ lines: [OCRLine]) -> [OCRLine] {
        guard lines.count > 1 else { return lines }
        guard let gutter = findGutter(in: lines) else {
            return orderSingleColumn(lines)
        }
        let left = lines.filter { $0.rect.midX < gutter }
        let right = lines.filter { $0.rect.midX >= gutter }
        // 切分失败保护（理论不会发生: 沟槽定义保证两侧非空）
        guard !left.isEmpty, !right.isEmpty else {
            return orderSingleColumn(lines)
        }
        return orderedLines(left) + orderedLines(right)
    }

    /// 排序后的全文（行以 \n 连接）
    public static func orderedText(_ lines: [OCRLine]) -> String {
        orderedLines(lines).map(\.text).joined(separator: "\n")
    }

    // MARK: - 分栏

    /// 寻找一条把行集分成左右两部分的竖直空白带, 没有则返回 nil
    private static func findGutter(in lines: [OCRLine]) -> CGFloat? {
        let sorted = lines.sorted { $0.rect.minX < $1.rect.minX }

        // 相邻（按 minX 排序）行之间的水平间隙
        var candidates: [(x: CGFloat, width: CGFloat)] = []
        for index in 0..<(sorted.count - 1) {
            let rightEdge = sorted[0...index].map { $0.rect.maxX }.max() ?? 0
            let nextLeft = sorted[index + 1].rect.minX
            if nextLeft - rightEdge >= gutterWidth {
                candidates.append((x: rightEdge, width: nextLeft - rightEdge))
            }
        }
        guard !candidates.isEmpty else { return nil }

        // 必须是真正的「栏」而不是个别短行造成的假间隙：
        // 沟槽两侧都要在纵向覆盖足够比例的版面高度
        let pageHeight = lines.map { $0.rect.maxY }.max() ?? 1
            - (lines.map { $0.rect.minY }.min() ?? 0)
        guard pageHeight > 0 else { return nil }
        let coverageThreshold = pageHeight * 0.3

        for candidate in candidates {
            let left = lines.filter { $0.rect.midX < candidate.x + candidate.width / 2 }
            let right = lines.filter { $0.rect.midX >= candidate.x + candidate.width / 2 }
            guard !left.isEmpty, !right.isEmpty else { continue }

            func verticalSpan(_ group: [OCRLine]) -> CGFloat {
                guard let maxY = group.map({ $0.rect.maxY }).max(),
                      let minY = group.map({ $0.rect.minY }).min() else { return 0 }
                return maxY - minY
            }
            if verticalSpan(left) >= coverageThreshold,
               verticalSpan(right) >= coverageThreshold {
                return candidate.x + candidate.width / 2
            }
        }
        return nil
    }

    // MARK: - 单栏排序

    /// 单栏：按垂直中心聚类成行 → 行间按 y、行内按 x
    private static func orderSingleColumn(_ lines: [OCRLine]) -> [OCRLine] {
        let rows = clusterRows(lines)
        return rows.flatMap { row in
            row.sorted { $0.rect.minX < $1.rect.minX }
        }
    }

    /// 聚成若干「视觉行」：垂直中心距离 < 半行高即同行
    private static func clusterRows(_ lines: [OCRLine]) -> [[OCRLine]] {
        let sorted = lines.sorted { $0.rect.midY < $1.rect.midY }
        let medianHeight = median(sorted.map(\.rect.height).filter { $0 > 0 }) ?? 0.02
        let threshold = medianHeight * (1 + rowOverlapRatio)

        var rows: [[OCRLine]] = []
        var current: [OCRLine] = []
        var currentCenter: CGFloat?

        for line in sorted {
            if let center = currentCenter, abs(line.rect.midY - center) <= threshold {
                current.append(line)
                // 行中心随成员缓慢更新（处理轻微倾斜）
                currentCenter = (center * CGFloat(current.count - 1) + line.rect.midY)
                    / CGFloat(current.count)
            } else {
                if !current.isEmpty {
                    rows.append(current)
                }
                current = [line]
                currentCenter = line.rect.midY
            }
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
