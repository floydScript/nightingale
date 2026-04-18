import SwiftUI
import SwiftData
import NaturalLanguage

/// 梦话词云（Phase 3 · P3.7）。
/// 把所有 sleepTalk 事件的 transcript 合并 → NLTokenizer 分词 →
/// 去停用词 → 按词频用 flow-layout 铺 50 个 token，字号按对数比例缩放。
struct WordCloudView: View {

    @Query(sort: \SleepEvent.timestamp, order: .reverse) private var events: [SleepEvent]

    @State private var tokens: [TokenWeight] = []

    /// 常见中文虚词 + 英文 stop words。词云太杂时这里可以扩充。
    private static let stopWords: Set<String> = [
        // 中文
        "的", "了", "是", "我", "你", "他", "她", "它", "这", "那", "在", "有",
        "和", "就", "都", "也", "要", "不", "一", "吧", "啊", "哦", "呢", "吗",
        "着", "呀", "嗯", "哈", "哎", "诶", "没",
        // 英文 & 占位
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "is", "it", "i",
        "you", "we", "he", "she", "me", "my", "your", "that", "this", "for",
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if tokens.isEmpty {
                        emptyState
                    } else {
                        FlowLayout(spacing: 10, lineSpacing: 10) {
                            ForEach(tokens) { t in
                                Text(t.token)
                                    .font(.system(size: t.fontSize, weight: .semibold))
                                    .foregroundStyle(Theme.accent.opacity(0.6 + 0.4 * t.normalized))
                                    .padding(.horizontal, 6)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .padding(Theme.padding)
            }
        }
        .navigationTitle("梦话词云")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: rebuild)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("过去梦话中出现最多的 \(min(50, tokens.count)) 个词")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("来源：\(sleepTalkEventCount) 条梦话转写")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有足够的梦话转写来生成词云。")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var sleepTalkEventCount: Int {
        events.filter { $0.type == .sleepTalk && $0.transcript != nil }.count
    }

    // MARK: - Tokenization

    private func rebuild() {
        let transcripts: [String] = events.compactMap { e in
            guard e.type == .sleepTalk, let t = e.transcript, !t.isEmpty else { return nil }
            return t
        }
        tokens = WordCloudView.tokenize(transcripts, limit: 50, stopWords: Self.stopWords)
    }

    /// 暴露为 static 方便写单测。
    static func tokenize(_ texts: [String], limit: Int, stopWords: Set<String>) -> [TokenWeight] {
        guard !texts.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        var counts: [String: Int] = [:]

        for text in texts {
            tokenizer.string = text
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let raw = String(text[range]).lowercased()
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count >= 1 else { return true }
                // 过滤全标点 / 全数字
                if trimmed.allSatisfy({ $0.isPunctuation || $0.isWhitespace }) { return true }
                if stopWords.contains(trimmed) { return true }
                counts[trimmed, default: 0] += 1
                return true
            }
        }

        let sorted = counts.sorted { $0.value > $1.value }.prefix(limit)
        guard !sorted.isEmpty else { return [] }
        let maxCount = sorted.first!.value

        return sorted.map { (word, count) in
            // 对数缩放，字号范围 [14, 36]
            let ratio = log(Double(count) + 1) / log(Double(maxCount) + 1)
            let fontSize = 14 + ratio * 22
            return TokenWeight(
                token: word,
                count: count,
                fontSize: fontSize,
                normalized: ratio
            )
        }
    }

    struct TokenWeight: Identifiable, Equatable, Sendable {
        let token: String
        let count: Int
        let fontSize: CGFloat
        /// 0...1 相对频率，可用于透明度 / 颜色加深。
        let normalized: Double
        var id: String { token }
    }
}

// MARK: - FlowLayout

/// 自己撸一个简化版 flow layout——一行装不下就换行，从左到右。
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        var x: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineH)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineH + lineSpacing
                x = bounds.minX
                lineH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}
