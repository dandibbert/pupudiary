import WidgetKit
import SwiftUI
import AppIntents

@main
struct PupudiaryWidgetBundle: WidgetBundle {
    var body: some Widget {
        PupudiaryWidget()
        PupudiaryLockWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            QuickLogControl()
        }
    }
}

// MARK: - 数据

struct PoopEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let today: [PoopRecord]
    let last: PoopRecord?
    let week: [DaySummary]
    let headline: Insight
    let quickType: BristolType

    /// 刚刚（2 分钟内）记录过，用来给按钮一个“已记录”的反馈
    var justLogged: Bool {
        guard let last else { return false }
        return date.timeIntervalSince(last.timestamp) < 120 && date >= last.timestamp
    }

    static func make(at date: Date = Date()) -> PoopEntry {
        let stats = GutStats(records: RecordStorage.load(), now: date)
        return PoopEntry(date: date,
                         todayCount: stats.today.count,
                         today: stats.today,
                         last: stats.last,
                         week: stats.days(7),
                         headline: stats.headline,
                         quickType: SharedSettings.quickDefaultType)
    }

    static var placeholder: PoopEntry {
        let now = Date()
        let samples = [BristolType.t4, .t3, .t4, .t5, .t4, .t2, .t4].enumerated().map { i, t in
            PoopRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86_400 - 3_600)), bristol: t)
        }
        let stats = GutStats(records: samples, now: now)
        return PoopEntry(date: now, todayCount: 1, today: Array(samples.prefix(1)), last: samples.first, week: stats.days(7),
                         headline: stats.headline, quickType: .t4)
    }
}

struct PoopProvider: TimelineProvider {
    func placeholder(in context: Context) -> PoopEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PoopEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .make())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PoopEntry>) -> Void) {
        let now = Date()
        var entries = [PoopEntry.make(at: now)]
        let cal = Calendar.current
        // “刚刚记录”的提示 2 分钟后消失
        if entries[0].justLogged {
            entries.append(.make(at: now.addingTimeInterval(121)))
        }
        // 午夜后今日次数归零
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            entries.append(.make(at: midnight.addingTimeInterval(1)))
        }
        let next = min(now.addingTimeInterval(3600), entries.last?.date ?? now.addingTimeInterval(3600))
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - 桌面小组件

struct PupudiaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PupudiaryWidget", provider: PoopProvider()) { entry in
            PupudiaryWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("噗噗手帐")
        .description("一眼看到今天的状态，点一下就能记录。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PupudiaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PoopEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

private struct LastLine: View {
    let entry: PoopEntry
    var body: some View {
        if let last = entry.last {
            HStack(spacing: 3) {
                Text("上次")
                Text(last.timestamp, style: .relative)
                Text("前")
            }
            .font(.cute(11, .medium))
            .foregroundStyle(Theme.subtle)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text("还没有记录")
                .font(.cute(11, .medium))
                .foregroundStyle(Theme.subtle)
        }
    }
}

private struct QuickButtonLabel: View {
    let justLogged: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: justLogged ? "checkmark" : "sparkles")
            Text(justLogged ? "已记录" : "噗！记一下")
        }
        .font(.cute(14, .heavy))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(justLogged ? GutStatus.ideal.color : Theme.primary, in: Capsule())
    }
}

private struct SmallView: View {
    let entry: PoopEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("今天")
                        .font(.cute(12, .bold))
                        .foregroundStyle(Theme.subtle)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(entry.todayCount)")
                            .font(.cute(34, .heavy))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text("次").font(.cute(13, .bold)).foregroundStyle(Theme.subtle)
                    }
                }
                Spacer(minLength: 0)
                Mascot(mood: entry.justLogged ? .excited : entry.headline.level.mood)
                    .frame(width: 46, height: 46)
            }
            LastLine(entry: entry)
            Spacer(minLength: 0)
            Button(intent: QuickLogIntent(status: .usual)) {
                QuickButtonLabel(justLogged: entry.justLogged)
            }
            .buttonStyle(.plain)
        }
        .widgetURL(URL(string: "pupudiary://home"))
    }
}

