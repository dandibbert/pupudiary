import Foundation

/// 健康提示的级别
enum InsightLevel: Int, Comparable {
    case good, info, attention, warning
    static func < (a: InsightLevel, b: InsightLevel) -> Bool { a.rawValue < b.rawValue }
}

struct Insight: Identifiable, Hashable {
    let id = UUID()
    let level: InsightLevel
    let title: String
    let message: String
}

struct DaySummary: Identifiable, Hashable {
    var id: Date { day }
    let day: Date
    let records: [PoopRecord]

    var count: Int { records.count }

    /// 当天最“需要关注”的状态，用于日历/小组件上的颜色
    var dominantStatus: GutStatus? {
        guard !records.isEmpty else { return nil }
        var counts: [GutStatus: Int] = [:]
        for r in records { counts[r.status, default: 0] += 1 }
        return counts.max { a, b in
            a.value == b.value ? a.key == .ideal : a.value < b.value
        }?.key
    }
}

enum TimeBucket: Int, CaseIterable, Identifiable {
    case morning, noon, afternoon, evening, night
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .morning: return "早上"
        case .noon: return "中午"
        case .afternoon: return "下午"
        case .evening: return "晚上"
        case .night: return "深夜"
        }
    }
    var emoji: String {
        switch self {
        case .morning: return "🌅"
        case .noon: return "☀️"
        case .afternoon: return "🌤️"
        case .evening: return "🌙"
        case .night: return "🌌"
        }
    }
    static func of(_ date: Date, calendar: Calendar = .current) -> TimeBucket {
        let h = calendar.component(.hour, from: date)
        switch h {
        case 5..<11: return .morning
        case 11..<14: return .noon
        case 14..<18: return .afternoon
        case 18..<23: return .evening
        default: return .night
        }
    }
}

/// 所有统计计算集中在这里，App 和小组件共用
struct GutStats {
    let records: [PoopRecord]   // 按时间倒序
    var calendar: Calendar = .current
    var now: Date = Date()

    init(records: [PoopRecord], now: Date = Date(), calendar: Calendar = .current) {
        self.records = records.sorted { $0.timestamp > $1.timestamp }
        self.now = now
        self.calendar = calendar
    }

    var last: PoopRecord? { records.first }

    func records(on day: Date) -> [PoopRecord] {
        records.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
    }

    var today: [PoopRecord] { records(on: now) }

    /// 最近 n 天（含今天），从早到晚
    func days(_ n: Int) -> [DaySummary] {
        let start = calendar.startOfDay(for: now)
        var grouped: [Date: [PoopRecord]] = [:]
        if let from = calendar.date(byAdding: .day, value: -(n - 1), to: start) {
            for r in records where r.timestamp >= from {
                grouped[calendar.startOfDay(for: r.timestamp), default: []].append(r)
            }
        }
        return (0..<n).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return DaySummary(day: d, records: grouped[d] ?? [])
        }
    }

    func records(inLast n: Int) -> [PoopRecord] {
        guard let from = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: now)) else { return [] }
        return records.filter { $0.timestamp >= from }
    }

    /// 连续有记录的天数（今天还没记的话从昨天开始算）
    var streak: Int {
        let days = Set(records.map { calendar.startOfDay(for: $0.timestamp) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = y
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    func statusDistribution(inLast n: Int) -> [GutStatus: Int] {
        var d: [GutStatus: Int] = [:]
        for r in records(inLast: n) { d[r.status, default: 0] += 1 }
        return d
    }

    func typeDistribution(inLast n: Int) -> [BristolType: Int] {
        var d: [BristolType: Int] = [:]
        for r in records(inLast: n) { d[r.bristol, default: 0] += 1 }
        return d
    }

    func timeDistribution(inLast n: Int) -> [TimeBucket: Int] {
        var d: [TimeBucket: Int] = [:]
        for r in records(inLast: n) { d[TimeBucket.of(r.timestamp, calendar: calendar), default: 0] += 1 }
        return d
    }

    func idealRatio(inLast n: Int) -> Double? {
        let list = records(inLast: n)
        guard !list.isEmpty else { return nil }
        return Double(list.filter { $0.status == .ideal }.count) / Double(list.count)
    }

    func averagePerDay(inLast n: Int) -> Double {
        Double(records(inLast: n).count) / Double(max(n, 1))
    }

    /// 区间内最长的两次间隔（小时）
    func longestGapHours(inLast n: Int) -> Double? {
        let list = records(inLast: n).sorted { $0.timestamp < $1.timestamp }
        guard list.count >= 2 else { return nil }
        var maxGap: TimeInterval = 0
        for i in 1..<list.count {
            maxGap = max(maxGap, list[i].timestamp.timeIntervalSince(list[i - 1].timestamp))
        }
        return maxGap / 3600
    }

    var hoursSinceLast: Double? {
        guard let last else { return nil }
        return now.timeIntervalSince(last.timestamp) / 3600
    }

    /// 最主要的一条健康提示
    var headline: Insight { insights.first ?? Insight(level: .info, title: "开始记录吧", message: "记录下第一次噗噗，就能看到你的肠道小报告啦") }

    /// 根据最近的记录生成健康提示，按严重程度排序
    var insights: [Insight] {
        guard !records.isEmpty else { return [] }
        var list: [Insight] = []
        let week = records(inLast: 7)

        if week.contains(where: \.needsAttention) {
            list.append(Insight(level: .warning,
                                title: "有需要留意的记录",
                                message: "最近记录到血丝或黑色、红色、灰白色。如果持续出现，请尽快咨询医生。"))
        }

        if let h = hoursSinceLast, h >= 72 {
            let days = Int(h / 24)
            list.append(Insight(level: .attention,
                                title: "已经 \(days) 天没有噗噗啦",
                                message: "多喝水、多吃蔬果和粗粮，起来走一走～"))
        }

        if week.count >= 3 {
            let dist = Dictionary(grouping: week, by: \.status).mapValues(\.count)
            let total = Double(week.count)
            if Double(dist[.loose] ?? 0) / total >= 0.5 {
                list.append(Insight(level: .attention, title: "最近偏稀比较多", message: GutStatus.loose.advice))
            } else if Double(dist[.dry] ?? 0) / total >= 0.5 {
                list.append(Insight(level: .attention, title: "最近偏干比较多", message: GutStatus.dry.advice))
            }
        }

        let perDay = averagePerDay(inLast: 7)
        if perDay > 3 {
            list.append(Insight(level: .attention,
                                title: "次数有点多",
                                message: String(format: "最近 7 天平均每天 %.1f 次，注意饮食卫生和补水。", perDay)))
        }

        if list.isEmpty {
            if let ratio = idealRatio(inLast: 7), ratio >= 0.6 {
                list.append(Insight(level: .good, title: "肠道状态很棒", message: "最近大部分都是理想状态，继续保持！"))
            } else if let last {
                list.append(Insight(level: .info, title: "最近一次：\(last.status.title)", message: last.status.advice))
            }
        }
        return list.sorted { $0.level > $1.level }
    }
}
