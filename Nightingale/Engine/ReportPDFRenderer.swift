import Foundation
import SwiftUI
import UIKit

/// PDF 报告渲染（Phase 3 · P3.2）。
///
/// 把 SessionDetailView 里常见的内容（header / 指标 / 4 张单图 / overlay / 事件列表
/// 含转写）渲染成一份医学风格 PDF。UI 层用 `ShareLink(item: URL)` 把文件导出。
///
/// 实现：用 `ImageRenderer` 把几块 SwiftUI view 渲染成 UIImage，再用
/// `UIGraphicsPDFRenderer` 把 images 拼到 PDF 页面上。
///
/// 注意：`ImageRenderer` 需要在主线程调用（依赖 @MainActor），所以整个
/// `render(session:)` 标 @MainActor。
@MainActor
final class ReportPDFRenderer {

    /// 页面尺寸（Letter-ish：612 × 792 pt）。
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792
    static let margin: CGFloat = 36

    /// 入口：给一个 session，写出 PDF 到 tmp 目录，返回 URL。失败返回 nil。
    func render(session: SleepSession) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: Self.pageWidth, height: Self.pageHeight)
        let renderer = UIGraphicsPDFRenderer(
            bounds: pageRect,
            format: UIGraphicsPDFRendererFormat()
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nightingale-\(session.startTime.formatted(.iso8601)).pdf")
        try? FileManager.default.removeItem(at: url)

        do {
            try renderer.writePDF(to: url) { context in
                renderPages(session: session, in: context)
            }
            return url
        } catch {
            NSLog("PDF render failed: \(error)")
            return nil
        }
    }

    // MARK: - Page composition

    private func renderPages(session: SleepSession, in context: UIGraphicsPDFRendererContext) {
        let contentWidth = Self.pageWidth - 2 * Self.margin
        var page = PageLayout(
            context: context,
            contentWidth: contentWidth,
            margin: Self.margin,
            pageHeight: Self.pageHeight
        )
        page.startNewPage()

        // 1. Header
        renderText(
            "Nightingale 睡眠报告",
            font: .boldSystemFont(ofSize: 22),
            color: UIColor.black,
            page: &page
        )
        renderText(
            session.startTime.formatted(date: .long, time: .shortened),
            font: .systemFont(ofSize: 14),
            color: UIColor.darkGray,
            page: &page
        )
        page.advance(by: 6)
        renderText(
            "记录时长：\(TimeFormat.duration(session.durationSeconds))",
            font: .systemFont(ofSize: 14),
            color: UIColor.darkGray,
            page: &page
        )
        page.advance(by: 14)

        // 2. Metrics grid（用 SwiftUI 渲染成图片）
        renderSection(title: "指标", page: &page)
        renderSwiftUIBlock(
            height: 120,
            page: &page,
            view: PDFMetricsGrid(session: session)
        )

        // 3. Overlay timeline
        renderSection(title: "综合时间轴", page: &page)
        renderSwiftUIBlock(
            height: 240,
            page: &page,
            view: OverlayTimelineChart(session: session)
                .frame(width: contentWidth, height: 220)
                .padding(.horizontal, 8)
        )

        // 4. Individual charts
        renderSection(title: "睡眠分期", page: &page)
        renderSwiftUIBlock(
            height: 200,
            page: &page,
            view: SleepStageChart(session: session)
                .frame(width: contentWidth, height: 180)
                .padding(.horizontal, 8)
        )
        renderSection(title: "心率", page: &page)
        renderSwiftUIBlock(
            height: 160,
            page: &page,
            view: HeartRateChart(session: session)
                .frame(width: contentWidth, height: 140)
                .padding(.horizontal, 8)
        )
        renderSection(title: "血氧", page: &page)
        renderSwiftUIBlock(
            height: 160,
            page: &page,
            view: SpO2Chart(session: session)
                .frame(width: contentWidth, height: 140)
                .padding(.horizontal, 8)
        )
        renderSection(title: "打呼时间轴", page: &page)
        renderSwiftUIBlock(
            height: 140,
            page: &page,
            view: SnoreTimelineChart(session: session)
                .frame(width: contentWidth, height: 120)
                .padding(.horizontal, 8)
        )

        // 5. Event list（含梦话转写）
        renderSection(title: "事件列表", page: &page)
        let events = session.events.sorted { $0.timestamp < $1.timestamp }
        if events.isEmpty {
            renderText(
                "本晚未检测到事件。",
                font: .systemFont(ofSize: 12),
                color: UIColor.darkGray,
                page: &page
            )
        } else {
            for event in events {
                let line = eventLine(event)
                renderText(line, font: .systemFont(ofSize: 11), color: UIColor.black, page: &page)
                if event.type == .sleepTalk, let t = event.transcript, !t.isEmpty {
                    renderText(
                        "  “\(t)”",
                        font: .italicSystemFont(ofSize: 11),
                        color: UIColor.darkGray,
                        page: &page
                    )
                }
            }
        }

        // 6. Tags + morning note（附页尾）
        if !session.tags.isEmpty || !(session.morningNote ?? "").isEmpty {
            page.advance(by: 10)
            renderSection(title: "标签 & 打卡", page: &page)
            if !session.tags.isEmpty {
                renderText(
                    "标签：\(session.tags.joined(separator: "、"))",
                    font: .systemFont(ofSize: 12),
                    color: UIColor.black,
                    page: &page
                )
            }
            if let note = session.morningNote, !note.isEmpty {
                renderText(
                    "一句话：\(note)",
                    font: .systemFont(ofSize: 12),
                    color: UIColor.black,
                    page: &page
                )
            }
        }

        // 7. 免责声明
        page.advance(by: 12)
        renderText(
            "本报告仅供个人参考，不构成医疗诊断。",
            font: .systemFont(ofSize: 10),
            color: UIColor.gray,
            page: &page
        )
    }

    // MARK: - Low-level renderers

    /// 把一段 SwiftUI View 渲染成 UIImage，然后按 contentWidth 绘入当前页面。
    /// 如果剩余空间不够就换页。
    private func renderSwiftUIBlock<V: View>(height: CGFloat, page: inout PageLayout, view: V) {
        let contentWidth = Self.pageWidth - 2 * Self.margin
        let renderer = ImageRenderer(content:
            view
                .frame(width: contentWidth, height: height)
                .background(Color.white)
        )
        renderer.scale = 2.0
        renderer.proposedSize = .init(width: contentWidth, height: height)

        guard let image = renderer.uiImage else { return }
        if !page.hasRoom(for: height + 8) { page.startNewPage() }
        image.draw(in: CGRect(x: Self.margin,
                              y: page.cursorY,
                              width: contentWidth,
                              height: height))
        page.advance(by: height + 8)
    }

    private func renderSection(title: String, page: inout PageLayout) {
        page.advance(by: 8)
        renderText(title, font: .boldSystemFont(ofSize: 14), color: UIColor.black, page: &page)
        page.advance(by: 2)
    }

    private func renderText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        page: inout PageLayout
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let contentWidth = Self.pageWidth - 2 * Self.margin
        let bounds = attributed.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = ceil(bounds.height)
        if !page.hasRoom(for: height) { page.startNewPage() }
        attributed.draw(in: CGRect(
            x: Self.margin,
            y: page.cursorY,
            width: contentWidth,
            height: height
        ))
        page.advance(by: height + 2)
    }

    private func eventLine(_ e: SleepEvent) -> String {
        let typeName: String = {
            switch e.type {
            case .snore: return "打呼"
            case .sleepTalk: return "梦话"
            case .suspectedApnea: return "疑似呼吸暂停"
            case .nightmareSpike: return "夜惊"
            }
        }()
        let time = e.timestamp.formatted(date: .omitted, time: .standard)
        return String(format: "• %@  %@  时长 %.0fs  置信度 %.0f%%",
                      time, typeName, e.duration, e.confidence * 100)
    }
}

