import Foundation
import UIKit

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, csv, json
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF 健康报告"
        case .csv: return "CSV 表格"
        case .json: return "JSON 备份"
        }
    }

    var subtitle: String {
        switch self {
        case .pdf: return "排版好的小报告，看医生时直接给医生看"
        case .csv: return "可以用 Excel / Numbers 打开"
        case .json: return "完整备份，可在设置里重新导入"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .json: return "externaldrive"
        }
    }
}

enum ExportRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, all = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .week: return "7 天"
        case .month: return "30 天"
        case .quarter: return "90 天"
        case .all: return "全部"
        }
    }
}

enum Exporter {
    static func export(_ records: [PoopRecord], format: ExportFormat, range: ExportRange, now: Date = Date()) throws -> URL {
        let filtered = filter(records, range: range, now: now).sorted { $0.timestamp < $1.timestamp }
        let stamp = fileDateFormatter.string(from: now)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        switch format {
        case .csv:
            let url = dir.appendingPathComponent("噗噗手帐-\(stamp).csv")
            try csv(filtered).write(to: url, atomically: true, encoding: .utf8)
            return url
        case .json:
            let url = dir.appendingPathComponent("噗噗手帐备份-\(stamp).json")
            let backup = Backup(app: "Pupudiary", version: 1, exportedAt: now, records: filtered)
            try RecordStorage.encoder.encode(backup).write(to: url)
            return url
        case .pdf:
            let url = dir.appendingPathComponent("噗噗健康报告-\(stamp).pdf")
            try PDFReport(records: filtered, range: range, now: now).data().write(to: url)
            return url
        }
    }

    static func filter(_ records: [PoopRecord], range: ExportRange, now: Date) -> [PoopRecord] {
        guard range != .all else { return records }
        let cal = Calendar.current
        guard let from = cal.date(byAdding: .day, value: -(range.rawValue - 1), to: cal.startOfDay(for: now)) else { return records }
        return records.filter { $0.timestamp >= from }
    }

    // MARK: CSV