private struct MediumView: View {
    let entry: PoopEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Mascot(mood: entry.justLogged ? .excited : entry.headline.level.mood)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("今天").font(.cute(12, .bold)).foregroundStyle(Theme.subtle)
                            Text("\(entry.todayCount)")
                                .font(.cute(26, .heavy))
                                .foregroundStyle(Theme.ink)
                                .contentTransition(.numericText())
                            Text("次").font(.cute(12, .bold)).foregroundStyle(Theme.subtle)
                        }
                        LastLine(entry: entry)
                    }
                }
                Spacer(minLength: 0)
                MiniWeek(days: entry.week)
                Text(entry.justLogged ? "已记录 ✓ 打开 App 可补充细节" : entry.headline.title)
                    .font(.cute(11, .bold))
                    .foregroundStyle(entry.justLogged ? GutStatus.ideal.color : entry.headline.level.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                ForEach(GutStatus.allCases) { s in
                    Button(intent: QuickLogIntent(status: QuickStatus(s))) {
                        HStack(spacing: 4) {
                            BristolIcon(type: s.representative, showFace: false)
                                .frame(width: 18, height: 18)
                            Text(s.title)
                                .font(.cute(13, .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(s.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 96)
        }
        .widgetURL(URL(string: "pupudiary://home"))
    }
}

private struct LargeView: View {
    let entry: PoopEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：吉祥物 + 今日次数 + 一键记录
            HStack(spacing: 10) {
                Mascot(mood: entry.justLogged ? .excited : entry.headline.level.mood)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("今天").font(.cute(13, .bold)).foregroundStyle(Theme.subtle)
                        Text("\(entry.todayCount)")
                            .font(.cute(30, .heavy))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text("次").font(.cute(13, .bold)).foregroundStyle(Theme.subtle)
                    }
                    LastLine(entry: entry)
                }
                Spacer(minLength: 0)
                Button(intent: QuickLogIntent(status: .usual)) {
                    QuickButtonLabel(justLogged: entry.justLogged)
                }
                .buttonStyle(.plain)
                .frame(width: 118)
            }

            // 健康提示
            HStack(spacing: 6) {
                Image(systemName: entry.headline.level.symbol)
                    .foregroundStyle(entry.headline.level.color)
                Text(entry.justLogged ? "已记录 ✓ 打开 App 可补充细节" : entry.headline.title)
                    .font(.cute(12, .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(entry.headline.level.color.opacity(0.14), in: Capsule())

            // 最近 7 天
            HStack(spacing: 0) {
                ForEach(entry.week) { d in
                    VStack(spacing: 3) {
                        ZStack {
                            if let s = d.dominantStatus {
                                Circle().fill(s.color)
                                Text("\(d.count)").font(.cute(12, .heavy)).foregroundStyle(.white)
                            } else {
                                Circle().strokeBorder(Theme.subtle.opacity(0.35), lineWidth: 1.2)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(Calendar.current.isDateInToday(d.day) ? "今" : MiniWeek.weekday(d.day))
                            .font(.cute(10, .bold))
                            .foregroundStyle(Calendar.current.isDateInToday(d.day) ? Theme.primary : Theme.subtle)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // 今天的记录
            VStack(alignment: .leading, spacing: 6) {
                if entry.today.isEmpty {
                    Text("今天还没有记录，点右上角按钮就能记一笔～")
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    ForEach(entry.today.prefix(2)) { r in
                        HStack(spacing: 8) {
                            BristolIcon(type: r.bristol)
                                .frame(width: 24, height: 24)
                            Text(r.bristol.nickname).font(.cute(13, .bold)).foregroundStyle(Theme.ink)
                            Text(r.status.title)
                                .font(.cute(11, .bold))
                                .foregroundStyle(r.status.color)
                            Spacer(minLength: 0)
                            Text(r.timestamp, format: .dateTime.hour().minute())
                                .font(.cute(12, .bold))
                                .foregroundStyle(Theme.subtle)
                                .monospacedDigit()
                        }
                    }
                    if entry.today.count > 2 {
                        Text("还有 \(entry.today.count - 2) 条…").font(.cute(11, .medium)).foregroundStyle(Theme.subtle)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            // 按状态一键记录
            HStack(spacing: 6) {
                ForEach(GutStatus.allCases) { s in
                    Button(intent: QuickLogIntent(status: QuickStatus(s))) {
                        VStack(spacing: 2) {
                            BristolIcon(type: s.representative, showFace: false)
                                .frame(width: 20, height: 20)
                            Text(s.title).font(.cute(12, .heavy)).foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(s.color.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .widgetURL(URL(string: "pupudiary://home"))
    }
}

private struct MiniWeek: View {
    let days: [DaySummary]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(days) { d in
                VStack(spacing: 2) {
                    ZStack {
                        if let s = d.dominantStatus {
                            Circle().fill(s.color)
                            Text("\(d.count)").font(.cute(10, .heavy)).foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Theme.subtle.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(Calendar.current.isDateInToday(d.day) ? "今" : Self.weekday(d.day))
                        .font(.cute(9, .bold))
                        .foregroundStyle(Theme.subtle)
                }
            }
        }
    }

    static func weekday(_ d: Date) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: d) - 1]
    }
}

// MARK: - 锁屏小组件

struct PupudiaryLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PupudiaryLockWidget", provider: PoopProvider()) { entry in
            LockView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("今日噗噗")
        .description("在锁屏上看今天的次数。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PoopEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "leaf.fill").font(.system(size: 11))
                    Text("\(entry.todayCount)").font(.cute(20, .heavy))
                    Text("今天").font(.cute(9, .bold))
                }
            }
            .widgetURL(URL(string: "pupudiary://record"))
        case .accessoryInline:
            Text("🌱 今天噗噗 \(entry.todayCount) 次")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("🌱 噗噗手帐").font(.cute(12, .heavy))
                Text("今天 \(entry.todayCount) 次").font(.cute(15, .heavy))
                if let last = entry.last {
                    HStack(spacing: 2) {
                        Text("上次")
                        Text(last.timestamp, style: .relative)
                        Text("前 · \(last.status.title)")
                    }
                    .font(.cute(11, .medium))
                    .lineLimit(1)
                } else {
                    Text("还没有记录").font(.cute(11, .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "pupudiary://record"))
        }
    }
}

// MARK: - 控制中心（iOS 18）

@available(iOSApplicationExtension 18.0, *)
struct QuickLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.pupudiary.quicklog") {
            ControlWidgetButton(action: QuickLogIntent(status: .usual)) {
                Label("噗！记一下", systemImage: "sparkles")
            }
        }
        .displayName("噗！记一下")
        .description("一键记录一次噗噗。")
    }
}