// MARK: - Page layout helper

private struct PageLayout {
    let context: UIGraphicsPDFRendererContext
    let contentWidth: CGFloat
    let margin: CGFloat
    let pageHeight: CGFloat
    var cursorY: CGFloat = 0

    mutating func startNewPage() {
        context.beginPage()
        cursorY = margin
    }

    mutating func advance(by delta: CGFloat) {
        cursorY += delta
    }

    func hasRoom(for height: CGFloat) -> Bool {
        cursorY + height <= pageHeight - margin
    }
}

// MARK: - SwiftUI helper blocks

/// 指标格子（复用 SessionDetailView 的视觉语言，但固定白背景便于 PDF）。
private struct PDFMetricsGrid: View {
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    cell("时长", TimeFormat.duration(session.durationSeconds))
                    cell("打呼次数", "\(session.snoreCount)")
                }
                GridRow {
                    cell("平均心率",
                         session.averageHeartRate.map { String(format: "%.0f BPM", $0) } ?? "—")
                    cell("最低 SpO₂",
                         session.minSpO2.map { String(format: "%.1f%%", $0) } ?? "—")
                }
                GridRow {
                    cell("平均噪音",
                         session.ambientNoiseAverageDB.map { String(format: "%.0f dB", 100 + $0) } ?? "—")
                    cell("峰值噪音",
                         session.ambientNoisePeakDB.map { String(format: "%.0f dB", 100 + $0) } ?? "—")
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    @ViewBuilder
    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.gray)
            Text(value).font(.headline).foregroundColor(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
