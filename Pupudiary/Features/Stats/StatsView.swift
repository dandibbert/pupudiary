import SwiftUI
import Charts

struct StatsView: View {
    @Environment(RecordStore.self) private var store
    @State private var range = 7

    private let ranges = [7, 30, 90]

    var body: some View {
        let stats = store.stats
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("范围", selection: $range) {
                        ForEach(ranges, id: \.self) { Text("\($0) 天").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if stats.records(inLast: range).isEmpty {
                        EmptyHint(title: "这段时间还没有记录", subtitle: "记录几次之后，这里会出现你的肠道小报告", mood: .sleepy)
                            .cardStyle()
                    } else {
                        summaryGrid(stats)
                        insightsCard(stats)
                        dailyChart(stats)
                        statusDonut(stats)
                        typeChart(stats)
                        timeChart(stats)
                    }
                    Text("统计结果仅供参考，不能代替专业医疗建议")
                        .font(.cute(11, .medium))
                        .foregroundStyle(Theme.subtle)
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("趋势")
        }
    }

    // MARK: 关键数字

    private func summaryGrid(_ stats: GutStats) -> some View {
        let count = stats.records(inLast: range).count
        let ratio = stats.idealRatio(inLast: range)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("总次数", "\(count)", "次", symbol: "number", color: Theme.primary)
            tile("日均", String(format: "%.1f", stats.averagePerDay(inLast: range)), "次/天", symbol: "calendar.day.timeline.left", color: GutStatus.loose.color)
            tile("理想占比", ratio.map { "\(Int(($0 * 100).rounded()))" } ?? "-", "%", symbol: "star.fill", color: GutStatus.ideal.color)
            tile("最长间隔", stats.longestGapHours(inLast: range).map { $0.friendlyDuration } ?? "-", "", symbol: "hourglass", color: GutStatus.dry.color)
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.cute(13, .bold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.cute(28, .heavy)).foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(unit).font(.cute(13, .bold)).foregroundStyle(Theme.subtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
    }

    // MARK: 提示

    private func insightsCard(_ stats: GutStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "小结", symbol: "lightbulb.fill")
            ForEach(stats.insights) { InsightCard(insight: $0) }
        }
        .cardStyle()
    }

    // MARK: 每日次数

    private struct DayPoint: Identifiable {
        let id = UUID()
        let day: Date
        let status: GutStatus
        let count: Int
    }

    private func dailyChart(_ stats: GutStats) -> some View {
        let days = stats.days(range)
        let points: [DayPoint] = days.flatMap { d in
            GutStatus.allCases.compactMap { s in
                let c = d.records.filter { $0.status == s }.count
                return c > 0 ? DayPoint(day: d.day, status: s, count: c) : nil
            }
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "每天几次", symbol: "chart.bar.fill")
            Chart(points) { p in
                BarMark(x: .value("日期", p.day, unit: .day),
                        y: .value("次数", p.count))
                    .foregroundStyle(by: .value("状态", p.status.title))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(domain: GutStatus.allCases.map(\.title),
                                       range: GutStatus.allCases.map(\.color))
            .chartXScale(domain: (days.first?.day ?? Date())...(Calendar.current.date(byAdding: .day, value: 1, to: days.last?.day ?? Date()) ?? Date()))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.subtle.opacity(0.2))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : (range == 30 ? 7 : 30))) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: range == 7)
                }
            }
            .chartLegend(position: .bottom, spacing: 10)
            .frame(height: 200)
        }
        .cardStyle()
    }

    // MARK: 状态占比

    private func statusDonut(_ stats: GutStats) -> some View {
        let dist = stats.statusDistribution(inLast: range)
        let total = max(1, dist.values.reduce(0, +))
        let ideal = Double(dist[.ideal] ?? 0) / Double(total)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "状态占比", symbol: "chart.pie.fill")
            HStack(spacing: 20) {
                Chart(GutStatus.allCases) { s in
                    SectorMark(angle: .value("次数", dist[s] ?? 0),
                               innerRadius: .ratio(0.62),
                               angularInset: 2)
                        .foregroundStyle(s.color)
                        .cornerRadius(4)
                }
                .frame(width: 130, height: 130)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(Int((ideal * 100).rounded()))%")
                            .font(.cute(22, .heavy))
                            .foregroundStyle(GutStatus.ideal.color)
                        Text("理想").font(.cute(11, .bold)).foregroundStyle(Theme.subtle)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(GutStatus.allCases) { s in
                        let c = dist[s] ?? 0
                        HStack(spacing: 8) {
                            StatusDot(status: s, size: 10)
                            Text(s.title).font(.cute(14, .bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(c) 次").font(.cute(13, .semibold)).foregroundStyle(Theme.subtle)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: 七型分布

    private func typeChart(_ stats: GutStats) -> some View {
        let dist = stats.typeDistribution(inLast: range)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "形态分布", symbol: "circle.hexagongrid.fill")
            Chart(BristolType.allCases) { t in
                BarMark(x: .value("类型", "\(t.rawValue)"),
                        y: .value("次数", dist[t] ?? 0))
                    .foregroundStyle(t.status.color)
                    .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel() }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.subtle.opacity(0.2))
                    AxisValueLabel()
                }
            }
            .frame(height: 150)
            HStack(spacing: 0) {
                ForEach(BristolType.allCases) { t in
                    BristolIcon(type: t, showFace: false)
                        .frame(width: 22, height: 22)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 24)
        }
        .cardStyle()
    }

    // MARK: 时段

    private func timeChart(_ stats: GutStats) -> some View {
        let dist = stats.timeDistribution(inLast: range)
        let top = dist.max { $0.value < $1.value }?.key
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "常在什么时候", symbol: "clock.fill",
                         trailing: top.map { "最常在\($0.title) \($0.emoji)" })
            Chart(TimeBucket.allCases) { b in
                BarMark(x: .value("时段", b.title),
                        y: .value("次数", dist[b] ?? 0))
                    .foregroundStyle(b == top ? Theme.primary : Theme.primary.opacity(0.35))
                    .cornerRadius(6)
            }
            .chartYAxis(.hidden)
            .frame(height: 130)
        }
        .cardStyle()
    }
}
