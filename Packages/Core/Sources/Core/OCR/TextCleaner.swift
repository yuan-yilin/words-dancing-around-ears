import Foundation

/// OCR 文本清洗：把阅读顺序排好的行列表整理成适合 TTS 朗读的段落文本。
///
/// 处理内容：
/// - 去掉页码行（纯数字、第 N 页、罗马数字等孤立行）
/// - 合并断行（CJK 直接拼接, 拉丁字母按空格规则）
/// - 去连字符断词（"inter-\nnational" → "international"）
/// - 按段落重组（行尾句界 / 明显短行 → 换段）
public enum TextCleaner {
    /// 清洗入口
    public static func clean(_ orderedLines: [String]) -> String {
        let significant = orderedLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !isPageNumberLine($0) }

        guard !significant.isEmpty else { return "" }

        var paragraphs: [String] = []
        var buffer = ""

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                paragraphs.append(trimmed)
            }
            buffer = ""
        }

        for line in significant {
            if buffer.isEmpty {
                buffer = line
                continue
            }

            if endsParagraph(buffer, next: line) {
                flush()
                buffer = line
                continue
            }

            buffer = joinLines(buffer, line)
        }
        flush()

        return paragraphs.joined(separator: "\n")
    }

    // MARK: - 页码判定

    private static func isPageNumberLine(_ line: String) -> Bool {
        let compact = line
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—·."))
        guard compact.count <= 8 else { return false }

        // 纯数字 / 罗马数字 / 「第N页」/ 「- N -」
        if compact.allSatisfy(\.isNumber) { return true }
        let roman = compact.lowercased()
        if !roman.isEmpty,
           roman.allSatisfy({ "ivxlcdm".contains($0) }) {
            return true
        }
        if let regex = try? NSRegularExpression(pattern: "^第?\\s*\\d+\\s*页?$") {
            let range = NSRange(compact.startIndex..., in: compact)
            if regex.firstMatch(in: compact, range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - 断行合并

    /// 行尾是否意味着段落结束
    private static func endsParagraph(_ current: String, next: String) -> Bool {
        guard let last = current.last else { return false }

        // 句末标点 → 段落结束
        if "。！？!?".contains(last) { return true }

        // 短行（如标题）后接新内容 → 段落结束
        if current.count <= 12 { return true }

        // 下一行以缩进/项目符号/明显新句开始
        if let first = next.first,
           "•·▪-–—①②③④⑤⑥⑦⑧⑨⑩".contains(first) {
            return true
        }

        return false
    }

    /// 两行合并（处理连字符断词与 CJK/拉丁接缝）
    private static func joinLines(_ a: String, _ b: String) -> String {
        // 连字符断词: "inter-" + "national" → "international"
        if a.hasSuffix("-"),
           let bFirst = b.first,
           bFirst.isLetter, bFirst.isLowercase {
            return String(a.dropLast()) + b
        }

        // 接缝处理
        guard let aLast = a.last, let bFirst = b.first else { return a + b }

        let aLatin = aLast.isLetter && isLatin(aLast)
        let bLatin = bFirst.isLetter && isLatin(bFirst)

        if aLatin && bLatin {
            return a + " " + b // 英文单词间补空格
        }
        // CJK 或混合 → 直接拼接
        return a + b
    }

    /// ASCII/扩展拉丁（区别于 CJK）
    private static func isLatin(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        return scalar.value < 0x2E80 // CJK 笔画区起点
    }
}