    static func csv(_ records: [PoopRecord]) -> String {
        var rows = ["日期,时间,布里斯托分型,名称,状态,颜色,量,感受,用时(分钟),不适,备注,一键记录"]
        for r in records {
            let fields: [String] = [
                dayFormatter.string(from: r.timestamp),
                timeFormatter.string(from: r.timestamp),
                "\(r.bristol.rawValue)",
                r.bristol.nickname,
                r.status.title,
                r.color?.title ?? "",
                r.amount.title,
                r.ease.title,
                r.durationMinutes > 0 ? "\(r.durationMinutes)" : "",
                r.symptoms.map(\.title).joined(separator: "、"),
                r.note,
                r.isQuick ? "是" : "",
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        // 带 BOM，Excel 打开中文不乱码
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    private static func escape(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: JSON

    struct Backup: Codable {
        var app: String
        var version: Int
        var exportedAt: Date
        var records: [PoopRecord]
    }

    /// 支持导入本 App 的备份，也兼容直接是记录数组的 JSON
    static func importJSON(_ data: Data) throws -> [PoopRecord] {
        if let backup = try? RecordStorage.decoder.decode(Backup.self, from: data) {
            return backup.records
        }
        return try RecordStorage.decoder.decode([PoopRecord].self, from: data)
    }

    // MARK: Formatters

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()
}

// MARK: - PDF 报告（纯 UIKit 绘制，A4）

struct PDFReport {
    let records: [PoopRecord]   // 按时间正序
    let range: ExportRange
    let now: Date

    init(records: [PoopRecord], range: ExportRange, now: Date) {
        self.records = records
        self.range = range
        self.now = now
    }

    private let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private let margin: CGFloat = 40

    private func uiColor(_ status: GutStatus) -> UIColor {
        switch status {
        case .dry: return UIColor(red: 1, green: 0.667, blue: 0.333, alpha: 1)
        case .ideal: return UIColor(red: 0.31, green: 0.77, blue: 0.53, alpha: 1)
        case .soft: return UIColor(red: 0.95, green: 0.76, blue: 0.19, alpha: 1)
        case .loose: return UIColor(red: 0.38, green: 0.68, blue: 0.94, alpha: 1)
        }
    }

    private let ink = UIColor(red: 0.29, green: 0.23, blue: 0.21, alpha: 1)
    private let subtle = UIColor(red: 0.61, green: 0.54, blue: 0.51, alpha: 1)
    private let accent = UIColor(red: 1, green: 0.55, blue: 0.4, alpha: 1)

    private func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    func data() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            var y = drawSummaryPage(ctx)
            y = drawTableHeader(at: y)
            for r in records {
                if y > page.height - margin - 24 {
                    ctx.beginPage()
                    y = drawTableHeader(at: margin)
                }
                y = drawRow(r, at: y)
            }
            drawFooter()
        }
    }

    private func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, width: CGFloat? = nil) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let w = width ?? (page.width - point.x - margin)
        let rect = s.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        s.draw(with: CGRect(x: point.x, y: point.y, width: w, height: ceil(rect.height)),
               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
    }

    private func drawSummaryPage(_ ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        ctx.beginPage()
        let stats = GutStats(records: records, now: now)
        let days = range == .all ? max(1, spanDays) : range.rawValue
        var y = margin

        y += draw("噗噗手帐 · 排便健康报告", at: CGPoint(x: margin, y: y), font: font(22, .bold), color: ink)
        y += 4
        let period: String
        if let first = records.first, let last = records.last {
            period = "\(Exporter.dayFormatter.string(from: first.timestamp)) 至 \(Exporter.dayFormatter.string(from: last.timestamp))"
        } else {
            period = "暂无记录"
        }
        y += draw("统计范围：\(range.title)（\(period)）  ·  生成于 \(Exporter.dayFormatter.string(from: now))",
                  at: CGPoint(x: margin, y: y), font: font(10), color: subtle)
        y += 18

        // 关键数字
        let tiles: [(String, String)] = [
            ("总次数", "\(records.count)"),
            ("日均次数", String(format: "%.1f", Double(records.count) / Double(days))),
            ("理想占比", stats.idealRatio(inLast: days).map { "\(Int(($0 * 100).rounded()))%" } ?? "-"),
            ("最长间隔", stats.longestGapHours(inLast: days).map { String(format: "%.0f 小时", $0) } ?? "-"),
        ]
        let tileW = (page.width - margin * 2 - 3 * 10) / 4
        for (i, tile) in tiles.enumerated() {
            let x = margin + CGFloat(i) * (tileW + 10)
            let rect = CGRect(x: x, y: y, width: tileW, height: 58)
            UIColor(red: 1, green: 0.95, blue: 0.91, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
            _ = draw(tile.0, at: CGPoint(x: x + 10, y: y + 8), font: font(10), color: subtle, width: tileW - 20)
            _ = draw(tile.1, at: CGPoint(x: x + 10, y: y + 24), font: font(20, .bold), color: ink, width: tileW - 20)
        }
        y += 58 + 22

        // 状态分布条
        y += draw("形态分布（布里斯托分型）", at: CGPoint(x: margin, y: y), font: font(13, .semibold), color: ink)
        y += 8
        let typeDist = Dictionary(grouping: records, by: \.bristol).mapValues(\.count)
        let maxCount = max(1, typeDist.values.max() ?? 1)
        let barMaxW = page.width - margin * 2 - 150
        for t in BristolType.allCases {
            let c = typeDist[t] ?? 0
            _ = draw("\(t.rawValue) 型 · \(t.nickname)", at: CGPoint(x: margin, y: y), font: font(10), color: ink, width: 110)
            let w = max(c > 0 ? 4 : 0, barMaxW * CGFloat(c) / CGFloat(maxCount))
            uiColor(t.status).setFill()
            UIBezierPath(roundedRect: CGRect(x: margin + 110, y: y + 2, width: w, height: 11), cornerRadius: 5.5).fill()
            _ = draw("\(c)", at: CGPoint(x: margin + 116 + w, y: y), font: font(10, .semibold), color: subtle, width: 30)
            y += 18
        }
        y += 6
        var legendX = margin
        for s in GutStatus.allCases {
            uiColor(s).setFill()
            UIBezierPath(ovalIn: CGRect(x: legendX, y: y + 3, width: 8, height: 8)).fill()
            _ = draw(s.title, at: CGPoint(x: legendX + 12, y: y), font: font(10), color: subtle, width: 40)
            legendX += 60
        }
        y += 26

        // 时段
        y += draw("时段分布", at: CGPoint(x: margin, y: y), font: font(13, .semibold), color: ink)
        y += 6
        let timeDist = Dictionary(grouping: records) { TimeBucket.of($0.timestamp) }.mapValues(\.count)
        let parts = TimeBucket.allCases.map { "\($0.title) \(timeDist[$0] ?? 0) 次" }.joined(separator: "   ")
        y += draw(parts, at: CGPoint(x: margin, y: y), font: font(11), color: ink)
        y += 18

        // 需要关注
        let flagged = records.filter(\.needsAttention)
        let symptomCount = Dictionary(grouping: records.flatMap(\.symptoms), by: { $0 }).mapValues(\.count)
        y += draw("需要关注", at: CGPoint(x: margin, y: y), font: font(13, .semibold), color: ink)
        y += 6
        var notes: [String] = []
        if !flagged.isEmpty { notes.append("有 \(flagged.count) 次记录到血丝或黑色/红色/灰白色") }
        if !symptomCount.isEmpty {
            notes.append("不适情况：" + Symptom.allCases.compactMap { s in symptomCount[s].map { "\(s.title) \($0) 次" } }.joined(separator: "、"))
        }
        if notes.isEmpty { notes.append("没有特别需要关注的记录") }
        for n in notes {
            y += draw("• " + n, at: CGPoint(x: margin, y: y), font: font(11), color: ink)
            y += 4
        }
        y += 8
        y += draw("本报告由用户自行记录生成，仅供参考，不构成医疗诊断。", at: CGPoint(x: margin, y: y), font: font(9), color: subtle)
        y += 20
        y += draw("详细记录", at: CGPoint(x: margin, y: y), font: font(13, .semibold), color: ink)
        y += 8
        return y
    }

    private var spanDays: Int {
        guard let first = records.first else { return 1 }
        let cal = Calendar.current
        return (cal.dateComponents([.day], from: cal.startOfDay(for: first.timestamp), to: cal.startOfDay(for: now)).day ?? 0) + 1
    }

    private let columns: [(String, CGFloat)] = [
        ("日期", 0), ("时间", 72), ("分型", 112), ("状态", 172), ("量/感受", 212), ("颜色", 276), ("不适 / 备注", 316),
    ]

    private func drawTableHeader(at y: CGFloat) -> CGFloat {
        UIColor(red: 1, green: 0.93, blue: 0.87, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: margin - 6, y: y, width: page.width - margin * 2 + 12, height: 20), cornerRadius: 6).fill()
        for (title, x) in columns {
            _ = draw(title, at: CGPoint(x: margin + x, y: y + 4), font: font(9, .semibold), color: ink, width: 90)
        }
        return y + 24
    }

    private func drawRow(_ r: PoopRecord, at y: CGFloat) -> CGFloat {
        let f = font(9)
        let extra = (r.symptoms.map(\.title) + (r.note.isEmpty ? [] : [r.note])).joined(separator: "；")
        let values: [String] = [
            Exporter.dayFormatter.string(from: r.timestamp),
            Exporter.timeFormatter.string(from: r.timestamp),
            "\(r.bristol.rawValue) 型 \(r.bristol.nickname)",
            r.status.title,
            "\(r.amount.title)/\(r.ease.title)",
            r.color?.title ?? "-",
        ]
        for (i, v) in values.enumerated() {
            let color: UIColor = i == 3 ? uiColor(r.status) : ink
            _ = draw(v, at: CGPoint(x: margin + columns[i].1, y: y), font: i == 3 ? font(9, .bold) : f, color: color, width: 70)
        }
        let h = draw(extra.isEmpty ? "-" : extra, at: CGPoint(x: margin + columns[6].1, y: y), font: f,
                     color: r.needsAttention ? UIColor.systemRed : ink, width: page.width - margin * 2 - columns[6].1)
        let rowH = max(14, h) + 5
        UIColor(white: 0.9, alpha: 1).setFill()
        UIRectFill(CGRect(x: margin, y: y + rowH - 2, width: page.width - margin * 2, height: 0.5))
        return y + rowH
    }

    private func drawFooter() {
        // 只在最后一页画页脚
        _ = draw("Pupudiary · 噗噗手帐", at: CGPoint(x: margin, y: page.height - 28), font: font(8), color: accent, width: 200)
    }
}
