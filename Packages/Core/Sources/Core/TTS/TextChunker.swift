import Foundation

/// 中文文本分段器：把全文切成适合 TTS 流水线生成的 chunk。
///
/// 规则（参考 PLAN.md「分段」一节）：
/// - 以句号/问号/感叹号/分号/换行为句界
/// - 句子聚合成 chunk，目标 300～600 字
/// - 单句超长时按逗号/顿号再切
/// - 不在英文单词或数字中间切断
public enum TextChunker {
    /// 句界标点（含全角/半角）
    private static let sentenceEnds: Set<Character> = ["。", "！", "？", "；", "!", "?", ";"]
    /// 句内次级分隔（超长句再切）
    private static let clauseBreaks: Set<Character> = ["，", "、", ",", "：", ":"]

    private static let targetLength = 400
    private static let maxLength = 600
    private static let minSentenceLength = 12

    public static func chunks(from text: String) -> [String] {
        let sentences = splitSentences(from: text)
        return accumulate(sentences: sentences)
    }

    /// MARK: - 句子切分

    private static func splitSentences(from text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sentences.append(trimmed)
            }
            current = ""
        }

        for character in text {
            current.append(character)
            if sentenceEnds.contains(character) {
                flush()
            } else if character == "\n" {
                // 换行视为弱句界：短行（标题）立即断，长行只在句末断
                if current.count < minSentenceLength {
                    flush()
                } else {
                    current.removeLast()
                    flush()
                }
            }
        }
        flush()
        return sentences
    }

    /// MARK: - 聚合

    private static func accumulate(sentences: [String]) -> [String] {
        var result: [String] = []
        var buffer = ""

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append(trimmed)
            }
            buffer = ""
        }

        for sentence in sentences {
            // 单句超长：按子句拆开逐段吸收
            if sentence.count > maxLength {
                for clause in splitClauses(from: sentence) {
                    if buffer.count + clause.count > maxLength {
                        flush()
                    }
                    if clause.count > maxLength {
                        // 子句仍超长（罕见），硬切但避开行首
                        for piece in hardSplit(clause) {
                            if buffer.count + piece.count > maxLength {
                                flush()
                            }
                            buffer += piece
                            flush()
                        }
                    } else {
                        buffer += clause
                    }
                }
                continue
            }

            if buffer.count + sentence.count > maxLength {
                flush()
            }
            buffer += sentence

            if buffer.count >= targetLength {
                flush()
            }
        }
        flush()
        return result
    }

    /// 按逗号等次级分隔切子句（保留分隔符在子句尾部）
    private static func splitClauses(from sentence: String) -> [String] {
        var clauses: [String] = []
        var current = ""
        for character in sentence {
            current.append(character)
            if clauseBreaks.contains(character) {
                clauses.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            clauses.append(current)
        }
        return clauses
    }

    /// 硬切分：每段约 maxLength，不切在 ASCII 字母/数字中间
    private static func hardSplit(_ text: String) -> [String] {
        var pieces: [String] = []
        var start = text.startIndex
        while text.distance(from: start, to: text.endIndex) > maxLength {
            var end = text.index(start, offsetBy: maxLength)
            // 回退到非 ASCII 字母数字边界
            while end > start,
                  text[text.index(before: end)].isLetter || text[text.index(before: end)].isNumber {
                end = text.index(before: end)
                if text.distance(from: start, to: end) <= maxLength / 2 {
                    break
                }
            }
            pieces.append(String(text[start..<end]))
            start = end
        }
        let rest = String(text[start...])
        if !rest.isEmpty {
            pieces.append(rest)
        }
        return pieces
    }
}
